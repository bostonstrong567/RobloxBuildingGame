local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Selection = require(Modules:WaitForChild("Selection"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local glueRemote = remotes:WaitForChild("GlueBlocks")
local unglueRemote = remotes:WaitForChild("UnglueBlocks")

local MAX_REACH = 100
local GLUE_TAG = "GlueWeld"
local DRAG_THRESHOLD = 5

local GlueTool = {}
GlueTool.Name = "glue"

local isUnglueMode = false
local firstPart: BasePart? = nil
local highlights: { [BasePart]: Highlight } = {}
local hoverHighlight: Highlight? = nil

local dragStart: Vector2? = nil
local isBoxDragging = false
local dragFrame: Frame? = nil
local rectGui = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateFilter()
	local list = {}
	if player.Character then table.insert(list, player.Character) end
	rayParams.FilterDescendantsInstances = list
end

local function getHitPart(): BasePart?
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	updateFilter()
	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_REACH, rayParams)
	if not result or not result.Instance:IsA("BasePart") then return nil end

	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder or not result.Instance:IsDescendantOf(placedFolder) then return nil end

	return result.Instance
end

local function addHighlight(part: BasePart, color: Color3, alpha: number?)
	if highlights[part] then return end
	local model = part:FindFirstAncestorWhichIsA("Model")
	local h = Instance.new("Highlight")
	h.Adornee = model or part
	h.FillColor = color
	h.FillTransparency = alpha or 0.5
	h.OutlineColor = color
	h.OutlineTransparency = 0.3
	h.Parent = model or part
	highlights[part] = h
end

local function clearHighlights()
	for _, h in highlights do h:Destroy() end
	highlights = {}
	if hoverHighlight then hoverHighlight:Destroy(); hoverHighlight = nil end
	firstPart = nil
end

local function showExistingGlue()
	clearHighlights()
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return end

	for _, desc in placedFolder:GetDescendants() do
		if desc:IsA("WeldConstraint") and desc.Name == GLUE_TAG then
			if desc.Part0 and desc.Part0.Parent then
				addHighlight(desc.Part0, Color3.fromRGB(0, 255, 100), 0.7)
			end
			if desc.Part1 and desc.Part1.Parent then
				addHighlight(desc.Part1, Color3.fromRGB(0, 255, 100), 0.7)
			end
		end
	end
end

local function createDragFrame()
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = isUnglueMode and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 100)
	frame.BackgroundTransparency = 0.7
	frame.BorderSizePixel = 0
	frame.ZIndex = 10

	local stroke = Instance.new("UIStroke")
	stroke.Color = frame.BackgroundColor3
	stroke.Thickness = 1
	stroke.Parent = frame

	local gui = Instance.new("ScreenGui")
	gui.Name = "GlueSelectRect"
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

local function glueAllSelected()
	local models = Selection.GetList()
	if #models < 2 then return end

	local parts = {}
	for _, model in models do
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
	end

	for i = 1, #parts - 1 do
		for j = i + 1, #parts do
			local a, b = parts[i], parts[j]
			if a:FindFirstAncestorWhichIsA("Model") ~= b:FindFirstAncestorWhichIsA("Model") then
				local dist = (a.Position - b.Position).Magnitude
				if dist <= a.Size.Magnitude / 2 + b.Size.Magnitude / 2 + 0.5 then
					glueRemote:FireServer(a, b)
				end
			end
		end
	end

	task.wait(0.1)
	showExistingGlue()
end

local function unglueAllSelected()
	local models = Selection.GetList()
	if #models < 1 then return end

	local parts = {}
	for _, model in models do
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
	end

	for _, part in parts do
		for _, child in part:GetChildren() do
			if child:IsA("WeldConstraint") and child.Name == GLUE_TAG then
				if child.Part0 and child.Part1 then
					unglueRemote:FireServer(child.Part0, child.Part1)
				end
			end
		end
	end

	task.wait(0.1)
	Selection.Clear()
	showExistingGlue()
end

function GlueTool.SetUnglueMode(unglue: boolean)
	isUnglueMode = unglue
end

function GlueTool:Equip()
	showExistingGlue()
end

function GlueTool:Unequip()
	clearHighlights()
	cleanupBoxDrag()
	Selection.Clear()
end

function GlueTool:Update()
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

	local hitPart = getHitPart()
	if hitPart then
		local model = hitPart:FindFirstAncestorWhichIsA("Model")
		local h = Instance.new("Highlight")
		h.Adornee = model or hitPart
		h.FillColor = isUnglueMode and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 255, 100)
		h.OutlineColor = h.FillColor
		h.FillTransparency = 0.6
		h.OutlineTransparency = 0.2
		h.Parent = playerGui
		hoverHighlight = h
	end
end

function GlueTool:OnClick()
	if isBoxDragging then return end

	local hitPart = getHitPart()
	if not hitPart then
		dragStart = UserInputService:GetMouseLocation()
		return
	end

	local hitModel = hitPart:FindFirstAncestorWhichIsA("Model")
	if not hitModel then return end

	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if shift or ctrl then
		Selection.Toggle(hitModel)
	else
		if not firstPart then
			firstPart = hitPart
			Selection.Add(hitModel)
			local color = isUnglueMode and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(100, 255, 255)
			addHighlight(hitPart, color, 0.4)
		else
			if isUnglueMode then
				unglueRemote:FireServer(firstPart, hitPart)
			else
				glueRemote:FireServer(firstPart, hitPart)
			end
			firstPart = nil
			Selection.Clear()
			task.wait(0.1)
			showExistingGlue()
		end
	end
end

function GlueTool:OnMouseMove()
	if not dragStart or isBoxDragging then return end

	local mousePos = UserInputService:GetMouseLocation()
	local dist = (mousePos - dragStart).Magnitude
	if dist >= DRAG_THRESHOLD then
		isBoxDragging = true
		dragFrame, rectGui = createDragFrame()
	end
end

function GlueTool:OnMouseUp()
	if isBoxDragging and dragStart then
		local mousePos = UserInputService:GetMouseLocation()
		local minX = math.min(dragStart.X, mousePos.X)
		local minY = math.min(dragStart.Y, mousePos.Y)
		local maxX = math.max(dragStart.X, mousePos.X)
		local maxY = math.max(dragStart.Y, mousePos.Y)

		local models = getModelsInRect(minX, minY, maxX, maxY)

		Selection.Clear()
		for _, model in models do
			Selection.Add(model)
		end

		if isUnglueMode then
			unglueAllSelected()
		else
			glueAllSelected()
		end

		cleanupBoxDrag()
		return
	end

	if dragStart and not isBoxDragging then
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if not shift and not ctrl and not firstPart then
			Selection.Clear()
		end
	end

	cleanupBoxDrag()
end

function GlueTool:OnRightClick()
	firstPart = nil
	Selection.Clear()
	showExistingGlue()
end

return GlueTool
