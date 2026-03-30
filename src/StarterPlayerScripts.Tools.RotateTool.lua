local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libs = ReplicatedStorage:WaitForChild("Libraries")
local Selection = require(Modules:WaitForChild("Selection"))
local History = require(Modules:WaitForChild("History"))
local GridUtil = require(Modules:WaitForChild("GridUtil"))
local ArcHandles = require(Libs:WaitForChild("ArcHandles"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local rotateRemote = remotes:WaitForChild("RotateBlock")
local batchTransformRemote = remotes:WaitForChild("BatchTransform")

local CELL = GridUtil.CELL_SIZE

local RotateTool = {}
RotateTool.Name = "rotate"

local handles = nil
local disconnectFocus = nil
local isDragging = false

local initialCFrames = {}
local beforeStates = {}
local pivotCF = CFrame.new()
local lastSteps = 0
local dragAxis = "Y"

local function showHandles()
	if handles then handles:Destroy(); handles = nil end
	if not Selection.Focus or not Selection.Focus.Parent then return end

	local adornee = Selection.GetBoundingBoxAdornee() or Selection.Focus
	local blacklist = { adornee }
	for _, m in Selection.GetList() do table.insert(blacklist, m) end
	handles = ArcHandles.new({
		Adornee = adornee,
		Parent = playerGui,
		Color = BrickColor.new("Bright green"),
		ObstacleBlacklist = blacklist,

		OnDragStart = function()
			isDragging = true
			lastSteps = 0
			initialCFrames = {}
			beforeStates = {}

			pivotCF = Selection.Focus:GetPivot()
			for _, model in Selection.GetList() do
				initialCFrames[model] = model:GetPivot()
				local gc = model:GetAttribute("GridCoord")
				beforeStates[model] = { gridCoord = gc }
			end
		end,

		OnDrag = function(axis, angle)
			dragAxis = axis
			local steps = math.round(math.deg(angle) / 90)
			if steps == lastSteps then return end
			lastSteps = steps

			local snapAngle = math.rad(steps * 90)
			local axisVec
			if axis == "X" then axisVec = Vector3.new(1, 0, 0)
			elseif axis == "Y" then axisVec = Vector3.new(0, 1, 0)
			else axisVec = Vector3.new(0, 0, 1) end

			local rotCF = CFrame.fromAxisAngle(axisVec, snapAngle)

			for model, startCF in initialCFrames do
				if model.Parent then
					local offset = pivotCF:ToObjectSpace(startCF)
					model:PivotTo(pivotCF * rotCF * offset)
				end
			end
		end,

		OnDragEnd = function()
			isDragging = false
			local totalSteps = lastSteps

			if totalSteps ~= 0 then
				local transforms = {}
				local savedBefore = {}
				local savedAfter = {}

				for model in initialCFrames do
					if not model.Parent then continue end

					local finalPos = model:GetPivot().Position
					local newGrid = GridUtil.WorldToGrid(finalPos)

					local stepsMod = totalSteps % 4
					if stepsMod < 0 then stepsMod = stepsMod + 4 end

					local ry, rx, rz = 0, 0, 0
					if dragAxis == "Y" then ry = stepsMod
					elseif dragAxis == "X" then rx = stepsMod
					else rz = stepsMod end

					savedBefore[model] = beforeStates[model]
					savedAfter[model] = {
						gridCoord = newGrid,
						rotY = ry, rotX = rx, rotZ = rz,
					}

					table.insert(transforms, {
						model = model,
						gridCoord = newGrid,
						rotY = ry,
						rotX = rx,
						rotZ = rz,
					})
				end

				batchTransformRemote:FireServer(transforms)

				local savedTransformsUndo = {}
				local savedTransformsRedo = transforms

				for model, before in savedBefore do
					if model.Parent and before.gridCoord then
						table.insert(savedTransformsUndo, {
							model = model,
							gridCoord = before.gridCoord,
							rotY = 0, rotX = 0, rotZ = 0,
						})
					end
				end

				History.Add({
					description = "rotate",
					Unapply = function()
						batchTransformRemote:FireServer(savedTransformsUndo)
					end,
					Apply = function()
						batchTransformRemote:FireServer(savedTransformsRedo)
					end,
				})
			end

			initialCFrames = {}
			beforeStates = {}
			lastSteps = 0
			task.defer(showHandles)
		end,
	})
end

function RotateTool:Equip()
	showHandles()
	disconnectFocus = Selection.OnFocusChanged(showHandles)
end

function RotateTool:Unequip()
	if handles then handles:Destroy(); handles = nil end
	if disconnectFocus then disconnectFocus(); disconnectFocus = nil end
end

function RotateTool:Update() end

function RotateTool:OnClick()
	if isDragging then return end
	task.defer(function()
		if isDragging then return end
		Selection.HandleClick()
		showHandles()
	end)
end

function RotateTool:OnRotate(axis: string)
	for _, model in Selection.GetList() do
		rotateRemote:FireServer(model, axis)
	end
	task.defer(showHandles)
end

return RotateTool
