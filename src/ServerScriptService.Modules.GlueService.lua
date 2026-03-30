--[[
	GlueService — Manages glue (WeldConstraint) connections between placed blocks.
	Place in: ServerScriptService > Modules > GlueService (ModuleScript)
]]

local GlueService = {}

local GLUE_TAG = "GlueWeld"

local function log(...)
	print("[GlueService]", ...)
end

local function getPlacedFolder()
	return workspace:FindFirstChild("PlacedBlocks")
end

local function alreadyGlued(partA: BasePart, partB: BasePart): boolean
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

function GlueService.GlueParts(partA: BasePart, partB: BasePart): WeldConstraint?
	if partA == partB then return nil end
	if alreadyGlued(partA, partB) then return nil end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = partA
	weld.Part1 = partB
	weld.Name = GLUE_TAG
	weld.Parent = partA

	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0 = partA
	nc.Part1 = partB
	nc.Parent = partA

	log("glued:", partA:GetFullName(), "<->", partB:GetFullName())
	return weld
end

function GlueService.UnglueParts(partA: BasePart, partB: BasePart)
	local removed = 0
	for _, parent in { partA, partB } do
		for _, child in parent:GetChildren() do
			if child:IsA("WeldConstraint") and child.Name == GLUE_TAG then
				if (child.Part0 == partA and child.Part1 == partB)
					or (child.Part0 == partB and child.Part1 == partA) then
					child:Destroy()
					removed += 1
				end
			end
		end
	end
	if removed > 0 then
		log("unglued:", partA:GetFullName(), "<->", partB:GetFullName(), "removed:", removed)
	end
end

function GlueService.AutoGlueToNeighbors(model: Model)
	local placedFolder = getPlacedFolder()
	if not placedFolder then return end

	local didGlue = false

	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then continue end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = { placedFolder }

		local size = part.Size + Vector3.new(0.4, 0.4, 0.4)
		local touching = workspace:GetPartBoundsInBox(part.CFrame, size, overlapParams)

		for _, neighbor in touching do
			if not neighbor:IsDescendantOf(model) and neighbor:IsA("BasePart") then
				-- Skip neighbors that are unanchored (part of an active contraption)
				if not neighbor.Anchored then continue end

				local weld = GlueService.GlueParts(part, neighbor)
				if weld then
					didGlue = true
				end
			end
		end
	end

	return didGlue
end

return GlueService
