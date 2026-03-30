--[[
	History — Undo/Redo stack for building actions.
	Place in: ReplicatedStorage > Modules > History (ModuleScript)
	Adapted from Fork3X Core/History.lua.

	Each record must have:
	  Apply(record)   — redo the action
	  Unapply(record) — undo the action
]]

local History = {}

History.Stack = {}
History.Index = 0

local MAX_STACK = 50

local function log(...)
	print("[History]", ...)
end

function History.Add(record)
	-- Clear any future history (redo stack)
	for i = History.Index + 1, #History.Stack do
		History.Stack[i] = nil
	end

	History.Index += 1
	History.Stack[History.Index] = record

	-- Trim old history if too large
	if History.Index > MAX_STACK then
		table.remove(History.Stack, 1)
		History.Index -= 1
	end

	log("recorded:", record.description or "action", "index:", History.Index)
end

function History.Undo()
	if History.Index < 1 then
		log("nothing to undo")
		return
	end

	local record = History.Stack[History.Index]
	if record and record.Unapply then
		record:Unapply()
		log("undid:", record.description or "action")
	end

	History.Index -= 1
end

function History.Redo()
	if History.Index >= #History.Stack then
		log("nothing to redo")
		return
	end

	History.Index += 1
	local record = History.Stack[History.Index]
	if record and record.Apply then
		record:Apply()
		log("redid:", record.description or "action")
	end
end

function History.Clear()
	History.Stack = {}
	History.Index = 0
	log("cleared")
end

function History.CanUndo(): boolean
	return History.Index >= 1
end

function History.CanRedo(): boolean
	return History.Index < #History.Stack
end

return History
