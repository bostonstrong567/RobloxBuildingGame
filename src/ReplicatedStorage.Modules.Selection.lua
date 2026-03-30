--[[
	Selection — Manages selected models with highlights.
	Place in: ReplicatedStorage > Modules > Selection (ModuleScript)
	Adapted from Fork3X Core/Selection.lua — simplified for grid building.
]]

local Selection = {}

Selection.Items = {}        -- { [Model]: true } hash for O(1) lookup
Selection.List = {}         -- { Model } array for iteration
Selection.Focus = nil       -- last selected model (handles attach here)
Selection.Highlights = {}   -- { [Model]: Highlight }

Selection.Color = Color3.fromRGB(100, 170, 255)
Selection.BoundingBox = nil

local changedCallbacks = {}
local focusChangedCallbacks = {}

-- Returns a disconnect function
function Selection.OnChanged(fn)
	table.insert(changedCallbacks, fn)
	return function()
		for i, cb in changedCallbacks do
			if cb == fn then table.remove(changedCallbacks, i); break end
		end
	end
end

-- Returns a disconnect function
function Selection.OnFocusChanged(fn)
	table.insert(focusChangedCallbacks, fn)
	return function()
		for i, cb in focusChangedCallbacks do
			if cb == fn then table.remove(focusChangedCallbacks, i); break end
		end
	end
end

local function fireChanged()
	for _, fn in changedCallbacks do fn() end
end

local function fireFocusChanged()
	for _, fn in focusChangedCallbacks do fn() end
end

------------------------------------------------------------
-- Highlight management
------------------------------------------------------------

local function addHighlight(model: Model)
	if Selection.Highlights[model] then return end

	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillColor = Selection.Color
	h.OutlineColor = Selection.Color
	h.FillTransparency = 0.6
	h.OutlineTransparency = 0.2
	h.Parent = model
	Selection.Highlights[model] = h
end

local function removeHighlight(model: Model)
	local h = Selection.Highlights[model]
	if h then
		h:Destroy()
		Selection.Highlights[model] = nil
	end
end

------------------------------------------------------------
-- Core operations
------------------------------------------------------------

function Selection.Add(model: Model)
	if not model or Selection.Items[model] then return end

	Selection.Items[model] = true
	table.insert(Selection.List, model)
	addHighlight(model)

	Selection.Focus = model
	fireFocusChanged()
	fireChanged()
end

function Selection.Remove(model: Model)
	if not Selection.Items[model] then return end

	Selection.Items[model] = nil
	removeHighlight(model)

	-- Remove from list
	for i, m in Selection.List do
		if m == model then
			table.remove(Selection.List, i)
			break
		end
	end

	-- Update focus
	if Selection.Focus == model then
		Selection.Focus = Selection.List[#Selection.List]
		fireFocusChanged()
	end

	fireChanged()
end

function Selection.Toggle(model: Model)
	if Selection.Items[model] then
		Selection.Remove(model)
	else
		Selection.Add(model)
	end
end

function Selection.Clear()
	for model in Selection.Items do
		removeHighlight(model)
	end
	Selection.Items = {}
	Selection.List = {}

	if Selection.Focus then
		Selection.Focus = nil
		fireFocusChanged()
	end

	fireChanged()
end

function Selection.Replace(model: Model)
	Selection.Clear()
	Selection.Add(model)
end

function Selection.IsSelected(model: Model): boolean
	return Selection.Items[model] == true
end

function Selection.GetList(): { Model }
	-- Return only models that still exist
	local valid = {}
	for _, model in Selection.List do
		if model.Parent then
			table.insert(valid, model)
		end
	end
	return valid
end

function Selection.Count(): number
	local n = 0
	for _ in Selection.Items do n += 1 end
	return n
end

function Selection.IsEmpty(): boolean
	return next(Selection.Items) == nil
end

------------------------------------------------------------
-- Shared raycast: get placed model under cursor
------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local MAX_REACH = 100

function Selection.GetHitModel(): Model?
	local camera = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	if char then table.insert(list, char) end
	params.FilterDescendantsInstances = list

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_REACH, params)
	if not result or not result.Instance:IsA("BasePart") then return nil end

	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder or not result.Instance:IsDescendantOf(placedFolder) then return nil end

	return result.Instance:FindFirstAncestorWhichIsA("Model")
end

------------------------------------------------------------
-- Shared click handler: select/multi-select/deselect
------------------------------------------------------------

function Selection.HandleClick()
	local model = Selection.GetHitModel()

	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if model then
		if shift or ctrl then
			Selection.Toggle(model)
		else
			Selection.Replace(model)
		end
	else
		if not shift and not ctrl then
			Selection.Clear()
		end
	end
end

------------------------------------------------------------
-- Bounding box: visible outline + invisible Part for handles
------------------------------------------------------------

local RunService = game:GetService("RunService")

local bbPart = nil
local bbHighlight = nil

local function computeBounds(list)
	local minV = Vector3.new(math.huge, math.huge, math.huge)
	local maxV = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, model in list do
		local cf, size = model:GetBoundingBox()
		local half = size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = (cf * CFrame.new(sx * half.X, sy * half.Y, sz * half.Z)).Position
					minV = minV:Min(p)
					maxV = maxV:Max(p)
				end
			end
		end
	end

	return (minV + maxV) / 2, maxV - minV
end

local function ensureBBPart()
	if bbPart then return end

	bbPart = Instance.new("Part")
	bbPart.Name = "SelectionBoundingBox"
	bbPart.Anchored = true
	bbPart.CanCollide = false
	bbPart.CanQuery = false
	bbPart.CanTouch = false
	bbPart.Transparency = 1
	bbPart.Parent = workspace.CurrentCamera

	bbHighlight = Instance.new("SelectionBox")
	bbHighlight.Color3 = Selection.Color
	bbHighlight.LineThickness = 0.02
	bbHighlight.Transparency = 0.5
	bbHighlight.SurfaceTransparency = 0.95
	bbHighlight.SurfaceColor3 = Selection.Color
	bbHighlight.Adornee = bbPart
	bbHighlight.Parent = bbPart
end

local function destroyBBPart()
	if bbPart then
		bbPart:Destroy()
		bbPart = nil
		bbHighlight = nil
	end
end

local function updateBoundingBox()
	local list = Selection.GetList()
	if #list == 0 then
		destroyBBPart()
		return
	end

	ensureBBPart()
	local center, size = computeBounds(list)
	bbPart.Size = size + Vector3.new(0.1, 0.1, 0.1)
	bbPart.CFrame = CFrame.new(center)
end

function Selection.GetBoundingBoxAdornee(): BasePart?
	local list = Selection.GetList()
	if #list == 0 then return nil end
	ensureBBPart()
	updateBoundingBox()
	return bbPart
end

function Selection.UpdateBoundingBox()
	updateBoundingBox()
end

Selection.OnChanged(updateBoundingBox)
Selection.OnFocusChanged(updateBoundingBox)

RunService.PreRender:Connect(function()
	if not Selection.IsEmpty() then
		updateBoundingBox()
	end
end)

return Selection
