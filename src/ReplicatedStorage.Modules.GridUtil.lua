local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GridUtil = {}

local CELL = 2
local SUBCELL = 0.25
GridUtil.CELL_SIZE = CELL
GridUtil.SUBCELL_SIZE = SUBCELL

------------------------------------------------------------
-- Float cleanup (removes floating point noise)
------------------------------------------------------------

local function cleanFloat(n: number): number
	local r4 = math.round(n * 4) / 4
	if math.abs(n - r4) < 0.05 then return r4 end
	return math.round(n * 100) / 100
end

function GridUtil.CleanVector(v: Vector3): Vector3
	return Vector3.new(cleanFloat(v.X), cleanFloat(v.Y), cleanFloat(v.Z))
end

------------------------------------------------------------
-- Standard 2x2x2 grid
------------------------------------------------------------

function GridUtil.WorldToGrid(worldPos: Vector3): Vector3
	return Vector3.new(
		math.floor(worldPos.X / CELL),
		math.floor(worldPos.Y / CELL),
		math.floor(worldPos.Z / CELL)
	)
end

function GridUtil.GridToWorld(gridCoord: Vector3): Vector3
	return Vector3.new(
		gridCoord.X * CELL + CELL / 2,
		gridCoord.Y * CELL + CELL / 2,
		gridCoord.Z * CELL + CELL / 2
	)
end

function GridUtil.SnapToGrid(worldPos: Vector3): Vector3
	return GridUtil.GridToWorld(GridUtil.WorldToGrid(worldPos))
end

function GridUtil.AdjacentCell(hitPos: Vector3, hitNormal: Vector3): Vector3
	return GridUtil.WorldToGrid(hitPos + hitNormal * (CELL * 0.5))
end

function GridUtil.HitCell(hitPos: Vector3, hitNormal: Vector3): Vector3
	return GridUtil.WorldToGrid(hitPos - hitNormal * (CELL * 0.5))
end

------------------------------------------------------------
-- Sub-grid (part-size snapping for small parts)
------------------------------------------------------------

function GridUtil.SnapToSubGrid(worldPos: Vector3): Vector3
	return Vector3.new(
		math.round(worldPos.X / SUBCELL) * SUBCELL,
		math.round(worldPos.Y / SUBCELL) * SUBCELL,
		math.round(worldPos.Z / SUBCELL) * SUBCELL
	)
end

local HALF_STUD = 0.5

function GridUtil.SnapToHalfStud(worldPos: Vector3): Vector3
	return Vector3.new(
		math.round(worldPos.X / HALF_STUD) * HALF_STUD,
		math.round(worldPos.Y / HALF_STUD) * HALF_STUD,
		math.round(worldPos.Z / HALF_STUD) * HALF_STUD
	)
end

function GridUtil.ComputeSubGridPlacement(hitPos: Vector3, hitNormal: Vector3, modelSize: Vector3): Vector3
	local absNormal = Vector3.new(math.abs(hitNormal.X), math.abs(hitNormal.Y), math.abs(hitNormal.Z))
	local halfPush = (modelSize / 2):Dot(absNormal)
	local rawPos = hitPos + hitNormal * halfPush
	local snapped = GridUtil.SnapToHalfStud(rawPos)

	local distFromSurface = (snapped - hitPos):Dot(hitNormal)
	if distFromSurface < halfPush * 0.5 then
		snapped = snapped + hitNormal * HALF_STUD
	end

	return snapped
end

------------------------------------------------------------
-- Keys
------------------------------------------------------------

function GridUtil.ToKey(g: Vector3): string
	return string.format("%.2f,%.2f,%.2f", g.X, g.Y, g.Z)
end

function GridUtil.FromKey(key: string): Vector3
	local p = string.split(key, ",")
	return Vector3.new(tonumber(p[1]), tonumber(p[2]), tonumber(p[3]))
end

function GridUtil.RotationCFrame(yIndex: number, xIndex: number?, zIndex: number?): CFrame
	local yRot = CFrame.Angles(0, math.rad((yIndex % 4) * 90), 0)
	local xRot = CFrame.Angles(math.rad(((xIndex or 0) % 4) * 90), 0, 0)
	local zRot = CFrame.Angles(0, 0, math.rad(((zIndex or 0) % 4) * 90))
	return yRot * xRot * zRot
end

------------------------------------------------------------
-- Placeable lookup (recursive through folders)
------------------------------------------------------------

function GridUtil.FindPlaceable(itemName: string): Instance?
	local placeables = ReplicatedStorage:FindFirstChild("Placeables")
	if not placeables then return nil end

	local direct = placeables:FindFirstChild(itemName)
	if direct and not direct:IsA("Folder") then return direct end

	for _, desc in placeables:GetDescendants() do
		if desc.Name == itemName and not desc:IsA("Folder") then
			return desc
		end
	end
	return nil
end

function GridUtil.GetAllPlaceables(): { { name: string, template: Instance } }
	local placeables = ReplicatedStorage:FindFirstChild("Placeables")
	if not placeables then return {} end

	local items = {}
	for _, desc in placeables:GetDescendants() do
		if (desc:IsA("Model") or desc:IsA("BasePart")) and not desc:IsA("Folder") then
			if desc.Parent and not desc.Parent:IsA("Model") then
				table.insert(items, { name = desc.Name, template = desc })
			end
		end
	end
	return items
end

function GridUtil.IsSubGridItem(itemName: string): boolean
	local MechanicsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MechanicsConfig"))
	local cfg = MechanicsConfig[itemName]
	if cfg and cfg.subGrid then return true end

	local template = GridUtil.FindPlaceable(itemName)
	if template then
		for _, desc in template:GetDescendants() do
			if desc:IsA("BasePart") then
				local cfgInner = MechanicsConfig[desc.Name]
				if cfgInner and cfgInner.subGrid then return true end
			end
		end
	end

	return false
end

------------------------------------------------------------
-- Client-side occupancy tracking
------------------------------------------------------------

local clientOccupancy = {}

function GridUtil.RebuildOccupancy()
	clientOccupancy = {}
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return end

	for _, model in placedFolder:GetChildren() do
		if model:IsA("Model") then
			local gc = model:GetAttribute("GridCoord")
			if gc then
				clientOccupancy[GridUtil.ToKey(gc)] = model
			end
		end
	end
end

function GridUtil.SetOccupied(gridCoord: Vector3, model: Model?)
	clientOccupancy[GridUtil.ToKey(gridCoord)] = model
end

function GridUtil.IsOccupied(gridCoord: Vector3, ignoreSet: { [Model]: true }?): boolean
	local key = GridUtil.ToKey(gridCoord)
	local occupant = clientOccupancy[key]
	if not occupant then return false end
	if not occupant.Parent then return false end
	if ignoreSet and ignoreSet[occupant] then return false end
	return true
end

function GridUtil.CanMoveGroup(models: {Model}, gridOffset: Vector3): boolean
	local ignoreSet = {}
	for _, m in models do ignoreSet[m] = true end

	for _, model in models do
		local gc = model:GetAttribute("GridCoord")
		if gc then
			local newGrid = gc + gridOffset
			if GridUtil.IsOccupied(newGrid, ignoreSet) then
				return false
			end
		end
	end
	return true
end

function GridUtil.CheckBoundsOverlap(pos: Vector3, size: Vector3, ignoreModel: Model?): boolean
	local placedFolder = workspace:FindFirstChild("PlacedBlocks")
	if not placedFolder then return false end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { placedFolder }

	local touching = workspace:GetPartBoundsInBox(CFrame.new(pos), size - Vector3.new(0.1, 0.1, 0.1), overlapParams)
	for _, part in touching do
		if part:IsA("BasePart") then
			if ignoreModel and part:IsDescendantOf(ignoreModel) then continue end
			return true
		end
	end
	return false
end

return GridUtil
