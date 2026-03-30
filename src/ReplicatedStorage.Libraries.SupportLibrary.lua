--[[
	SupportLibrary — Minimal extract from Fork3X.
	Only includes functions needed by Handles.lua and ArcHandles.lua.
	Place in: ReplicatedStorage > Libraries > SupportLibrary (ModuleScript)
]]

local SupportLibrary = {}

function SupportLibrary.FlipTable(Table)
	local FlippedTable = {}
	for Key, Value in Table do
		FlippedTable[Value] = Key
	end
	return FlippedTable
end

function SupportLibrary.Keys(Table)
	local Keys = {}
	for Key in Table do
		table.insert(Keys, Key)
	end
	return Keys
end

function SupportLibrary.AddUserInputListener(InputState, InputTypeFilter, CatchAll, Callback)
	local InputTypes = {}
	if type(InputTypeFilter) == 'string' then
		InputTypes[InputTypeFilter] = true
	elseif type(InputTypeFilter) == 'table' then
		InputTypes = SupportLibrary.FlipTable(InputTypeFilter)
	end

	return game:GetService('UserInputService')['Input' .. InputState]:Connect(function(Input, GameProcessedEvent)
		if GameProcessedEvent and not CatchAll then return end
		if not InputTypes[Input.UserInputType.Name] then return end
		if Input.UserInputType == Enum.UserInputType.Keyboard and game:GetService('UserInputService'):GetFocusedTextBox() then return end
		Callback(Input)
	end)
end

return SupportLibrary
