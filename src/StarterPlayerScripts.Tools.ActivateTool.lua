local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MechanicsConfig = require(Modules:WaitForChild("MechanicsConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local activateRemote = remotes:WaitForChild("ActivateToggle")

local MAX_REACH = 100

local BEHAVIOR_COLORS = {
	remove = Color3.fromRGB(255, 80, 80),
	toggle = Color3.fromRGB(255, 200, 50),
}

local ActivateTool = {}
ActivateTool.Name = "activate"
ActivateTool.IsPlaying = false

local hoverHighlight: Highlight? = nil

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

local function getModelBehavior(model: Model): string?
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and MechanicsConfig[desc.Name] then
			local cfg = MechanicsConfig[desc.Name]
			if cfg.activatable then
				return cfg.behavior or "toggle"
			end
		end
	end
	return nil
end

function ActivateTool:Equip()
	local result = activateRemote:InvokeServer("play")
	if result then
		ActivateTool.IsPlaying = true
	end
end

function ActivateTool:Unequip()
	if hoverHighlight then hoverHighlight:Destroy(); hoverHighlight = nil end

	if ActivateTool.IsPlaying then
		activateRemote:InvokeServer("build")
		ActivateTool.IsPlaying = false
	end
end

function ActivateTool:Update()
	if hoverHighlight then hoverHighlight:Destroy(); hoverHighlight = nil end
	if not ActivateTool.IsPlaying then return end

	local hitPart = getHitPart()
	if not hitPart then return end

	local model = hitPart:FindFirstAncestorWhichIsA("Model")
	if not model then return end

	local behavior = getModelBehavior(model)
	if not behavior then return end

	local color = BEHAVIOR_COLORS[behavior] or Color3.fromRGB(255, 200, 50)

	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.4
	h.OutlineTransparency = 0.2
	h.Parent = playerGui
	hoverHighlight = h
end

function ActivateTool:OnClick()
	if not ActivateTool.IsPlaying then return end

	local hitPart = getHitPart()
	if not hitPart then return end

	local model = hitPart:FindFirstAncestorWhichIsA("Model")
	if not model then return end

	local behavior = getModelBehavior(model)
	if behavior then
		activateRemote:InvokeServer(hitPart)
	end
end

return ActivateTool
