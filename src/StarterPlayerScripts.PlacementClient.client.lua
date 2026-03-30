--[[
	PlacementClient — Slim orchestrator. Wires sidebar buttons to tool modules.
	Place in: StarterPlayerScripts > PlacementClient (LocalScript)

	All logic lives in tool modules and shared modules.
	This script only handles: tool switching, sidebar wiring, hotbar, PreRender loop.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local HotbarUI = require(Modules:WaitForChild("HotbarUI"))
local SaveLoadUI = require(Modules:WaitForChild("SaveLoadUI"))
local Selection = require(Modules:WaitForChild("Selection"))
local GridUtil = require(Modules:WaitForChild("GridUtil"))
local InventoryUI = require(Modules:WaitForChild("InventoryUI"))

-- Tools (in StarterPlayerScripts > Tools folder)
local toolsFolder = script:WaitForChild("Tools")
local PlaceTool = require(toolsFolder:WaitForChild("PlaceTool"))
local SelectTool = require(toolsFolder:WaitForChild("SelectTool"))
local MoveTool = require(toolsFolder:WaitForChild("MoveTool"))
local RotateTool = require(toolsFolder:WaitForChild("RotateTool"))
local ResizeTool = require(toolsFolder:WaitForChild("ResizeTool"))
local GlueTool = require(toolsFolder:WaitForChild("GlueTool"))
local ActivateTool = require(toolsFolder:WaitForChild("ActivateTool"))
local InputController = require(script:WaitForChild("InputController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local COLOR_OFF = Color3.fromRGB(255, 53, 56)
local COLOR_ON = Color3.fromRGB(97, 255, 89)

------------------------------------------------------------
-- Tool registry
------------------------------------------------------------

local TOOLS = {
	place = PlaceTool,
	select = SelectTool,
	move = MoveTool,
	rotate = RotateTool,
	rescale = ResizeTool,
	glue = GlueTool,
	unglue = GlueTool, -- same module, different internal mode
	activate = ActivateTool,
}

local currentTool = nil
local currentMode = "place"

------------------------------------------------------------
-- Sidebar stroke refs
------------------------------------------------------------

local strokeRefs: { [string]: UIStroke } = {}
local releaseButton: TextButton? = nil

local function updateStrokeColors()
	for mode, stroke in strokeRefs do
		if mode == "activate" then
			stroke.Color = (currentMode == "activate") and COLOR_ON or COLOR_OFF
		elseif mode == "glue" or mode == "unglue" then
			stroke.Color = (currentMode == "glue" or currentMode == "unglue") and COLOR_ON or COLOR_OFF
		else
			stroke.Color = (currentMode == mode) and COLOR_ON or COLOR_OFF
		end
	end
end

------------------------------------------------------------
-- Tool switching (Fork3X Equip/Unequip pattern)
------------------------------------------------------------

local isPlayMode = false

local function setToolMode(mode: string)
	-- During Play Mode, only allow activate (to exit) and place (forced by exit)
	if isPlayMode and mode ~= "activate" and mode ~= "place" then
		return
	end

	-- Toggle off: same mode returns to place
	if currentMode == mode and mode ~= "place" then
		mode = "place"
	end

	-- Unequip current
	if currentTool and currentTool.Unequip then
		currentTool:Unequip()
	end

	-- Handle unglue as glue tool with flag
	if mode == "unglue" then
		GlueTool.SetUnglueMode(true)
	elseif mode == "glue" then
		GlueTool.SetUnglueMode(false)
	end

	-- Update button text and play mode state
	if mode == "activate" then
		isPlayMode = true
		if releaseButton then releaseButton.Text = "Stop" end
	elseif currentMode == "activate" and mode ~= "activate" then
		isPlayMode = false
		if releaseButton then releaseButton.Text = "Play" end
	end

	currentMode = mode
	currentTool = TOOLS[mode]

	-- Clear selection when switching to non-selection tools
	if mode == "place" or mode == "glue" or mode == "unglue" or mode == "activate" then
		Selection.Clear()
	end

	-- Equip new
	if currentTool and currentTool.Equip then
		currentTool:Equip()
	end

	-- Deselect hotbar in non-place modes
	if mode ~= "place" then
		HotbarUI.SetSelected(nil)
		PlaceTool.SetItem(nil)
	end

	updateStrokeColors()
	print("[PlacementClient] mode:", mode)
end

------------------------------------------------------------
-- Hotbar item selection
------------------------------------------------------------

local items: { string } = {}
local allPlaceables = GridUtil.GetAllPlaceables()
for _, entry in allPlaceables do
	table.insert(items, entry.name)
end

local function selectHotbarItem(slot: number?)
	-- Can't select items in activate mode
	if currentMode == "activate" then return end

	-- Switch to place mode if not already
	if currentMode ~= "place" then
		setToolMode("place")
	end

	HotbarUI.SetSelected(nil)

	if slot and slot <= #items then
		local name = items[slot]
		if PlaceTool.GetItem() == name then
			-- Toggle off
			PlaceTool.SetItem(nil)
			return
		end
		PlaceTool.SetItem(name)
		HotbarUI.SetSelected(slot)
	else
		PlaceTool.SetItem(nil)
	end
end

------------------------------------------------------------
-- Sidebar button wiring
------------------------------------------------------------

local function wireToolButton(toolHolder, frameName: string, buttonName: string, mode: string)
	local frame = toolHolder:FindFirstChild(frameName)
	if not frame then return end

	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		strokeRefs[mode] = stroke
	end

	local btn = frame:FindFirstChild(buttonName)
	if btn then
		btn.MouseButton1Click:Connect(function()
			setToolMode(mode)
		end)
	end
end

local function connectSidebar()
	local mainGui = playerGui:FindFirstChild("Main")
	if not mainGui then return end
	local sideBar = mainGui:FindFirstChild("SideBar")
	if not sideBar then return end

	local toolHolder = sideBar:FindFirstChild("ToolHolder")
	if toolHolder then
		wireToolButton(toolHolder, "ActivateFrame", "Activate", "activate")
		wireToolButton(toolHolder, "SelectAndMoveFrame", "SelectAndMove", "select")
		wireToolButton(toolHolder, "MoveFrame", "Move", "move")
		wireToolButton(toolHolder, "RotateFrame", "Rotate", "rotate")
		wireToolButton(toolHolder, "RescaleFrame", "Rescale", "rescale")
		wireToolButton(toolHolder, "GlueFrame", "Glue", "glue")
		wireToolButton(toolHolder, "ScraperFrame", "Scraper", "unglue")
	end

	local tool2Holder = sideBar:FindFirstChild("Tool2Holder")
	if tool2Holder then
		local holder = tool2Holder:FindFirstChild("UnAnchorButtonHolder")
		if holder then
			local btn = holder:FindFirstChild("UnAnchorButton")
			if btn and btn:IsA("TextButton") then
				releaseButton = btn
				btn.Text = "Play"
				btn.MouseButton1Click:Connect(function()
					setToolMode("activate")
				end)
			end
		end
	end

	updateStrokeColors()
end

------------------------------------------------------------
-- PreRender: delegate to current tool
------------------------------------------------------------

RunService.PreRender:Connect(function(dt)
	if currentTool and currentTool.Update then
		currentTool:Update(dt)
	end
end)

------------------------------------------------------------
-- Init
------------------------------------------------------------

local mainGui = playerGui:FindFirstChild("Main")
if mainGui then
	mainGui.Enabled = true
end

HotbarUI.Init(playerGui)
HotbarUI.ConnectClicks(function(s) selectHotbarItem(s) end)

for i, name in items do
	local t = GridUtil.FindPlaceable(name)
	if t then HotbarUI.PopulateSlot(i, t) end
end

connectSidebar()
SaveLoadUI.Init(playerGui)

InventoryUI.Init(playerGui, function(itemName)
	if currentMode ~= "place" then
		setToolMode("place")
	end
	PlaceTool.SetItem(itemName)
	HotbarUI.SetSelected(nil)
end)

-- Init input controller
InputController.Init(
	function() return currentTool end,
	setToolMode,
	selectHotbarItem
)

-- Build client occupancy map and keep it updated
GridUtil.RebuildOccupancy()
local placedFolder = workspace:FindFirstChild("PlacedBlocks")
if placedFolder then
	placedFolder.ChildAdded:Connect(function()
		task.defer(GridUtil.RebuildOccupancy)
	end)
	placedFolder.ChildRemoved:Connect(function()
		task.defer(GridUtil.RebuildOccupancy)
	end)
end

-- Start in place mode
setToolMode("place")

print("[PlacementClient] ready")
