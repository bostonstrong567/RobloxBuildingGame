local HotbarUI = {}

local slots = {}
local selectedIndex: number? = nil
local spinAngle = 0

local function getSlotOrder(frame: Instance): number
	local numKey = frame:FindFirstChild("NumKey")
	if numKey and numKey:IsA("TextLabel") then
		local n = tonumber(numKey.Text)
		if n then return n == 0 and 10 or n end
	end
	return 99
end

local function cloneAsModel(template: Instance): Model?
	if template:IsA("Model") then
		return template:Clone()
	elseif template:IsA("BasePart") then
		local m = Instance.new("Model")
		m.Name = template.Name
		local p = template:Clone()
		p.Parent = m
		m.PrimaryPart = p
		return m
	end
	return nil
end

function HotbarUI.Init(playerGui: Instance)
	local hotbar = playerGui:WaitForChild("Main"):WaitForChild("HotBar")

	local frames = {}
	for _, desc in hotbar:GetDescendants() do
		if (desc:IsA("ImageLabel") or desc:IsA("Frame")) and desc:FindFirstChild("NumKey") then
			table.insert(frames, desc)
		end
	end
	table.sort(frames, function(a, b) return getSlotOrder(a) < getSlotOrder(b) end)

	for i, frame in frames do
		local vp = Instance.new("ViewportFrame")
		vp.Name = "Preview"
		vp.Size = UDim2.new(0.9, 0, 0.85, 0)
		vp.Position = UDim2.new(0.05, 0, 0.02, 0)
		vp.BackgroundTransparency = 1
		vp.Ambient = Color3.fromRGB(150, 150, 150)
		vp.LightColor = Color3.fromRGB(255, 255, 255)
		vp.LightDirection = Vector3.new(-1, -1, -1)
		vp.Parent = frame

		local wm = Instance.new("WorldModel")
		wm.Parent = vp

		local cam = Instance.new("Camera")
		cam.FieldOfView = 50
		cam.Parent = vp
		vp.CurrentCamera = cam

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(100, 180, 255)
		stroke.Thickness = 2
		stroke.Transparency = 1
		stroke.Enabled = false
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame

		slots[i] = {
			frame = frame,
			viewport = vp,
			worldModel = wm,
			vpCamera = cam,
			highlight = stroke,
			viewModel = nil,
			camDist = 3,
		}
	end
end

function HotbarUI.PopulateSlot(index: number, template: Instance)
	local slot = slots[index]
	if not slot then return end

	if slot.viewModel then
		slot.viewModel:Destroy()
		slot.viewModel = nil
	end

	local clone = cloneAsModel(template)
	if not clone then return end

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then clone.PrimaryPart = first end
	end

	local cf, size = clone:GetBoundingBox()
	clone.WorldPivot = cf
	clone:PivotTo(CFrame.identity)

	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	clone.Parent = slot.worldModel
	slot.viewModel = clone

	local maxDim = math.max(size.X, size.Y, size.Z)
	slot.camDist = maxDim * 2.2

	slot.vpCamera.CFrame = CFrame.new(
		Vector3.new(slot.camDist * 0.7, slot.camDist * 0.35, slot.camDist * 0.7),
		Vector3.zero
	)
end

function HotbarUI.SetSelected(index: number?)
	if selectedIndex and slots[selectedIndex] then
		slots[selectedIndex].highlight.Transparency = 1
		slots[selectedIndex].highlight.Enabled = false
	end
	selectedIndex = index
	if index and slots[index] then
		slots[index].highlight.Enabled = true
		slots[index].highlight.Transparency = 0
	end
end

function HotbarUI.SpinSelected(dt: number)
	if not selectedIndex then return end
	local slot = slots[selectedIndex]
	if not slot or not slot.viewModel then return end

	spinAngle += math.rad(40) * dt
	local d = slot.camDist
	slot.vpCamera.CFrame = CFrame.new(
		Vector3.new(math.cos(spinAngle) * d, d * 0.35, math.sin(spinAngle) * d),
		Vector3.zero
	)
end

function HotbarUI.ConnectClicks(callback: (number) -> ())
	for i, slot in slots do
		slot.frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				callback(i)
			end
		end)
	end
end

function HotbarUI.GetSlotCount(): number
	local n = 0
	for _ in slots do n += 1 end
	return n
end

return HotbarUI
