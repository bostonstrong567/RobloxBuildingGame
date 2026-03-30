local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RepModules = ReplicatedStorage:WaitForChild("Modules")
local SSModules = ServerScriptService:WaitForChild("Modules")
local Config = require(RepModules:WaitForChild("MechanicsConfig"))
local FaceUtil = require(RepModules:WaitForChild("FaceUtil"))
local StateManager = require(SSModules:WaitForChild("StateManager"))

local MechanicsService = {}

local AXIS_MAP = {
	X = Vector3.new(1, 0, 0),
	Y = Vector3.new(0, 1, 0),
	Z = Vector3.new(0, 0, 1),
}

local FACE_NAME_TO_ID = {
	Top = Enum.NormalId.Top,
	Bottom = Enum.NormalId.Bottom,
	Left = Enum.NormalId.Left,
	Right = Enum.NormalId.Right,
	Front = Enum.NormalId.Front,
	Back = Enum.NormalId.Back,
}

local playerPlayState = {}

local function log(...)
	print("[Mechanics]", ...)
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function isSideAllowed(cfg, face: Enum.NormalId): boolean
	if not cfg.actionSides then return true end
	for _, name in cfg.actionSides do
		if FACE_NAME_TO_ID[name] == face then return true end
	end
	return false
end

local function findBase(model: Model): BasePart?
	local main = model:FindFirstChild("Main")
	if main and main:IsA("BasePart") then return main end

	local best: BasePart? = nil
	local bestVol = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local s = d.Size
			local vol = s.X * s.Y * s.Z
			if vol > bestVol then bestVol = vol; best = d end
		end
	end
	return best
end

local function findMechPart(model: Model, base: BasePart): BasePart?
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= base and Config[desc.Name] then
			return desc
		end
	end
	return nil
end

local function noCollide(partA: BasePart, partB: BasePart)
	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0 = partA
	nc.Part1 = partB
	nc.Parent = partA
end

local function getJointPoint(base: BasePart, part: BasePart): Vector3
	local face = FaceUtil.GetClosestFaceTowardPart(base, part)
	local faceNormal = FaceUtil.GetFaceWorldNormal(base, face)
	return base.Position + faceNormal * (base.Size / 2):Dot(faceNormal:Abs())
end

------------------------------------------------------------
-- Weld creation
------------------------------------------------------------

local function alreadyWelded(partA: BasePart, partB: BasePart): boolean
	for _, child in partA:GetChildren() do
		if child:IsA("WeldConstraint") then
			if (child.Part0 == partA and child.Part1 == partB)
				or (child.Part0 == partB and child.Part1 == partA) then
				return true
			end
		end
	end
	for _, child in partB:GetChildren() do
		if child:IsA("WeldConstraint") then
			if (child.Part0 == partA and child.Part1 == partB)
				or (child.Part0 == partB and child.Part1 == partA) then
				return true
			end
		end
	end
	return false
end

local function createWeld(partA: BasePart, partB: BasePart)
	if alreadyWelded(partA, partB) then return end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = partA
	weld.Part1 = partB
	weld.Name = "MechWeld"
	weld.Parent = partB

	noCollide(partA, partB)
end

------------------------------------------------------------
-- BUILDERS: constraint setup during Build Mode
------------------------------------------------------------

local function buildHinge(base: BasePart, part: BasePart, cfg)
	local localAxis = AXIS_MAP[cfg.axis or "Y"]
	local worldAxis = base.CFrame:VectorToWorldSpace(localAxis)
	local jointPoint = getJointPoint(base, part)

	local att0 = Instance.new("Attachment")
	att0.Parent = base
	att0.WorldPosition = jointPoint
	att0.WorldAxis = worldAxis

	local att1 = Instance.new("Attachment")
	att1.Parent = part
	att1.WorldPosition = jointPoint
	att1.WorldAxis = worldAxis

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1

	if cfg.motor then
		hinge.ActuatorType = Enum.ActuatorType.Motor
		hinge.AngularVelocity = 0
		hinge.MotorMaxTorque = cfg.torque or 1000
	end

	if cfg.limits then
		hinge.LimitsEnabled = true
		hinge.LowerAngle = cfg.limits[1]
		hinge.UpperAngle = cfg.limits[2]
	end

	hinge.Parent = base
	noCollide(base, part)
end

local function buildPrismatic(base: BasePart, part: BasePart, cfg)
	local axis = AXIS_MAP[cfg.axis or "Y"]

	local att0 = Instance.new("Attachment")
	att0.Axis = axis
	att0.WorldPosition = part.Position
	att0.Parent = base

	local att1 = Instance.new("Attachment")
	att1.Axis = axis
	att1.Parent = part

	local pris = Instance.new("PrismaticConstraint")
	pris.Attachment0 = att0
	pris.Attachment1 = att1

	if cfg.motor then
		pris.ActuatorType = Enum.ActuatorType.Motor
		pris.Velocity = 0
		pris.MotorMaxForce = cfg.force or 500
	end

	if cfg.limits then
		pris.LimitsEnabled = true
		pris.LowerLimit = cfg.limits[1]
		pris.UpperLimit = cfg.limits[2]
	end

	pris.Parent = base
	noCollide(base, part)
end

local function buildCylindrical(base: BasePart, part: BasePart, cfg)
	local localAxis = AXIS_MAP[cfg.axis or "X"]
	local worldAxis = base.CFrame:VectorToWorldSpace(localAxis)
	local jointPoint = getJointPoint(base, part)

	local att0 = Instance.new("Attachment")
	att0.Parent = base
	att0.WorldPosition = jointPoint
	att0.WorldAxis = worldAxis

	local att1 = Instance.new("Attachment")
	att1.Parent = part
	att1.WorldPosition = jointPoint
	att1.WorldAxis = worldAxis

	local cyl = Instance.new("CylindricalConstraint")
	cyl.Attachment0 = att0
	cyl.Attachment1 = att1
	cyl.InclinationAngle = 0

	if cfg.motor then
		cyl.AngularActuatorType = Enum.ActuatorType.Motor
		cyl.AngularVelocity = 0
		cyl.MotorMaxAngularAcceleration = 500
		cyl.MotorMaxTorque = cfg.torque or 50000
	end

	cyl.Parent = base
	noCollide(base, part)

	if cfg.material then
		local matEnum = Enum.Material[cfg.material]
		if matEnum then
			part.Material = matEnum
		end
	end

	part.CustomPhysicalProperties = PhysicalProperties.new(
		cfg.density or 1.3,
		cfg.friction or 1.5,
		cfg.elasticity or 0.95,
		1.0,
		cfg.frictionWeight or 3
	)
end

local function buildSpring(base: BasePart, part: BasePart, cfg)
	local att0 = Instance.new("Attachment")
	att0.Parent = base

	local att1 = Instance.new("Attachment")
	att1.Parent = part

	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = cfg.stiffness or 500
	spring.Damping = cfg.damping or 50
	spring.FreeLength = cfg.freeLength or 4
	spring.Visible = true
	spring.Coils = 5

	if cfg.minLength and cfg.maxLength then
		spring.LimitsEnabled = true
		spring.MinLength = cfg.minLength
		spring.MaxLength = cfg.maxLength
	end

	spring.Parent = base
	noCollide(base, part)
end

local function buildRope(base: BasePart, part: BasePart, cfg)
	local att0 = Instance.new("Attachment")
	att0.Parent = base

	local att1 = Instance.new("Attachment")
	att1.Parent = part

	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = att0
	rope.Attachment1 = att1
	rope.Length = cfg.length or 10
	rope.Visible = true

	rope.Parent = base
	noCollide(base, part)
end

local function buildBallSocket(base: BasePart, part: BasePart, cfg)
	local jointPoint = getJointPoint(base, part)

	local att0 = Instance.new("Attachment")
	att0.Parent = base
	att0.WorldPosition = jointPoint

	local att1 = Instance.new("Attachment")
	att1.Parent = part
	att1.WorldPosition = jointPoint

	local bs = Instance.new("BallSocketConstraint")
	bs.Attachment0 = att0
	bs.Attachment1 = att1

	if cfg.twistLimits then
		bs.TwistLimitsEnabled = true
		bs.TwistLowerAngle = cfg.twistLimits[1]
		bs.TwistUpperAngle = cfg.twistLimits[2]
	end

	bs.Parent = base
	noCollide(base, part)
end

local BUILDERS = {
	HingeConstraint = buildHinge,
	PrismaticConstraint = buildPrismatic,
	CylindricalConstraint = buildCylindrical,
	SpringConstraint = buildSpring,
	RopeConstraint = buildRope,
	BallSocketConstraint = buildBallSocket,
}

------------------------------------------------------------
-- RUNTIME_BEHAVIORS: effects during Play Mode
------------------------------------------------------------

local function startThruster(model, part, cfg)
	local att = Instance.new("Attachment")
	att.Name = "RuntimeAtt"
	att.Parent = part

	local vf = Instance.new("VectorForce")
	vf.Name = "RuntimeForce"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	local axisVec = AXIS_MAP[cfg.axis or "Y"]
	vf.Force = axisVec * (cfg.thrustForce or 1200)
	vf.Parent = part
end

local function stopThruster(model, part, cfg)
	local vf = part:FindFirstChild("RuntimeForce")
	if vf then vf:Destroy() end
	local att = part:FindFirstChild("RuntimeAtt")
	if att then att:Destroy() end
end

local function startBalloon(model, part, cfg)
	local att = Instance.new("Attachment")
	att.Name = "RuntimeAtt"
	att.Parent = part

	local vf = Instance.new("VectorForce")
	vf.Name = "RuntimeForce"
	vf.Attachment0 = att
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Force = Vector3.new(0, cfg.liftForce or 800, 0)
	vf.Parent = part
end

local function stopBalloon(model, part, cfg)
	stopThruster(model, part, cfg)
end

local function startWheel(model, part, cfg)
	local direction = model:GetAttribute("MotorDirection") or 1
	local speed = (cfg.speed or 4) * direction
	for _, desc in model:GetDescendants() do
		if desc:IsA("CylindricalConstraint") then
			desc.AngularVelocity = speed
		end
	end
end

local function stopWheel(model, part, cfg)
	for _, desc in model:GetDescendants() do
		if desc:IsA("CylindricalConstraint") then
			desc.AngularVelocity = 0
		end
	end
end

local RUNTIME_BEHAVIORS = {
	thruster = { start = startThruster, stop = stopThruster },
	balloon = { start = startBalloon, stop = stopBalloon },
	wheel = { start = startWheel, stop = stopWheel },
}

------------------------------------------------------------
-- Generic motor start/stop
------------------------------------------------------------

local function startConstraintMotors(model)
	local direction = model:GetAttribute("MotorDirection") or 1

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and Config[desc.Name] then
			local cfg = Config[desc.Name]
			if not cfg.motor then continue end

			local speed = (cfg.speed or 2) * direction
			for _, child in model:GetDescendants() do
				if child:IsA("HingeConstraint") and child.ActuatorType == Enum.ActuatorType.Motor then
					child.AngularVelocity = speed
				elseif child:IsA("PrismaticConstraint") and child.ActuatorType == Enum.ActuatorType.Motor then
					child.Velocity = speed
				elseif child:IsA("CylindricalConstraint") and child.AngularActuatorType == Enum.ActuatorType.Motor then
					child.AngularVelocity = speed
				end
			end
			break
		end
	end
end

local function stopAllMotors(folder)
	for _, desc in folder:GetDescendants() do
		if desc:IsA("HingeConstraint") then
			desc.AngularVelocity = 0
		elseif desc:IsA("PrismaticConstraint") then
			desc.Velocity = 0
		elseif desc:IsA("CylindricalConstraint") then
			desc.AngularVelocity = 0
		end
	end
end

------------------------------------------------------------
-- Neighbor detection
------------------------------------------------------------

local function findActionSideNeighbors(part: BasePart, ownModel: Model, cfg): {BasePart}
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return {} end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { placedFolder }

	local size = part.Size + Vector3.new(0.4, 0.4, 0.4)
	local touching = workspace:GetPartBoundsInBox(part.CFrame, size, overlapParams)

	local neighbors = {}
	for _, hit in touching do
		if hit:IsA("BasePart") and not hit:IsDescendantOf(ownModel) then
			local face = FaceUtil.GetClosestFaceTowardPart(part, hit)
			if isSideAllowed(cfg, face) then
				table.insert(neighbors, hit)
			end
		end
	end

	return neighbors
end

local function connectToExistingMechanicals(model: Model)
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return end

	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then continue end
		if Config[part.Name] then continue end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = { placedFolder }

		local size = part.Size + Vector3.new(0.4, 0.4, 0.4)
		local touching = workspace:GetPartBoundsInBox(part.CFrame, size, overlapParams)

		for _, neighbor in touching do
			if neighbor:IsA("BasePart") and not neighbor:IsDescendantOf(model) then
				local cfg = Config[neighbor.Name]
				if cfg and cfg.connectsToNeighbors then
					local face = FaceUtil.GetClosestFaceTowardPart(neighbor, part)
					if isSideAllowed(cfg, face) then
						createWeld(neighbor, part)
					end
				end
			end
		end
	end
end

------------------------------------------------------------
-- Weld map + flood fill
------------------------------------------------------------

local function buildWeldMap(folder): { [BasePart]: { [BasePart]: true } }
	local map = {}
	for _, desc in folder:GetDescendants() do
		if desc:IsA("WeldConstraint") and desc.Part0 and desc.Part1
			and desc.Part0.Parent and desc.Part1.Parent then

			local p0, p1 = desc.Part0, desc.Part1
			if not map[p0] then map[p0] = {} end
			if not map[p1] then map[p1] = {} end
			map[p0][p1] = true
			map[p1][p0] = true
		end
	end
	return map
end

local function floodFillFrom(startParts: {BasePart}, weldMap): { [BasePart]: true }
	local visited = {}
	local queue = {}
	for _, p in startParts do
		visited[p] = true
		table.insert(queue, p)
	end

	while #queue > 0 do
		local current = table.remove(queue, 1)
		local connections = weldMap[current]
		if connections then
			for other in connections do
				if not visited[other] then
					visited[other] = true
					table.insert(queue, other)
				end
			end
		end
	end

	return visited
end

------------------------------------------------------------
-- Grounding: find parts sitting on baseplate
------------------------------------------------------------

local function findGroundedParts(): { [BasePart]: true }
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return {} end

	local baseplate = workspace:FindFirstChild("Baseplate")
	if not baseplate then return {} end

	local bpTop = baseplate.Position.Y + baseplate.Size.Y / 2

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { placedFolder }

	local checkHeight = 2.5
	local checkCF = CFrame.new(baseplate.Position.X, bpTop + checkHeight / 2, baseplate.Position.Z)
	local checkSize = Vector3.new(baseplate.Size.X + 0.4, checkHeight, baseplate.Size.Z + 0.4)
	local touching = workspace:GetPartBoundsInBox(checkCF, checkSize, overlapParams)

	local seeds = {}
	for _, part in touching do
		if part:IsA("BasePart") then
			local partBottom = part.Position.Y - part.Size.Y / 2
			if partBottom < bpTop + 1.5 then
				table.insert(seeds, part)
			end
		end
	end

	local weldMap = buildWeldMap(placedFolder)
	return floodFillFrom(seeds, weldMap)
end

------------------------------------------------------------
-- PLAY MODE
------------------------------------------------------------

function MechanicsService.EnterPlayMode(plr: Player, occupancy, placeBlockFn, placeSubGridFn)
	if playerPlayState[plr] then return false end

	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return false end

	local snapshot = {}
	local playerParts = {}
	local playerModels = {}

	for _, model in placedFolder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("PlacedBy") == plr.UserId then
			table.insert(playerModels, model)
			for _, desc in model:GetDescendants() do
				if desc:IsA("BasePart") then
					snapshot[desc] = {
						cframe = desc.CFrame,
						size = desc.Size,
						anchored = desc.Anchored,
					}
					table.insert(playerParts, desc)
				end
			end
		end
	end

	local groundedParts = findGroundedParts()

	local groundedCount = 0
	for _ in groundedParts do groundedCount += 1 end

	local unanchoredCount = 0
	for _, part in playerParts do
		if not groundedParts[part] then
			part.Anchored = false
			unanchoredCount += 1
		end
	end

	log("Play Mode: grounded", groundedCount, "unanchored", unanchoredCount, "of", #playerParts)

	for _, model in playerModels do
		startConstraintMotors(model)

		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") and Config[desc.Name] then
				local cfg = Config[desc.Name]
				if cfg.runtime then
					local beh = RUNTIME_BEHAVIORS[cfg.runtime]
					if beh and beh.start then
						beh.start(model, desc, cfg)
						log("Runtime started:", cfg.runtime, "on", model.Name, "part:", desc.Name, "anchored:", desc.Anchored)
					end
				end
			end
		end
	end

	for _, part in playerParts do
		if not part.Anchored then
			part:ApplyImpulse(Vector3.new(0, 0.01, 0))
		end
	end

	local activeParts = {}
	for _, part in playerParts do
		if not groundedParts[part] then
			activeParts[part] = true
		end
	end

	playerPlayState[plr] = {
		snapshot = snapshot,
		playing = true,
		removedDuringPlay = {},
		occupancyRef = occupancy,
		placeBlockFn = placeBlockFn,
		placeSubGridFn = placeSubGridFn,
		activeParts = activeParts,
	}

	log("Play Mode ON for", plr.Name)
	return true
end

------------------------------------------------------------
-- BUILD MODE (Besiege-style reset)
------------------------------------------------------------

function MechanicsService.ExitPlayMode(plr: Player)
	local state = playerPlayState[plr]
	if not state then return false end

	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if placedFolder then
		for _, model in placedFolder:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("PlacedBy") == plr.UserId then
				for _, desc in model:GetDescendants() do
					if desc:IsA("BasePart") and Config[desc.Name] then
						local cfg = Config[desc.Name]
						if cfg.runtime then
							local beh = RUNTIME_BEHAVIORS[cfg.runtime]
							if beh and beh.stop then
								beh.stop(model, desc, cfg)
							end
						end
					end
				end
			end
		end

		stopAllMotors(placedFolder)
	end

	for part, data in state.snapshot do
		if part.Parent then
			part.Anchored = true
			part.CFrame = data.cframe
			part.Size = data.size
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end

	if #state.removedDuringPlay > 0 then
		for _, info in state.removedDuringPlay do
			if info.subGrid and state.placeSubGridFn and info.worldPos then
				state.placeSubGridFn(plr, info.itemName, info.worldPos, info.rotY, info.rotX)
			elseif state.placeBlockFn and info.gridCoord then
				state.placeBlockFn(plr, info.itemName, info.gridCoord, info.rotY, info.rotX)
			end
		end
		log("Restored", #state.removedDuringPlay, "removed parts")
	end

	playerPlayState[plr] = nil
	log("Build Mode restored for", plr.Name)
	return true
end

function MechanicsService.IsPlaying(plr: Player): boolean
	return playerPlayState[plr] ~= nil
end

------------------------------------------------------------
-- RemovablePart: destroy during play mode
------------------------------------------------------------

function MechanicsService.RemoveDuringPlay(model: Model, plr: Player, occupancy)
	if not playerPlayState[plr] then return end

	local state = playerPlayState[plr]
	local isSubGrid = model:GetAttribute("SubGrid")
	local gridCoord = model:GetAttribute("GridCoord")
	local worldPos = model:GetAttribute("WorldPos")

	local stateData = StateManager.Get(model)
	local ry = stateData and stateData.rotation.y or 0
	local rx = stateData and stateData.rotation.x or 0

	table.insert(state.removedDuringPlay, {
		itemName = model.Name,
		gridCoord = gridCoord,
		worldPos = worldPos,
		subGrid = isSubGrid,
		rotY = ry,
		rotX = rx,
	})

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			state.snapshot[desc] = nil
			state.activeParts[desc] = nil
		end
	end

	local GridUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GridUtil"))
	if gridCoord then
		occupancy[GridUtil.ToKey(gridCoord)] = nil
	end

	StateManager.Unregister(model)
	model:Destroy()

	local groundedParts = findGroundedParts()
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if placedFolder then
		local released = 0
		for _, desc in placedFolder:GetDescendants() do
			if desc:IsA("BasePart") and desc.Anchored and not groundedParts[desc] then
				desc.Anchored = false
				desc:ApplyImpulse(Vector3.new(0, 0.01, 0))
				state.activeParts[desc] = true
				released += 1
			end
		end
		if released > 0 then
			log("Released", released, "parts after removal")
		end
	end
end

------------------------------------------------------------
-- Anti-sleep pulse (only active parts, skip force blocks)
------------------------------------------------------------

RunService.PreSimulation:Connect(function()
	for _, state in playerPlayState do
		if not state.playing then continue end
		for part in state.activeParts do
			if not part.Parent or part.Anchored then continue end
			if part:FindFirstChild("RuntimeForce") then continue end
			if part.AssemblyLinearVelocity.Magnitude < 0.05
				and part.AssemblyAngularVelocity.Magnitude < 0.05 then
				part:ApplyImpulse(Vector3.new(0, 0.001, 0))
			end
		end
	end
end)

------------------------------------------------------------
-- Query helpers
------------------------------------------------------------

function MechanicsService.IsMechanical(model: Model): boolean
	local base = findBase(model)
	if not base then return false end
	return findMechPart(model, base) ~= nil
end

function MechanicsService.IsActivatable(model: Model): boolean
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and Config[desc.Name] then
			local cfg = Config[desc.Name]
			if cfg.activatable then return true end
		end
	end
	return false
end

function MechanicsService.GetBehavior(model: Model): string?
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and Config[desc.Name] then
			local cfg = Config[desc.Name]
			return cfg.behavior or "toggle"
		end
	end
	return nil
end

function MechanicsService.OnBlockRemoved(removedModel: Model) end

------------------------------------------------------------
-- Apply: called when any model is placed (Build Mode)
------------------------------------------------------------

function MechanicsService.Apply(model: Model)
	local base = findBase(model)
	if not base then return end

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local cfg = Config[desc.Name]

			if desc ~= base then
				if cfg and cfg.constraint then
					local builder = BUILDERS[cfg.constraint]
					if builder then
						builder(base, desc, cfg)
						log("Built", cfg.constraint, "for", desc.Name, "in", model.Name)
					end
				else
					if not alreadyWelded(base, desc) then
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = base
						weld.Part1 = desc
						weld.Name = "InternalWeld"
						weld.Parent = desc
						noCollide(base, desc)
					end
				end
			end

			if cfg and cfg.connectsToNeighbors then
				local neighbors = findActionSideNeighbors(desc, model, cfg)
				for _, neighbor in neighbors do
					createWeld(desc, neighbor)
				end
			end
		end
	end

	connectToExistingMechanicals(model)

	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = true
		end
	end
end

function MechanicsService.OnPlayerLeaving(plr: Player)
	if playerPlayState[plr] then
		MechanicsService.ExitPlayMode(plr)
	end
end

return MechanicsService
