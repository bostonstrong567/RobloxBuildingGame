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
local moveRemote = remotes:WaitForChild("MoveBlock")
local rotateRemote = remotes:WaitForChild("RotateBlock")

local CELL = GridUtil.CELL_SIZE

local MoveTool = {}
MoveTool.Name = "move"

local handles = nil
local disconnectFocus = nil
local isDragging = false

local initialCFrames = {}
local beforeGridCoords = {}

local SIDE_TO_AXIS = {
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

	local adornee = Selection.GetBoundingBoxAdornee() or Selection.Focus
	local blacklist = { adornee }
	for _, m in Selection.GetList() do table.insert(blacklist, m) end
	handles = Handles.new({
		Adornee = adornee,
		Parent = playerGui,
		Color = Color3.fromRGB(255, 170, 0),
		ObstacleBlacklist = blacklist,

		OnDragStart = function()
			isDragging = true
			initialCFrames = {}
			beforeGridCoords = {}
			for _, model in Selection.GetList() do
				initialCFrames[model] = model:GetPivot()
				beforeGridCoords[model] = model:GetAttribute("GridCoord")
			end
		end,

		OnDrag = function(side, distance)
			local axisDir = SIDE_TO_AXIS[side]
			if not axisDir then return end

			local snapped = math.round(distance / CELL) * CELL
			local gridSteps = math.round(snapped / CELL)
			local gridOffset = axisDir * gridSteps

			if not GridUtil.CanMoveGroup(Selection.GetList(), gridOffset) then
				return
			end

			local offset = axisDir * snapped
			for model, startCF in initialCFrames do
				if model.Parent then
					model:PivotTo(startCF + offset)
				end
			end
		end,

		OnDragEnd = function()
			isDragging = false

			local moved = false
			for model in initialCFrames do
				if model.Parent then
					local worldPos = model:GetPivot().Position
					local newGrid = GridUtil.WorldToGrid(worldPos)
					local oldGrid = beforeGridCoords[model]
					if oldGrid and newGrid ~= oldGrid then
						moved = true
						break
					end
				end
			end

			if moved then
				local savedBefore = {}
				local savedAfter = {}
				local savedModels = {}

				for model in initialCFrames do
					if model.Parent then
						local newGrid = GridUtil.WorldToGrid(model:GetPivot().Position)
						local oldGrid = beforeGridCoords[model]
						savedBefore[model] = oldGrid
						savedAfter[model] = newGrid
						table.insert(savedModels, model)

						if oldGrid and newGrid ~= oldGrid then
							moveRemote:FireServer(model, newGrid)
						end
					end
				end

				History.Add({
					description = "move",
					Unapply = function()
						for _, model in savedModels do
							if model.Parent and savedBefore[model] then
								moveRemote:FireServer(model, savedBefore[model])
							end
						end
					end,
					Apply = function()
						for _, model in savedModels do
							if model.Parent and savedAfter[model] then
								moveRemote:FireServer(model, savedAfter[model])
							end
						end
					end,
				})
			else
				for model, startCF in initialCFrames do
					if model.Parent then
						model:PivotTo(startCF)
					end
				end
			end

			initialCFrames = {}
			beforeGridCoords = {}
			task.defer(showHandles)
		end,
	})
end

function MoveTool:Equip()
	showHandles()
	disconnectFocus = Selection.OnFocusChanged(showHandles)
end

function MoveTool:Unequip()
	if handles then handles:Destroy(); handles = nil end
	if disconnectFocus then disconnectFocus(); disconnectFocus = nil end
end

function MoveTool:Update() end

function MoveTool:OnClick()
	if isDragging then return end
	task.defer(function()
		if isDragging then return end
		Selection.HandleClick()
		showHandles()
	end)
end

function MoveTool:OnRotate(axis: string)
	for _, model in Selection.GetList() do
		rotateRemote:FireServer(model, axis)
	end
	task.defer(showHandles)
end

return MoveTool
