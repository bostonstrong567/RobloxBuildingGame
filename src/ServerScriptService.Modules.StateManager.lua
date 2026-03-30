--[[
	StateManager — Tracks the state of every placed block/model.
	Place in: ServerScriptService > Modules > StateManager (ModuleScript)
]]

local StateManager = {}

local states = {}
local nextId = 1

local function log(...)
	print("[StateManager]", ...)
end

export type BlockState = {
	id: number,
	instance: Model,
	gridCoord: Vector3,
	placedBy: number?,
	rotation: { y: number, x: number },
	physicsState: "anchored" | "unanchored" | "constrained",
	anchored: boolean,
	connections: { [number]: string },
}

function StateManager.Register(model: Model, gridCoord: Vector3, placedBy: number?, rotY: number, rotX: number): number
	local id = nextId
	nextId += 1

	local state: BlockState = {
		id = id,
		instance = model,
		gridCoord = gridCoord,
		placedBy = placedBy,
		rotation = { y = rotY, x = rotX },
		physicsState = "anchored",
		anchored = true,
		connections = {},
	}

	states[id] = state
	model:SetAttribute("StateId", id)

	log("registered", model.Name, "id:", id, "grid:", gridCoord)
	return id
end

function StateManager.Unregister(idOrModel: number | Model)
	local id = idOrModel
	if typeof(idOrModel) ~= "number" then
		id = idOrModel:GetAttribute("StateId")
	end
	if not id or not states[id] then return end

	local state = states[id]
	log("unregistered", state.instance.Name, "id:", id)

	for connId in state.connections do
		local other = states[connId]
		if other then
			other.connections[id] = nil
		end
	end

	states[id] = nil
end

function StateManager.Get(idOrModel: number | Model): BlockState?
	local id = idOrModel
	if typeof(idOrModel) ~= "number" then
		id = idOrModel:GetAttribute("StateId")
	end
	if not id then return nil end
	return states[id]
end

function StateManager.SetPhysicsState(id: number, physState: string, anchored: boolean)
	local state = states[id]
	if not state then return end
	state.physicsState = physState
	state.anchored = anchored
	log("physics:", state.instance.Name, "->", physState, "anchored:", anchored)
end

function StateManager.GetAll(): { [number]: BlockState }
	return states
end

------------------------------------------------------------
-- Snapshot / Restore — captures full physical state of parts
-- Used by activate/deactivate to reset to pre-activation state
------------------------------------------------------------

export type PartSnapshot = {
	cframe: CFrame,
	anchored: boolean,
	linearVelocity: Vector3,
	angularVelocity: Vector3,
}

export type ContraptionSnapshot = {
	parts: { [BasePart]: PartSnapshot },
	stateUpdates: { [number]: { physicsState: string, anchored: boolean } },
}

function StateManager.Snapshot(partSet: { [BasePart]: true }): ContraptionSnapshot
	local snapshot: ContraptionSnapshot = {
		parts = {},
		stateUpdates = {},
	}

	for part in partSet do
		if not part.Parent then continue end

		snapshot.parts[part] = {
			cframe = part.CFrame,
			anchored = part.Anchored,
			linearVelocity = part.AssemblyLinearVelocity,
			angularVelocity = part.AssemblyAngularVelocity,
		}

		-- Also save StateManager's tracked state for this part's model
		local model = part:FindFirstAncestorWhichIsA("Model")
		if model then
			local state = StateManager.Get(model)
			if state and not snapshot.stateUpdates[state.id] then
				snapshot.stateUpdates[state.id] = {
					physicsState = state.physicsState,
					anchored = state.anchored,
				}
			end
		end
	end

	local count = 0
	for _ in snapshot.parts do count += 1 end
	log("snapshot saved:", count, "parts")
	return snapshot
end

function StateManager.Restore(snapshot: ContraptionSnapshot)
	local count = 0

	for part, data in snapshot.parts do
		if not part.Parent then continue end

		-- Anchor first (stops physics), then set position
		part.Anchored = data.anchored
		part.CFrame = data.cframe
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		count += 1
	end

	-- Restore StateManager tracked state
	for id, data in snapshot.stateUpdates do
		local state = states[id]
		if state then
			state.physicsState = data.physicsState
			state.anchored = data.anchored
		end
	end

	log("snapshot restored:", count, "parts")
end

return StateManager
