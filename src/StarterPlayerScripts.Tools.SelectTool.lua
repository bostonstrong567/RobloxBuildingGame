local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libs = ReplicatedStorage:WaitForChild("Libraries")
local Selection = require(Modules:WaitForChild("Selection"))
local GridUtil = require(Modules:WaitForChild("GridUtil"))
local History = require(Modules:WaitForChild("History"))
local Handles = require(Libs:WaitForChild("Handles"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local moveRemote = remotes:WaitForChild("MoveBlock")

local CELL = GridUtil.CELL_SIZE

local SelectTool = {}
SelectTool.Name = "select"

local hoverHighlight: Highlight? = nil
local dragFrame: Frame? = nil
local dragStart: Vector2? = nil
local isBoxDragging = false
local DRAG_THRESHOLD = 5
local rectGui = nil

local moveHandles = nil
local disconnectChanged = nil
local isHandleDragging = false
local initialCFrames = {}
local beforeGridCoords = {}

local isFreeDragging = false
local freeDragLastTargetGrid = nil
local freeDragInitialCFrames = {}
local freeDragBeforeGrids = {}
local freeDragFocusGridOffset = {} -- { [Model]: Vector3 } offset from focus grid
local clickedSelectedModel = nil

local SIDE_TO_AXIS = {
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
}

local function createDragFrame()
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(100, 170, 255)
	frame.BackgroundTransparency = 0.7
	frame.BorderSizePixel = 0
	frame.ZIndex = 10

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 170, 255)
	stroke.Thickness = 1
	stroke.Parent = frame

	local gui = Instance.new("ScreenGui")
	gui.Name = "SelectionRect"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = playerGui
	frame.Parent = gui

	return frame, gui
end

local function getModelsInRect(minX, minY, maxX, maxY)
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return {} end

	local found = {}
	for _, child in placedFolder:GetChildren() do
		if child:IsA("Model") then
			local pivot = child:GetPivot()
			local screenPos, onScreen = camera:WorldToViewportPoint(pivot.Position)
			if onScreen then
				local sx, sy = screenPos.X, screenPos.Y
				if sx >= minX and sx <= maxX and sy >= minY and sy <= maxY then
					table.insert(found, child)
				end
			end
		end
	end
	return found
end


local function cleanupBoxDrag()
	isBoxDragging = false
	dragStart = nil
	if rectGui then rectGui:Destroy(); rectGui = nil end
	dragFrame = nil
end

local dragRayParams = RaycastParams.new()
dragRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function cleanupFreeDrag()
	isFreeDragging = false
	freeDragLastTargetGrid = nil
	freeDragInitialCFrames = {}
	freeDragBeforeGrids = {}
	freeDragFocusGridOffset = {}
	clickedSelectedModel = nil
end

local function getMouseSurfaceGrid(excludeModels: {Model}): Vector3?
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local excludeList = {}
	local char = player.Character
	if char then table.insert(excludeList, char) end
	for _, m in excludeModels do
		table.insert(excludeList, m)
	end
	dragRayParams.FilterDescendantsInstances = excludeList

	local result = workspace:Raycast(ray.Origin, ray.Direction * 200, dragRayParams)
	if not result then return nil end

	local placePos = result.Position + result.Normal * (CELL / 2)
	return Vector3.new(
		math.floor(placePos.X / CELL),
		math.floor(placePos.Y / CELL),
		math.floor(placePos.Z / CELL)
	)
end

local function buildIgnoreSet(): { [Model]: true }
	local set = {}
	for _, m in Selection.GetList() do set[m] = true end
	return set
end

local function showMoveHandles()
	if moveHandles then moveHandles:Destroy(); moveHandles = nil end
	if Selection.IsEmpty() then return end
	if not Selection.Focus or not Selection.Focus.Parent then return end

	local adornee = Selection.GetBoundingBoxAdornee() or Selection.Focus
	local blacklist = { adornee }
	for _, m in Selection.GetList() do table.insert(blacklist, m) end

	moveHandles = Handles.new({
		Adornee = adornee,
		Parent = playerGui,
		Color = Color3.fromRGB(255, 170, 0),
		ObstacleBlacklist = blacklist,

		OnDragStart = function()
			isHandleDragging = true
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
			isHandleDragging = false

			local moved = false
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
						moved = true
					end
				end
			end

			if moved then
				for _, model in savedModels do
					local newGrid = savedAfter[model]
					local oldGrid = savedBefore[model]
					if oldGrid and newGrid ~= oldGrid then
						moveRemote:FireServer(model, newGrid)
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
			task.defer(showMoveHandles)
		end,
	})
end

function SelectTool:Equip()
	showMoveHandles()
	disconnectChanged = Selection.OnChanged(showMoveHandles)
end

function SelectTool:Unequip()
	if hoverHighlight then hoverHighlight:Destroy(); hoverHighlight = nil end
	if moveHandles then moveHandles:Destroy(); moveHandles = nil end
	if disconnectChanged then disconnectChanged(); disconnectChanged = nil end
	cleanupBoxDrag()
	cleanupFreeDrag()
end

function SelectTool:Update()
	if hoverHighlight then hoverHighlight:Destroy(); hoverHighlight = nil end

	if isBoxDragging and dragFrame and dragStart then
		local mousePos = UserInputService:GetMouseLocation()
		local minX = math.min(dragStart.X, mousePos.X)
		local minY = math.min(dragStart.Y, mousePos.Y)
		local maxX = math.max(dragStart.X, mousePos.X)
		local maxY = math.max(dragStart.Y, mousePos.Y)

		dragFrame.Position = UDim2.fromOffset(minX, minY)
		dragFrame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
		return
	end

	if isHandleDragging or isFreeDragging then return end

	local model = Selection.GetHitModel()
	if model and not Selection.IsSelected(model) then
		local h = Instance.new("Highlight")
		h.Adornee = model
		h.FillColor = Selection.Color
		h.OutlineColor = Selection.Color
		h.FillTransparency = 0.75
		h.OutlineTransparency = 0.4
		h.Parent = playerGui
		hoverHighlight = h
	end
end

function SelectTool:OnClick()
	if isHandleDragging or isBoxDragging or isFreeDragging then return end

	local hitModel = Selection.GetHitModel()
	if hitModel then
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if not Selection.IsSelected(hitModel) then
			if shift or ctrl then
				Selection.Toggle(hitModel)
			else
				Selection.Replace(hitModel)
			end
			showMoveHandles()
		end

		clickedSelectedModel = hitModel
		dragStart = UserInputService:GetMouseLocation()

		freeDragInitialCFrames = {}
		freeDragBeforeGrids = {}
		freeDragFocusGridOffset = {}
		local focusGrid = Selection.Focus:GetAttribute("GridCoord")
		for _, model in Selection.GetList() do
			freeDragInitialCFrames[model] = model:GetPivot()
			local gc = model:GetAttribute("GridCoord")
			freeDragBeforeGrids[model] = gc
			freeDragFocusGridOffset[model] = gc and focusGrid and (gc - focusGrid) or Vector3.zero
		end

		freeDragLastTargetGrid = nil
		return
	end

	dragStart = UserInputService:GetMouseLocation()
end

function SelectTool:OnMouseMove()
	if isHandleDragging then return end
	if not dragStart then return end

	if isFreeDragging then
		local models = Selection.GetList()
		local targetGrid = getMouseSurfaceGrid(models)
		if not targetGrid then return end
		if freeDragLastTargetGrid and targetGrid == freeDragLastTargetGrid then return end

		local ignoreSet = buildIgnoreSet()
		local canMove = true
		for model in freeDragInitialCFrames do
			local offset = freeDragFocusGridOffset[model] or Vector3.zero
			local newGC = targetGrid + offset
			if GridUtil.IsOccupied(newGC, ignoreSet) then
				canMove = false
				break
			end
		end

		if canMove then
			freeDragLastTargetGrid = targetGrid
			for model in freeDragInitialCFrames do
				if model.Parent then
					local offset = freeDragFocusGridOffset[model] or Vector3.zero
					local newGC = targetGrid + offset
					local worldPos = GridUtil.GridToWorld(newGC)
					local initCF = freeDragInitialCFrames[model]
					model:PivotTo(CFrame.new(worldPos) * initCF.Rotation)
				end
			end
		end
		return
	end

	if isBoxDragging then return end

	local mousePos = UserInputService:GetMouseLocation()
	local dist = (mousePos - dragStart).Magnitude
	if dist >= DRAG_THRESHOLD then
		if clickedSelectedModel then
			isFreeDragging = true
		else
			isBoxDragging = true
			dragFrame, rectGui = createDragFrame()
		end
	end
end

function SelectTool:OnMouseUp()
	if isHandleDragging then return end

	if isFreeDragging then
		local moved = false
		local savedBefore = {}
		local savedAfter = {}
		local savedModels = {}

		for model in freeDragInitialCFrames do
			if model.Parent then
				local newGrid = GridUtil.WorldToGrid(model:GetPivot().Position)
				local oldGrid = freeDragBeforeGrids[model]
				savedBefore[model] = oldGrid
				savedAfter[model] = newGrid
				table.insert(savedModels, model)

				if oldGrid and newGrid ~= oldGrid then
					moved = true
					moveRemote:FireServer(model, newGrid)
				end
			end
		end

		if moved then
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
			for model, startCF in freeDragInitialCFrames do
				if model.Parent then
					model:PivotTo(startCF)
				end
			end
		end

		cleanupFreeDrag()
		cleanupBoxDrag()
		showMoveHandles()
		return
	end

	if clickedSelectedModel and not isBoxDragging and not isFreeDragging then
		cleanupFreeDrag()
		cleanupBoxDrag()
		return
	end

	if isBoxDragging and dragStart then
		local mousePos = UserInputService:GetMouseLocation()
		local minX = math.min(dragStart.X, mousePos.X)
		local minY = math.min(dragStart.Y, mousePos.Y)
		local maxX = math.max(dragStart.X, mousePos.X)
		local maxY = math.max(dragStart.Y, mousePos.Y)

		local models = getModelsInRect(minX, minY, maxX, maxY)

		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if not shift and not ctrl then
			Selection.Clear()
		end

		for _, model in models do
			if ctrl then
				Selection.Toggle(model)
			else
				Selection.Add(model)
			end
		end

		cleanupBoxDrag()
		showMoveHandles()
		return
	end

	if dragStart and not isBoxDragging then
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if not shift and not ctrl then
			Selection.Clear()
			showMoveHandles()
		end
	end

	cleanupBoxDrag()
end

function SelectTool:OnRightClick()
	local model = Selection.GetHitModel()
	if model then
		Selection.Remove(model)
		showMoveHandles()
	end
end

function SelectTool:OnRotate(axis: string)
	local rotateRemote = remotes:FindFirstChild("RotateBlock")
	if not rotateRemote then return end
	for _, model in Selection.GetList() do
		rotateRemote:FireServer(model, axis)
	end
	task.defer(showMoveHandles)
end

function SelectTool:OnKeyDown(keyCode)
	if keyCode == Enum.KeyCode.Q then
		local dirRemote = remotes:FindFirstChild("SetDirection")
		for _, model in Selection.GetList() do
			local current = model:GetAttribute("MotorDirection") or 1
			local newDir = -current
			if dirRemote then
				dirRemote:FireServer(model, newDir)
			end
			print("[SelectTool] Motor direction:", model.Name, "->", newDir == 1 and "FORWARD" or "REVERSE")
		end
	end
end

return SelectTool
