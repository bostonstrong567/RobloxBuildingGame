local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GridUtil = require(Modules:WaitForChild("GridUtil"))
local History = require(Modules:WaitForChild("History"))
local HotbarUI = require(Modules:WaitForChild("HotbarUI"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local placeRemote = remotes:WaitForChild("PlaceBlock")
local removeRemote = remotes:WaitForChild("RemoveBlock")

local CELL = GridUtil.CELL_SIZE
local MAX_REACH = 100
local GHOST_ALPHA = 0.5

local PlaceTool = {}
PlaceTool.Name = "place"

local ghostModel: Model? = nil
local ghostParts: { BasePart } = {}
local selectedName: string? = nil
local rotY = 0
local rotX = 0
local rotZ = 0
local currentGridCoord: Vector3? = nil
local currentWorldPos: Vector3? = nil
local placementValid = false
local isSubGrid = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateFilter()
	local list = {}
	if player.Character then table.insert(list, player.Character) end
	if ghostModel then table.insert(list, ghostModel) end
	rayParams.FilterDescendantsInstances = list
end

local function wrapAsModel(template: Instance): Model?
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
		if first then clone.PrimaryPart = first
		else clone:Destroy(); return nil end
	end

	local cf = clone:GetBoundingBox()
	if clone.PrimaryPart then
		clone.PrimaryPart.PivotOffset = clone.PrimaryPart.CFrame:ToObjectSpace(cf)
	end
	return clone
end

local function clearGhost()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
		ghostParts = {}
	end
	currentGridCoord = nil
	currentWorldPos = nil
	placementValid = false
end

local function createGhost(itemName: string)
	clearGhost()
	local template = GridUtil.FindPlaceable(itemName)
	if not template then return end

	local clone = wrapAsModel(template)
	if not clone then return end

	ghostParts = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Anchored = true
			d.Transparency = GHOST_ALPHA
			table.insert(ghostParts, d)
		end
	end

	clone.Parent = workspace
	ghostModel = clone
	isSubGrid = GridUtil.IsSubGridItem(itemName)
	updateFilter()
end

local function computePlacement(): (Vector3?, CFrame?)
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	updateFilter()

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_REACH, rayParams)
	if not result then return nil, nil end

	if isSubGrid then
		local rot = GridUtil.RotationCFrame(rotY, rotX, rotZ)
		local _, rawSize = ghostModel:GetBoundingBox()
		local rotatedSize = (rot * CFrame.new(rawSize / 2)).Position * 2
		rotatedSize = Vector3.new(math.abs(rotatedSize.X), math.abs(rotatedSize.Y), math.abs(rotatedSize.Z))
		local snappedPos = GridUtil.ComputeSubGridPlacement(result.Position, result.Normal, rotatedSize)
		return snappedPos, CFrame.new(snappedPos) * rot
	else
		local placePos = result.Position + result.Normal * (CELL / 2)
		local gridCoord = Vector3.new(
			math.floor(placePos.X / CELL),
			math.floor(placePos.Y / CELL),
			math.floor(placePos.Z / CELL)
		)

		local gx = gridCoord.X * CELL + CELL / 2
		local gy = gridCoord.Y * CELL + CELL / 2
		local gz = gridCoord.Z * CELL + CELL / 2

		return gridCoord, CFrame.new(gx, gy, gz) * GridUtil.RotationCFrame(rotY, rotX, rotZ)
	end
end

function PlaceTool:Equip()
	if selectedName then
		createGhost(selectedName)
	end
end

function PlaceTool:Unequip()
	clearGhost()
end

function PlaceTool:Update(dt)
	if ghostModel and ghostModel.PrimaryPart then
		local coord, cf = computePlacement()
		if not coord or not cf then
			for _, p in ghostParts do p.Transparency = 1 end
			placementValid = false
			currentGridCoord = nil
			currentWorldPos = nil
		else
			local overlapping = false
			if isSubGrid then
				currentWorldPos = coord
				currentGridCoord = nil
				local _, modelSize = ghostModel:GetBoundingBox()
				overlapping = GridUtil.CheckBoundsOverlap(coord, modelSize)
			else
				currentGridCoord = coord
				currentWorldPos = nil
			end

			for _, p in ghostParts do
				p.Transparency = GHOST_ALPHA
				p.Color = overlapping and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(100, 255, 100)
			end
			ghostModel:PivotTo(cf)
			placementValid = not overlapping
		end
	end
	HotbarUI.SpinSelected(dt)
end

function PlaceTool:OnClick()
	if not placementValid or not selectedName then return end

	if isSubGrid then
		if not currentWorldPos then return end
		placeRemote:FireServer(selectedName, currentWorldPos, rotY, rotX, true)

		History.Add({
			description = "place " .. selectedName,
			worldPos = currentWorldPos,
			itemName = selectedName,
			isSubGrid = true,
			Unapply = function(self)
				removeRemote:FireServer(self.worldPos, true)
			end,
			Apply = function(self)
				placeRemote:FireServer(self.itemName, self.worldPos, rotY, rotX, true)
			end,
		})
	else
		if not currentGridCoord then return end
		placeRemote:FireServer(selectedName, currentGridCoord, rotY, rotX)

		History.Add({
			description = "place " .. selectedName,
			gridCoord = currentGridCoord,
			itemName = selectedName,
			Unapply = function(self)
				removeRemote:FireServer(self.gridCoord)
			end,
			Apply = function(self)
				placeRemote:FireServer(self.itemName, self.gridCoord, rotY, rotX)
			end,
		})
	end
end

function PlaceTool:OnRightClick()
	if currentWorldPos and isSubGrid then
		removeRemote:FireServer(currentWorldPos, true)
	elseif currentGridCoord then
		removeRemote:FireServer(currentGridCoord)
	end
end

function PlaceTool:OnRotate(axis: string)
	if axis == "Y" then
		rotY = (rotY + 1) % 4
	elseif axis == "X" then
		rotX = (rotX + 1) % 4
	elseif axis == "Z" then
		rotZ = (rotZ + 1) % 4
	end
end

function PlaceTool:GetGridCoord(): Vector3?
	return currentGridCoord
end

function PlaceTool.SetItem(name: string?)
	selectedName = name
	if name then
		createGhost(name)
	else
		clearGhost()
	end
end

function PlaceTool.GetItem(): string?
	return selectedName
end

return PlaceTool
