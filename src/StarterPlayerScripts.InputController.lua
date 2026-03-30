--[[
	InputController — Centralized keyboard/mouse input handling.
	Place in: StarterPlayerScripts > InputController (ModuleScript)
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Selection = require(Modules:WaitForChild("Selection"))
local History = require(Modules:WaitForChild("History"))
local InventoryUI = require(Modules:WaitForChild("InventoryUI"))

local InputController = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local placeRemote = remotes:WaitForChild("PlaceBlock")
local removeRemote = remotes:WaitForChild("RemoveBlock")

-- Set by PlacementClient
local getCurrentTool = nil      -- () -> tool
local setToolMode = nil         -- (mode) -> ()
local selectHotbarItem = nil    -- (slot) -> ()

------------------------------------------------------------
-- Clipboard
------------------------------------------------------------

local clipboard = {}

local function copySelection()
	local list = Selection.GetList()
	if #list == 0 then return end

	clipboard = {}
	local firstCoord = list[1]:GetAttribute("GridCoord")
	if not firstCoord then return end

	for _, model in list do
		local gc = model:GetAttribute("GridCoord")
		if gc then
			table.insert(clipboard, {
				item = model.Name,
				ox = gc.X - firstCoord.X,
				oy = gc.Y - firstCoord.Y,
				oz = gc.Z - firstCoord.Z,
			})
		end
	end
	print("[Input] copied", #clipboard, "blocks")
end

local function pasteClipboard(baseCoord: Vector3?)
	if #clipboard == 0 or not baseCoord then return end
	for _, entry in clipboard do
		local coord = Vector3.new(baseCoord.X + entry.ox, baseCoord.Y + entry.oy, baseCoord.Z + entry.oz)
		placeRemote:FireServer(entry.item, coord, 0, 0)
	end
	print("[Input] pasted", #clipboard, "blocks")
end

local function cutSelection()
	copySelection()
	local list = Selection.GetList()
	for _, model in list do
		local gc = model:GetAttribute("GridCoord")
		if gc then removeRemote:FireServer(gc) end
	end
	Selection.Clear()
	print("[Input] cut", #clipboard, "blocks")
end

local function duplicateSelection()
	copySelection()
	if #clipboard == 0 then return end

	-- Offset by 1 cell on X
	local first = nil
	for _, model in Selection.GetList() do
		first = model:GetAttribute("GridCoord")
		break
	end
	if first then
		pasteClipboard(first + Vector3.new(1, 0, 0))
	end
end

local function deleteSelected()
	local list = Selection.GetList()
	for _, model in list do
		local isSubGrid = model:GetAttribute("SubGrid")
		if isSubGrid then
			local wp = model:GetAttribute("WorldPos")
			if wp then removeRemote:FireServer(wp, true) end
		else
			local gc = model:GetAttribute("GridCoord")
			if gc then removeRemote:FireServer(gc) end
		end
	end
	Selection.Clear()
end

------------------------------------------------------------
-- Key maps
------------------------------------------------------------

local HOTBAR_MAP = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

------------------------------------------------------------
-- Init: connect to UserInputService
------------------------------------------------------------

function InputController.Init(getToolFn, setModeFn, selectItemFn)
	getCurrentTool = getToolFn
	setToolMode = setModeFn
	selectHotbarItem = selectItemFn

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		local tool = getCurrentTool()

		-- Mouse clicks: delegate to current tool
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if tool and tool.OnClick then
				tool:OnClick()
			end
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if tool and tool.OnRightClick then
				tool:OnRightClick()
			end
			return
		end

		-- Keyboard
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		-- Ctrl shortcuts
		if ctrl then
			if input.KeyCode == Enum.KeyCode.C then copySelection(); return end
			if input.KeyCode == Enum.KeyCode.X then cutSelection(); return end
			if input.KeyCode == Enum.KeyCode.D then duplicateSelection(); return end
			if input.KeyCode == Enum.KeyCode.Z then History.Undo(); return end
			if input.KeyCode == Enum.KeyCode.Y then History.Redo(); return end
			if input.KeyCode == Enum.KeyCode.V then
				-- Paste at cursor (tool provides grid coord)
				if tool and tool.GetGridCoord then
					pasteClipboard(tool:GetGridCoord())
				end
				return
			end
		end

		-- Delete/Backspace
		if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
			if not Selection.IsEmpty() then
				deleteSelected()
			end
			return
		end

		-- Inventory toggle
		if input.KeyCode == Enum.KeyCode.E then
			InventoryUI.Toggle()
			return
		end

		-- Tool shortcuts
		if input.KeyCode == Enum.KeyCode.G then setToolMode("glue"); return end
		if input.KeyCode == Enum.KeyCode.H then setToolMode("unglue"); return end
		if input.KeyCode == Enum.KeyCode.F then setToolMode("activate"); return end

		-- R/T rotation: delegate to tool
		if input.KeyCode == Enum.KeyCode.R then
			if tool and tool.OnRotate then tool:OnRotate("Y") end
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			if tool and tool.OnRotate then tool:OnRotate("X") end
			return
		end
		if input.KeyCode == Enum.KeyCode.Y then
			if tool and tool.OnRotate then tool:OnRotate("Z") end
			return
		end

		-- Hotbar
		local slot = HOTBAR_MAP[input.KeyCode]
		if slot then selectHotbarItem(slot); return end

		-- Pass to tool
		if tool and tool.OnKeyDown then
			tool:OnKeyDown(input.KeyCode)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local tool = getCurrentTool()
			if tool and tool.OnMouseMove then
				tool:OnMouseMove()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		local tool = getCurrentTool()
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if tool and tool.OnMouseUp then
				tool:OnMouseUp()
			elseif tool and tool.OnRelease then
				tool:OnRelease()
			end
		end
	end)
end

return InputController
