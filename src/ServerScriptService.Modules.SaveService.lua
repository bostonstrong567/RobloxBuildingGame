--[[
	SaveService — Handles DataStore persistence for player builds.
	Place in: ServerScriptService > Modules > SaveService (ModuleScript)

	Each player gets up to MAX_SLOTS save slots.
	Each slot stores: { name, blocks = { {item, gx, gy, gz, ry, rx}, ... }, savedAt }
	Falls back to in-memory storage when DataStore is unavailable (Studio testing).
]]

local DataStoreService = game:GetService("DataStoreService")

local SaveService = {}

local STORE_NAME = "PlayerBuilds_v1"
local MAX_SLOTS = 10

-- In-memory fallback for Studio testing
local memoryStore = {}

local function log(...)
	print("[SaveService]", ...)
end

local function getStore()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then return store end
	log("DataStore unavailable, using memory fallback:", store)
	return nil
end

local function getPlayerData(userId: number): {}
	local store = getStore()

	if store then
		local ok, data = pcall(function()
			return store:GetAsync(tostring(userId))
		end)
		if ok and data then return data end
		if not ok then log("GetAsync failed:", data) end
	end

	-- Fallback to memory
	return memoryStore[userId] or {}
end

local function setPlayerData(userId: number, data: {}): boolean
	local store = getStore()

	if store then
		local ok, err = pcall(function()
			store:SetAsync(tostring(userId), data)
		end)
		if not ok then
			log("SetAsync failed:", err)
			-- Fall through to memory
		else
			return true
		end
	end

	-- Memory fallback
	memoryStore[userId] = data
	log("saved to memory for userId:", userId)
	return true
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function SaveService.GetSlots(userId: number): { { id: number, name: string } }
	local data = getPlayerData(userId)
	local slots = {}

	for i, slot in data do
		if type(slot) == "table" and slot.name then
			table.insert(slots, { id = i, name = slot.name })
		end
	end

	return slots
end

function SaveService.SaveSlot(userId: number, slotId: number?, slotName: string, blocks: {}): (boolean, string?)
	local data = getPlayerData(userId)

	local id = slotId
	if not id then
		-- Find next available slot
		id = #data + 1
		if id > MAX_SLOTS then
			return false, "Max save slots reached (" .. MAX_SLOTS .. ")"
		end
	end

	if id < 1 or id > MAX_SLOTS then
		return false, "Invalid slot id"
	end

	data[id] = {
		name = slotName,
		blocks = blocks,
		savedAt = os.time(),
	}

	local ok = setPlayerData(userId, data)
	if ok then
		log("saved slot", id, "for userId", userId, "(" .. #blocks .. " blocks)")
	end
	return ok, ok and nil or "Save failed"
end

function SaveService.LoadSlot(userId: number, slotId: number): { name: string, blocks: {} }?
	local data = getPlayerData(userId)

	if not data[slotId] or type(data[slotId]) ~= "table" then
		return nil
	end

	local slot = data[slotId]
	log("loaded slot", slotId, "for userId", userId, "(" .. #(slot.blocks or {}) .. " blocks)")
	return slot
end

return SaveService
