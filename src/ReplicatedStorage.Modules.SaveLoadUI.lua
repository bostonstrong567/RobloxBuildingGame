--[[
	SaveLoadUI — Wires up the SaveManager/SaveSlot GUI for save/load.
	Place in: ReplicatedStorage > Modules > SaveLoadUI (ModuleScript)

	GUI paths (already created in Studio):
	  Main > GameState > ButtonHolder > SaveHolder > Save
	  Main > GameState > ButtonHolder > LoadHolder > Load
	  Main > GameState > ToggleVisability > ToggleSaveLoad
	  Main > SaveManager > NewSaveButton > TextButton
	  Main > SaveManager > Lister > SaveLoadTemplet (template, Visible=false)
	  Main > SaveSlot > SaveTextBoxHolder > SaveTextBox
	  Main > SaveSlot > SaveButtonHolder > Save
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SaveLoadUI = {}

local remotesFolder
local getSavesRemote
local saveBuildRemote
local loadBuildRemote

local mainGui
local gameState
local saveManager
local saveSlot
local lister
local template
local toggleBtn
local saveTextBox

local currentSlotId = nil -- nil = new slot

local function log(...)
	print("[SaveLoadUI]", ...)
end

------------------------------------------------------------
-- Slot list management
------------------------------------------------------------

local function clearSlotList()
	for _, child in lister:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "SaveLoadTemplet" then
			child:Destroy()
		end
	end
end

local function refreshSlotList()
	clearSlotList()

	local ok, saves = pcall(function()
		return getSavesRemote:InvokeServer()
	end)

	if not ok or not saves then
		log("failed to get saves:", saves)
		return
	end

	for _, save in saves do
		local slot = template:Clone()
		slot.Name = "Slot_" .. save.id
		slot.Visible = true

		local nameLabel = slot:FindFirstChild("SaveNameText")
		if nameLabel then
			nameLabel.Text = save.name
		end

		local saveLoad = slot:FindFirstChild("SaveLoad")
		if saveLoad then
			-- Save to slot button
			local saveHolder = saveLoad:FindFirstChild("SaveTextButtonHolder")
			if saveHolder then
				local btn = saveHolder:FindFirstChild("SaveTextButton")
				if btn then
					btn.MouseButton1Click:Connect(function()
						local result = saveBuildRemote:InvokeServer(save.id, save.name)
						if result then
							log("saved to slot", save.id)
						end
					end)
				end
			end

			-- Load from slot button
			local loadHolder = saveLoad:FindFirstChild("LoadButtonHolder")
			if loadHolder then
				local btn = loadHolder:FindFirstChild("LoadButton")
				if btn then
					btn.MouseButton1Click:Connect(function()
						local result = loadBuildRemote:InvokeServer(save.id)
						if result then
							log("loaded from slot", save.id)
							saveManager.Visible = false
							toggleBtn.Text = "Open"
						end
					end)
				end
			end
		end

		slot.Parent = lister
	end

	log("refreshed slot list:", #saves, "slots")
end

------------------------------------------------------------
-- Init
------------------------------------------------------------

function SaveLoadUI.Init(playerGui)
	mainGui = playerGui:WaitForChild("Main")

	remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	getSavesRemote = remotesFolder:WaitForChild("GetSaves")
	saveBuildRemote = remotesFolder:WaitForChild("SaveBuild")
	loadBuildRemote = remotesFolder:WaitForChild("LoadBuild")

	-- GUI references
	gameState = mainGui:WaitForChild("GameState")
	saveManager = mainGui:WaitForChild("SaveManager")
	saveSlot = mainGui:WaitForChild("SaveSlot")
	lister = saveManager:WaitForChild("Lister")
	template = lister:WaitForChild("SaveLoadTemplet")

	local saveTextBoxHolder = saveSlot:WaitForChild("SaveTextBoxHolder")
	saveTextBox = saveTextBoxHolder:WaitForChild("SaveTextBox")

	-- ToggleSaveLoad button: toggles SaveManager panel
	local toggleFrame = gameState:WaitForChild("ToggleVisability")
	toggleBtn = toggleFrame:WaitForChild("ToggleSaveLoad")
	toggleBtn.MouseButton1Click:Connect(function()
		saveManager.Visible = not saveManager.Visible
		saveSlot.Visible = false
		toggleBtn.Text = saveManager.Visible and "Close" or "Open"
		if saveManager.Visible then
			refreshSlotList()
		end
	end)

	-- GameState Save button: opens SaveSlot popup for quick new save
	local saveHolder = gameState:WaitForChild("ButtonHolder"):WaitForChild("SaveHolder")
	local gameSaveBtn = saveHolder:WaitForChild("Save")
	gameSaveBtn.MouseButton1Click:Connect(function()
		currentSlotId = nil
		saveSlot.Visible = true
		saveManager.Visible = false
		toggleBtn.Text = "Open"

		-- Default name based on existing slot count
		local ok, saves = pcall(function() return getSavesRemote:InvokeServer() end)
		local count = (ok and saves) and #saves or 0
		saveTextBox.Text = "Slot #" .. (count + 1)
	end)

	-- GameState Load button: opens SaveManager
	local loadHolder = gameState:WaitForChild("ButtonHolder"):WaitForChild("LoadHolder")
	local gameLoadBtn = loadHolder:WaitForChild("Load")
	gameLoadBtn.MouseButton1Click:Connect(function()
		saveManager.Visible = true
		saveSlot.Visible = false
		toggleBtn.Text = "Close"
		refreshSlotList()
	end)

	-- NewSaveButton in SaveManager: opens SaveSlot popup
	local newSaveFrame = saveManager:WaitForChild("NewSaveButton")
	local newSaveBtn = newSaveFrame:WaitForChild("TextButton")
	newSaveBtn.MouseButton1Click:Connect(function()
		currentSlotId = nil
		saveSlot.Visible = true

		local ok, saves = pcall(function() return getSavesRemote:InvokeServer() end)
		local count = (ok and saves) and #saves or 0
		saveTextBox.Text = "Slot #" .. (count + 1)
	end)

	-- SaveSlot confirm button: actually saves
	local saveBtnHolder = saveSlot:WaitForChild("SaveButtonHolder")
	local confirmSaveBtn = saveBtnHolder:WaitForChild("Save")
	confirmSaveBtn.MouseButton1Click:Connect(function()
		local name = saveTextBox.Text
		if name == "" then name = "Unnamed" end

		local ok, result = pcall(function()
			return saveBuildRemote:InvokeServer(currentSlotId, name)
		end)

		if ok and result then
			log("saved:", name)
		else
			log("save failed:", result)
		end

		saveSlot.Visible = false

		-- Refresh list if manager is open
		if saveManager.Visible then
			refreshSlotList()
		end
	end)

	log("initialized")
end

return SaveLoadUI
