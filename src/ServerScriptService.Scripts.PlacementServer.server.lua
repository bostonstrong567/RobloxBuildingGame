--[[
	PlacementServer — Handles placement/removal/save/load remotes.
	Place in: ServerScriptService > Scripts > PlacementServer (Script)

	Build-then-Assemble: all blocks start anchored.
	Activate/deactivate via GUI button (ActivateToggle remote).
	Save/load via DataStoreService (GetSaves, SaveBuild, LoadBuild remotes).
]]

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RepModules = ReplicatedStorage:WaitForChild("Modules")
local SSModules = ServerScriptService:WaitForChild("Modules")
local GridUtil = require(RepModules:WaitForChild("GridUtil"))
local MechanicsService = require(SSModules:WaitForChild("MechanicsService"))
local StateManager = require(SSModules:WaitForChild("StateManager"))
local GlueService = require(SSModules:WaitForChild("GlueService"))
local SaveService = require(SSModules:WaitForChild("SaveService"))

local placeables = ReplicatedStorage:WaitForChild("Placeables")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local placeRemote = remotes:WaitForChild("PlaceBlock")
local glueRemote = remotes:WaitForChild("GlueBlocks")
local unglueRemote = remotes:WaitForChild("UnglueBlocks")
local removeRemote = remotes:WaitForChild("RemoveBlock")
local activateRemote = remotes:WaitForChild("ActivateToggle")
local getSavesRemote = remotes:WaitForChild("GetSaves")
local saveBuildRemote = remotes:WaitForChild("SaveBuild")
local loadBuildRemote = remotes:WaitForChild("LoadBuild")
local moveBlockRemote = remotes:WaitForChild("MoveBlock")
local rotateBlockRemote = remotes:WaitForChild("RotateBlock")

local resizeBlockRemote = remotes:FindFirstChild("ResizeBlock")
if not resizeBlockRemote then
	resizeBlockRemote = Instance.new("RemoteEvent")
	resizeBlockRemote.Name = "ResizeBlock"
	resizeBlockRemote.Parent = remotes
end

local batchTransformRemote = remotes:FindFirstChild("BatchTransform")
if not batchTransformRemote then
	batchTransformRemote = Instance.new("RemoteEvent")
	batchTransformRemote.Name = "BatchTransform"
	batchTransformRemote.Parent = remotes
end

local setDirectionRemote = remotes:FindFirstChild("SetDirection")
if not setDirectionRemote then
	setDirectionRemote = Instance.new("RemoteEvent")
	setDirectionRemote.Name = "SetDirection"
	setDirectionRemote.Parent = remotes
end

local CELL = 2
local PLACED_TAG = "PlacedBlock"

local placedFolder = workspace:FindFirstChild("PlacedBlocks")
if not placedFolder then
	placedFolder = Instance.new("Folder")
	placedFolder.Name = "PlacedBlocks"
	placedFolder.Parent = workspace
end

local occupancy = {}

local function cellCenter(gridCoord: Vector3): Vector3
	return Vector3.new(
		gridCoord.X * CELL + CELL / 2,
		gridCoord.Y * CELL + CELL / 2,
		gridCoord.Z * CELL + CELL / 2
	)
end

------------------------------------------------------------
-- Core placement (used by both handlePlace and loadBuild)
------------------------------------------------------------

local function findTemplate(itemName: string): Instance?
	local direct = placeables:FindFirstChild(itemName)
	if direct and not direct:IsA("Folder") then return direct end

	for _, desc in placeables:GetDescendants() do
		if desc.Name == itemName and not desc:IsA("Folder") then
			return desc
		end
	end
	return nil
end

local function cloneTemplate(template: Instance): Model?
	local clone: Model

	if template:IsA("Model") then
		clone = template:Clone()
	elseif template:IsA("BasePart") then
		local m = Instance.new("Model")
		m.Name = template.Name
		local p = template:Clone()
		p.Parent = m
		m.PrimaryPart = p
		clone = m
	else
		return nil
	end

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then
			clone.PrimaryPart = first
		else
			clone:Destroy()
			return nil
		end
	end

	local cf = clone:GetBoundingBox()
	if clone.PrimaryPart then
		clone.PrimaryPart.PivotOffset = clone.PrimaryPart.CFrame:ToObjectSpace(cf)
	end

	return clone
end

local function placeBlockInternal(plr: Player, itemName: string, gridCoord: Vector3, ry: number, rx: number): boolean
	local template = findTemplate(itemName)
	if not template then return false end

	local key = GridUtil.ToKey(gridCoord)
	if occupancy[key] then return false end

	local clone = cloneTemplate(template)
	if not clone then return false end

	local pos = cellCenter(gridCoord)
	local rot = GridUtil.RotationCFrame(ry, rx)
	clone:PivotTo(CFrame.new(pos) * rot)

	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	CollectionService:AddTag(clone, PLACED_TAG)
	clone:SetAttribute("GridCoord", gridCoord)
	clone:SetAttribute("PlacedBy", plr.UserId)

	clone.Parent = placedFolder
	occupancy[key] = { instance = clone, owner = plr }

	StateManager.Register(clone, gridCoord, plr.UserId, ry, rx)
	MechanicsService.Apply(clone)
	GlueService.AutoGlueToNeighbors(clone)

	return true
end

local function placeSubGridInternal(plr: Player, itemName: string, worldPos: Vector3, ry: number, rx: number): boolean
	local template = findTemplate(itemName)
	if not template then return false end

	local clone = cloneTemplate(template)
	if not clone then return false end

	local rot = GridUtil.RotationCFrame(ry, rx)
	clone:PivotTo(CFrame.new(worldPos) * rot)

	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end

	CollectionService:AddTag(clone, PLACED_TAG)
	clone:SetAttribute("WorldPos", worldPos)
	clone:SetAttribute("SubGrid", true)
	clone:SetAttribute("PlacedBy", plr.UserId)

	clone.Parent = placedFolder

	StateManager.Register(clone, worldPos, plr.UserId, ry, rx)
	MechanicsService.Apply(clone)
	GlueService.AutoGlueToNeighbors(clone)

	return true
end

------------------------------------------------------------
-- Clear all blocks for a player
------------------------------------------------------------

local function clearPlayerBlocks(plr: Player)
	local toRemove = {}
	for key, data in occupancy do
		if data.owner == plr then
			table.insert(toRemove, key)
		end
	end

	for _, key in toRemove do
		local data = occupancy[key]
		if data then
			StateManager.Unregister(data.instance)
			data.instance:Destroy()
			occupancy[key] = nil
		end
	end

	local subGridToRemove = {}
	for _, model in placedFolder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("SubGrid") and model:GetAttribute("PlacedBy") == plr.UserId then
			table.insert(subGridToRemove, model)
		end
	end

	for _, model in subGridToRemove do
		StateManager.Unregister(model)
		model:Destroy()
	end
end

------------------------------------------------------------
-- Serialize current build for a player
------------------------------------------------------------

local function serializePlayerBlocks(plr: Player): {}
	local blocks = {}

	for _, data in occupancy do
		if data.owner == plr then
			local model = data.instance
			local gridCoord = model:GetAttribute("GridCoord")
			local state = StateManager.Get(model)
			if gridCoord and state then
				table.insert(blocks, {
					item = model.Name,
					gx = gridCoord.X,
					gy = gridCoord.Y,
					gz = gridCoord.Z,
					ry = state.rotation.y,
					rx = state.rotation.x,
					dir = model:GetAttribute("MotorDirection") or 1,
				})
			end
		end
	end

	for _, model in placedFolder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("SubGrid") and model:GetAttribute("PlacedBy") == plr.UserId then
			local wp = model:GetAttribute("WorldPos")
			local state = StateManager.Get(model)
			if wp and state then
				table.insert(blocks, {
					item = model.Name,
					gx = wp.X,
					gy = wp.Y,
					gz = wp.Z,
					ry = state.rotation.y,
					rx = state.rotation.x,
					subGrid = true,
				})
			end
		end
	end

	return blocks
end

------------------------------------------------------------
-- Remote handlers: placement
------------------------------------------------------------

local function handlePlace(plr: Player, itemName: string, coordOrPos: Vector3, ry: number, rx: number, isSubGrid: boolean?)
	if MechanicsService.IsPlaying(plr) then return end
	if typeof(itemName) ~= "string" then return end
	if typeof(coordOrPos) ~= "Vector3" then return end
	if typeof(ry) ~= "number" then return end
	if typeof(rx) ~= "number" then return end

	if isSubGrid then
		if placeSubGridInternal(plr, itemName, coordOrPos, ry, rx) then
			print("[PlacementServer] placed sub-grid", itemName, "at", coordOrPos, "by", plr.Name)
		end
	else
		if placeBlockInternal(plr, itemName, coordOrPos, ry, rx) then
			print("[PlacementServer] placed", itemName, "at grid", coordOrPos, "by", plr.Name)
		end
	end
end

local function handleRemove(plr: Player, coordOrPos: Vector3, isSubGrid: boolean?)
	if MechanicsService.IsPlaying(plr) then return end
	if typeof(coordOrPos) ~= "Vector3" then return end

	if isSubGrid then
		for _, model in placedFolder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("SubGrid") then
				local wp = model:GetAttribute("WorldPos")
				if wp and (wp - coordOrPos).Magnitude < 0.5 then
					StateManager.Unregister(model)
					model:Destroy()
					return
				end
			end
		end
	else
		local key = GridUtil.ToKey(coordOrPos)
		local data = occupancy[key]
		if not data then return end

		MechanicsService.OnBlockRemoved(data.instance)
		StateManager.Unregister(data.instance)
		data.instance:Destroy()
		occupancy[key] = nil
	end
end

local function handleGlue(plr: Player, partA: BasePart, partB: BasePart)
	if not partA or not partB then return end
	if not partA:IsA("BasePart") or not partB:IsA("BasePart") then return end
	if not partA:IsDescendantOf(placedFolder) then return end
	if not partB:IsDescendantOf(placedFolder) then return end

	GlueService.GlueParts(partA, partB)
end

local function handleUnglue(plr: Player, partA: BasePart, partB: BasePart)
	if not partA or not partB then return end
	if not partA:IsA("BasePart") or not partB:IsA("BasePart") then return end
	if not partA:IsDescendantOf(placedFolder) then return end
	if not partB:IsDescendantOf(placedFolder) then return end

	GlueService.UnglueParts(partA, partB)
end

------------------------------------------------------------
-- Remote handlers: activate/deactivate
------------------------------------------------------------

activateRemote.OnServerInvoke = function(plr, targetOrCmd, param)
	-- Global Play/Build toggle
	if targetOrCmd == "play" then
		local ok = MechanicsService.EnterPlayMode(plr, occupancy, placeBlockInternal, placeSubGridInternal)
		print("[PlacementServer]", plr.Name, "entered Play Mode:", ok)
		return ok
	end

	if targetOrCmd == "build" then
		local ok = MechanicsService.ExitPlayMode(plr)
		print("[PlacementServer]", plr.Name, "returned to Build Mode:", ok)
		return ok
	end

	-- Click on a RemovablePart during Play Mode
	local targetPart = targetOrCmd
	if not targetPart or not targetPart:IsA("BasePart") then return nil end
	if not targetPart:IsDescendantOf(placedFolder) then return nil end

	local model = targetPart:FindFirstAncestorWhichIsA("Model")
	if not model then return nil end
	if not MechanicsService.IsActivatable(model) then return nil end

	local behavior = MechanicsService.GetBehavior(model)

	if not MechanicsService.IsPlaying(plr) then return nil end

	if behavior == "remove" then
		MechanicsService.RemoveDuringPlay(model, plr, occupancy)
		return "removed"
	end

	if behavior == "toggle" then
		return "toggled"
	end

	return nil
end

------------------------------------------------------------
-- Remote handlers: save/load
------------------------------------------------------------

getSavesRemote.OnServerInvoke = function(plr)
	return SaveService.GetSlots(plr.UserId)
end

saveBuildRemote.OnServerInvoke = function(plr, slotId, slotName)
	if slotId ~= nil and typeof(slotId) ~= "number" then return false end
	if typeof(slotName) ~= "string" then return false end

	local blocks = serializePlayerBlocks(plr)
	local ok, err = SaveService.SaveSlot(plr.UserId, slotId, slotName, blocks)

	if ok then
		print("[PlacementServer]", plr.Name, "saved", #blocks, "blocks to slot", slotId or "new")
	else
		warn("[PlacementServer] save failed for", plr.Name, ":", err)
	end

	return ok
end

loadBuildRemote.OnServerInvoke = function(plr, slotId)
	if typeof(slotId) ~= "number" then return false end

	local slotData = SaveService.LoadSlot(plr.UserId, slotId)
	if not slotData or not slotData.blocks then return false end

	-- Clear existing build
	clearPlayerBlocks(plr)

	local placed = 0
	for _, block in slotData.blocks do
		local coord = Vector3.new(block.gx, block.gy, block.gz)
		local ok = false
		if block.subGrid then
			ok = placeSubGridInternal(plr, block.item, coord, block.ry or 0, block.rx or 0)
		else
			ok = placeBlockInternal(plr, block.item, coord, block.ry or 0, block.rx or 0)
		end
		if ok then
			placed += 1
			if block.dir and block.dir ~= 1 then
				local model = placedFolder:FindFirstChild(block.item)
				if model then
					model:SetAttribute("MotorDirection", block.dir)
				end
			end
		end
	end

	print("[PlacementServer]", plr.Name, "loaded", placed, "/", #slotData.blocks, "blocks from slot", slotId)
	return true
end

------------------------------------------------------------
-- Remote handlers: move/rotate
------------------------------------------------------------

moveBlockRemote.OnServerEvent:Connect(function(plr, model, newGridCoord)
	if MechanicsService.IsPlaying(plr) then return end

	if not model or not model:IsA("Model") then
		print("[PlacementServer] MoveBlock REJECTED: not a model")
		return
	end
	if not model:IsDescendantOf(placedFolder) then
		print("[PlacementServer] MoveBlock REJECTED: not in PlacedBlocks")
		return
	end
	if typeof(newGridCoord) ~= "Vector3" then
		print("[PlacementServer] MoveBlock REJECTED: newGridCoord not Vector3, got", typeof(newGridCoord))
		return
	end

	local oldGridCoord = model:GetAttribute("GridCoord")
	if not oldGridCoord then
		print("[PlacementServer] MoveBlock REJECTED: no GridCoord attribute")
		return
	end

	local newKey = GridUtil.ToKey(newGridCoord)
	if occupancy[newKey] then
		print("[PlacementServer] MoveBlock REJECTED: target occupied at", newKey)
		return
	end

	local oldKey = GridUtil.ToKey(oldGridCoord)

	-- Move model to new grid position, keep same rotation
	local state = StateManager.Get(model)
	local ry = state and state.rotation.y or 0
	local rx = state and state.rotation.x or 0

	local rot = GridUtil.RotationCFrame(ry, rx)
	model:PivotTo(CFrame.new(cellCenter(newGridCoord)) * rot)

	model:SetAttribute("GridCoord", newGridCoord)
	occupancy[oldKey] = nil
	occupancy[newKey] = { instance = model, owner = plr }

	if state then
		state.gridCoord = newGridCoord
	end

	print("[PlacementServer] moved", model.Name, "from", oldGridCoord, "to", newGridCoord)
end)

rotateBlockRemote.OnServerEvent:Connect(function(plr, model, axis)
	if MechanicsService.IsPlaying(plr) then return end
	if not model or not model:IsA("Model") then return end
	if not model:IsDescendantOf(placedFolder) then return end

	local state = StateManager.Get(model)
	if not state then return end

	if axis == "Y" then
		state.rotation.y = (state.rotation.y + 1) % 4
	elseif axis == "X" then
		state.rotation.x = (state.rotation.x + 1) % 4
	elseif axis == "Z" then
		if not state.rotation.z then state.rotation.z = 0 end
		state.rotation.z = (state.rotation.z + 1) % 4
	else
		return
	end

	local rot = GridUtil.RotationCFrame(state.rotation.y, state.rotation.x, state.rotation.z or 0)

	local isSubGrid = model:GetAttribute("SubGrid")
	local pos
	if isSubGrid then
		local wp = model:GetAttribute("WorldPos")
		if not wp then return end
		pos = wp
	else
		local gridCoord = model:GetAttribute("GridCoord")
		if not gridCoord then return end
		pos = cellCenter(gridCoord)
	end
	model:PivotTo(CFrame.new(pos) * rot)
end)

------------------------------------------------------------
-- Remote handler: resize
------------------------------------------------------------

local FACE_TO_VEC = {
	Right  = Vector3.new(1, 0, 0),
	Left   = Vector3.new(-1, 0, 0),
	Top    = Vector3.new(0, 1, 0),
	Bottom = Vector3.new(0, -1, 0),
	Front  = Vector3.new(0, 0, -1),
	Back   = Vector3.new(0, 0, 1),
}

resizeBlockRemote.OnServerEvent:Connect(function(plr, model, faceName, gridUnits)
	if MechanicsService.IsPlaying(plr) then return end
	if not model or not model:IsA("Model") then return end
	if not model:IsDescendantOf(placedFolder) then return end
	if typeof(faceName) ~= "string" then return end
	if typeof(gridUnits) ~= "number" then return end
	if gridUnits == 0 then return end

	local axisVec = FACE_TO_VEC[faceName]
	if not axisVec then return end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then return end

	local axisAbs = Vector3.new(math.abs(axisVec.X), math.abs(axisVec.Y), math.abs(axisVec.Z))

	local currentSize = primary.Size
	local newAxisSize = (currentSize * axisAbs).Magnitude + gridUnits * CELL
	if newAxisSize < CELL then return end

	primary.Size = currentSize + axisAbs * (gridUnits * CELL)

	local posOffset = axisVec * (gridUnits * CELL / 2)
	model:PivotTo(model:GetPivot() + posOffset)

	print("[PlacementServer] resized", model.Name, "face:", faceName, "by", gridUnits, "cells")
end)

------------------------------------------------------------
-- Remote handler: batch transform (group rotate/move)
------------------------------------------------------------

batchTransformRemote.OnServerEvent:Connect(function(plr, transforms)
	if MechanicsService.IsPlaying(plr) then return end
	if typeof(transforms) ~= "table" then return end

	local movingModels = {}
	for _, entry in transforms do
		if typeof(entry) ~= "table" then return end
		local model = entry.model
		if not model or not model:IsA("Model") then return end
		if not model:IsDescendantOf(placedFolder) then return end
		movingModels[model] = true
	end

	local oldKeys = {}
	for model in movingModels do
		local gc = model:GetAttribute("GridCoord")
		if gc then
			local key = GridUtil.ToKey(gc)
			oldKeys[key] = model
		end
	end

	for key, model in oldKeys do
		if occupancy[key] and occupancy[key].instance == model then
			occupancy[key] = nil
		end
	end

	local success = true
	local newEntries = {}

	for _, entry in transforms do
		local model = entry.model
		local newGrid = entry.gridCoord
		if typeof(newGrid) ~= "Vector3" then
			success = false
			break
		end

		local newKey = GridUtil.ToKey(newGrid)
		if occupancy[newKey] and not movingModels[occupancy[newKey].instance] then
			success = false
			break
		end

		table.insert(newEntries, { model = model, gridCoord = newGrid, key = newKey, entry = entry })
	end

	if not success then
		for key, model in oldKeys do
			local gc = model:GetAttribute("GridCoord")
			if gc then
				occupancy[GridUtil.ToKey(gc)] = { instance = model, owner = plr }
			end
		end
		return
	end

	for _, ne in newEntries do
		local model = ne.model
		local newGrid = ne.gridCoord
		local ry = ne.entry.rotY or 0
		local rx = ne.entry.rotX or 0
		local rz = ne.entry.rotZ or 0

		local state = StateManager.Get(model)
		if state then
			state.rotation.y = ry
			state.rotation.x = rx
			if rz ~= 0 then state.rotation.z = rz end
			state.gridCoord = newGrid
		end

		local rot = GridUtil.RotationCFrame(ry, rx, rz)
		model:PivotTo(CFrame.new(cellCenter(newGrid)) * rot)
		model:SetAttribute("GridCoord", newGrid)
		occupancy[ne.key] = { instance = model, owner = plr }
	end
end)

------------------------------------------------------------
-- Remote handler: set motor direction
------------------------------------------------------------

setDirectionRemote.OnServerEvent:Connect(function(plr, model, direction)
	if not model or not model:IsA("Model") then return end
	if not model:IsDescendantOf(placedFolder) then return end
	if direction ~= 1 and direction ~= -1 then return end

	model:SetAttribute("MotorDirection", direction)
end)

------------------------------------------------------------
-- Connect remotes
------------------------------------------------------------

placeRemote.OnServerEvent:Connect(handlePlace)
removeRemote.OnServerEvent:Connect(handleRemove)
glueRemote.OnServerEvent:Connect(handleGlue)
unglueRemote.OnServerEvent:Connect(handleUnglue)

print("[PlacementServer] ready")
