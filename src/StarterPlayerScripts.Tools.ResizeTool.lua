local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libs = ReplicatedStorage:WaitForChild("Libraries")
local Selection = require(Modules:WaitForChild("Selection"))
local History = require(Modules:WaitForChild("History"))
local GridUtil = require(Modules:WaitForChild("GridUtil"))
local Handles = require(Libs:WaitForChild("Handles"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local resizeRemote = remotes:WaitForChild("ResizeBlock")

local CELL = GridUtil.CELL_SIZE

local ResizeTool = {}
ResizeTool.Name = "rescale"

local handles = nil
local disconnectFocus = nil
local isDragging = false

local initialSize = nil
local initialCF = nil
local targetModel = nil
local targetPrimary = nil
local lastGridUnits = 0
local dragFaceName = nil

local SIDE_TO_VEC = {
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
}

local function showHandles()
	if handles then handles:Destroy(); handles = nil end
	if not Selection.Focus or not Selection.Focus.Parent then return end

	targetModel = Selection.Focus
	targetPrimary = targetModel.PrimaryPart or targetModel:FindFirstChildWhichIsA("BasePart")
	if not targetPrimary then return end

	handles = Handles.new({
		Adornee = targetModel,
		Parent = playerGui,
		Color = Color3.fromRGB(0, 170, 255),
		ObstacleBlacklist = { targetModel },

		OnDragStart = function()
			isDragging = true
			lastGridUnits = 0
			initialSize = targetPrimary.Size
			initialCF = targetModel:GetPivot()
		end,

		OnDrag = function(side, distance)
			local axisVec = SIDE_TO_VEC[side]
			if not axisVec or not initialSize then return end

			dragFaceName = side.Name
			local gridUnits = math.round(distance / CELL)
			if gridUnits == lastGridUnits then return end
			lastGridUnits = gridUnits

			local axisAbs = Vector3.new(math.abs(axisVec.X), math.abs(axisVec.Y), math.abs(axisVec.Z))
			local newSize = initialSize + axisAbs * (gridUnits * CELL)

			local minAxis = (newSize * axisAbs).Magnitude
			if minAxis < CELL then
				gridUnits = math.ceil((CELL - (initialSize * axisAbs).Magnitude) / CELL)
				newSize = initialSize + axisAbs * (gridUnits * CELL)
				lastGridUnits = gridUnits
			end

			targetPrimary.Size = newSize
			local posOffset = axisVec * (gridUnits * CELL / 2)
			targetModel:PivotTo(initialCF + posOffset)
		end,

		OnDragEnd = function()
			isDragging = false
			local finalGridUnits = lastGridUnits

			if finalGridUnits ~= 0 and dragFaceName then
				resizeRemote:FireServer(targetModel, dragFaceName, finalGridUnits)

				local savedFace = dragFaceName
				local savedUnits = finalGridUnits
				local savedModel = targetModel

				History.Add({
					description = "resize",
					Unapply = function()
						if savedModel.Parent then
							resizeRemote:FireServer(savedModel, savedFace, -savedUnits)
						end
					end,
					Apply = function()
						if savedModel.Parent then
							resizeRemote:FireServer(savedModel, savedFace, savedUnits)
						end
					end,
				})
			else
				if initialSize and targetPrimary then
					targetPrimary.Size = initialSize
				end
				if initialCF and targetModel and targetModel.Parent then
					targetModel:PivotTo(initialCF)
				end
			end

			initialSize = nil
			initialCF = nil
			lastGridUnits = 0
			dragFaceName = nil
			task.defer(showHandles)
		end,
	})
end

function ResizeTool:Equip()
	showHandles()
	disconnectFocus = Selection.OnFocusChanged(showHandles)
end

function ResizeTool:Unequip()
	if handles then handles:Destroy(); handles = nil end
	if disconnectFocus then disconnectFocus(); disconnectFocus = nil end
end

function ResizeTool:Update() end

function ResizeTool:OnClick()
	if isDragging then return end
	task.defer(function()
		if isDragging then return end
		Selection.HandleClick()
		showHandles()
	end)
end

function ResizeTool:OnRotate(axis: string)
	local rotateRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("RotateBlock")
	if not rotateRemote then return end
	for _, model in Selection.GetList() do
		rotateRemote:FireServer(model, axis)
	end
	task.defer(showHandles)
end

return ResizeTool
