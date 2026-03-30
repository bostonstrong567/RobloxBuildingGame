--[[
	FaceUtil — Face/normal detection utilities for the placement system.
	Place in: ReplicatedStorage > Modules > FaceUtil (ModuleScript)
]]

local FaceUtil = {}

local OPPOSITES = {
	[Enum.NormalId.Top] = Enum.NormalId.Bottom,
	[Enum.NormalId.Bottom] = Enum.NormalId.Top,
	[Enum.NormalId.Left] = Enum.NormalId.Right,
	[Enum.NormalId.Right] = Enum.NormalId.Left,
	[Enum.NormalId.Front] = Enum.NormalId.Back,
	[Enum.NormalId.Back] = Enum.NormalId.Front,
}

local FACE_VECTORS = {
	[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
	[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
	[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
	[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
	[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
	[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
}

function FaceUtil.GetOppositeFace(face)
	return OPPOSITES[face]
end

function FaceUtil.NormalToFace(part, worldNormal)
	local localNormal = part.CFrame:VectorToObjectSpace(worldNormal)

	local ax = math.abs(localNormal.X)
	local ay = math.abs(localNormal.Y)
	local az = math.abs(localNormal.Z)

	if ax >= ay and ax >= az then
		return localNormal.X > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	elseif ay >= ax and ay >= az then
		return localNormal.Y > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
	else
		return localNormal.Z > 0 and Enum.NormalId.Back or Enum.NormalId.Front
	end
end

function FaceUtil.FaceToWorldVector(part, face)
	local localVector = FACE_VECTORS[face]
	if not localVector then
		return nil
	end
	return part.CFrame:VectorToWorldSpace(localVector)
end

function FaceUtil.GetClosestFaceFromPoint(part, worldPoint)
	local localPos = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5

	local x = localPos.X / half.X
	local y = localPos.Y / half.Y
	local z = localPos.Z / half.Z

	local ax = math.abs(x)
	local ay = math.abs(y)
	local az = math.abs(z)

	if ax >= ay and ax >= az then
		return x > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	elseif ay >= ax and ay >= az then
		return y > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
	else
		return z > 0 and Enum.NormalId.Back or Enum.NormalId.Front
	end
end

function FaceUtil.GetClosestFaceTowardPart(subjectPart, otherPart)
	return FaceUtil.GetClosestFaceFromPoint(subjectPart, otherPart.Position)
end

function FaceUtil.GetTouchingFaces(partA, partB)
	local faceA = FaceUtil.GetClosestFaceTowardPart(partA, partB)
	local faceB = FaceUtil.GetClosestFaceTowardPart(partB, partA)
	return faceA, faceB
end

function FaceUtil.AreTouching(partA, partB, overlapParams)
	local parts = workspace:GetPartsInPart(partA, overlapParams)

	for _, part in ipairs(parts) do
		if part == partB then
			return true
		end
	end

	return false
end

function FaceUtil.GetTouchingFacesChecked(partA, partB, overlapParams)
	if FaceUtil.AreTouching(partA, partB, overlapParams) then
		return FaceUtil.GetTouchingFaces(partA, partB)
	end
	return nil, nil
end

function FaceUtil.GetFaceFromRaycastResult(result)
	if not result or not result.Instance then
		return nil
	end
	return FaceUtil.NormalToFace(result.Instance, result.Normal)
end

function FaceUtil.GetFacesFromRaycastResult(casterPart, result)
	if not result or not result.Instance then
		return nil, nil
	end

	local hitFace = FaceUtil.NormalToFace(result.Instance, result.Normal)
	local casterFace = FaceUtil.GetOppositeFace(hitFace)

	if casterPart then
		local casterNormal = -result.Normal
		casterFace = FaceUtil.NormalToFace(casterPart, casterNormal)
	end

	return casterFace, hitFace
end

--- Get the world-space unit offset vector for a given NormalId on a part.
--- Useful for "place block on this face" logic.
function FaceUtil.GetFaceWorldNormal(part: BasePart, face: Enum.NormalId): Vector3
	local localVec = FACE_VECTORS[face]
	if not localVec then return Vector3.zero end
	return part.CFrame:VectorToWorldSpace(localVec).Unit
end

return FaceUtil
