local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GridUtil = require(Modules:WaitForChild("GridUtil"))

local InventoryUI = {}

local gui = nil
local mainFrame = nil
local contentFrame = nil
local isOpen = false
local onItemSelected = nil
local categoryButtons = {}

local COLORS = {
	bg = Color3.fromRGB(30, 35, 50),
	header = Color3.fromRGB(45, 55, 80),
	category = Color3.fromRGB(55, 65, 95),
	categoryActive = Color3.fromRGB(80, 100, 150),
	item = Color3.fromRGB(50, 60, 85),
	itemHover = Color3.fromRGB(70, 85, 120),
	border = Color3.fromRGB(100, 130, 180),
	text = Color3.fromRGB(220, 230, 255),
	textDim = Color3.fromRGB(150, 160, 180),
}

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

local function createViewport(parent: Instance, template: Instance, size: UDim2)
	local vp = Instance.new("ViewportFrame")
	vp.Size = size
	vp.Position = UDim2.new(0.05, 0, 0.05, 0)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 150, 150)
	vp.LightColor = Color3.fromRGB(255, 255, 255)
	vp.LightDirection = Vector3.new(-1, -1, -1)
	vp.Parent = parent

	local wm = Instance.new("WorldModel")
	wm.Parent = vp

	local clone = cloneAsModel(template)
	if not clone then return end

	if not clone.PrimaryPart then
		local first = clone:FindFirstChildWhichIsA("BasePart", true)
		if first then clone.PrimaryPart = first end
	end

	local cf, bSize = clone:GetBoundingBox()
	clone.WorldPivot = cf
	clone:PivotTo(CFrame.identity)

	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	clone.Parent = wm

	local maxDim = math.max(bSize.X, bSize.Y, bSize.Z)
	local camDist = maxDim * 2.5

	local cam = Instance.new("Camera")
	cam.FieldOfView = 50
	cam.CFrame = CFrame.new(
		Vector3.new(camDist * 0.7, camDist * 0.35, camDist * 0.7),
		Vector3.zero
	)
	cam.Parent = vp
	vp.CurrentCamera = cam
end

local function createItemButton(parent: Instance, itemName: string, template: Instance)
	local btn = Instance.new("TextButton")
	btn.Name = itemName
	btn.Size = UDim2.new(0, 80, 0, 90)
	btn.BackgroundColor3 = COLORS.item
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = btn

	createViewport(btn, template, UDim2.new(0.9, 0, 0.65, 0))

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.25, 0)
	label.Position = UDim2.new(0, 0, 0.75, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = itemName
	label.Parent = btn

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 2)
	padding.PaddingRight = UDim.new(0, 2)
	padding.Parent = label

	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = COLORS.itemHover
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = COLORS.item
	end)
	btn.MouseButton1Click:Connect(function()
		if onItemSelected then
			onItemSelected(itemName)
		end
		InventoryUI.Close()
	end)
end

local function buildCategoryContent(categoryName: string, items: {{ name: string, template: Instance }})
	if contentFrame then
		for _, child in contentFrame:GetChildren() do
			if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
				child:Destroy()
			end
		end
	end

	for _, catBtn in categoryButtons do
		catBtn.BackgroundColor3 = COLORS.category
	end
	if categoryButtons[categoryName] then
		categoryButtons[categoryName].BackgroundColor3 = COLORS.categoryActive
	end

	for _, entry in items do
		createItemButton(contentFrame, entry.name, entry.template)
	end
end

local function organizeByCategory(): { [string]: {{ name: string, template: Instance }} }
	local placeables = ReplicatedStorage:FindFirstChild("Placeables")
	if not placeables then return {} end

	local categories = { All = {} }

	for _, child in placeables:GetChildren() do
		if child:IsA("Folder") then
			categories[child.Name] = {}
			for _, item in child:GetChildren() do
				if item:IsA("Model") or item:IsA("BasePart") then
					table.insert(categories[child.Name], { name = item.Name, template = item })
					table.insert(categories.All, { name = item.Name, template = item })
				end
			end
		elseif child:IsA("Model") or child:IsA("BasePart") then
			table.insert(categories.All, { name = child.Name, template = child })
		end
	end

	return categories
end

function InventoryUI.Init(playerGui: Instance, callback: (string) -> ())
	onItemSelected = callback

	gui = Instance.new("ScreenGui")
	gui.Name = "InventoryGui"
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = playerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "InventoryPanel"
	mainFrame.Size = UDim2.new(0, 500, 0, 400)
	mainFrame.Position = UDim2.new(0.5, -250, 0.5, -200)
	mainFrame.BackgroundColor3 = COLORS.bg
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = gui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 8)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = COLORS.border
	mainStroke.Thickness = 2
	mainStroke.Parent = mainFrame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 36)
	header.BackgroundColor3 = COLORS.header
	header.BorderSizePixel = 0
	header.Parent = mainFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 8)
	headerCorner.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = COLORS.text
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Inventory [E]"
	title.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 30, 0, 30)
	closeBtn.Position = UDim2.new(1, -33, 0, 3)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.BorderSizePixel = 0
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.Text = "X"
	closeBtn.Parent = header

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		InventoryUI.Close()
	end)

	local categoryBar = Instance.new("ScrollingFrame")
	categoryBar.Name = "CategoryBar"
	categoryBar.Size = UDim2.new(1, -16, 0, 32)
	categoryBar.Position = UDim2.new(0, 8, 0, 42)
	categoryBar.BackgroundTransparency = 1
	categoryBar.ScrollBarThickness = 0
	categoryBar.ScrollingDirection = Enum.ScrollingDirection.X
	categoryBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	categoryBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	categoryBar.BorderSizePixel = 0
	categoryBar.Parent = mainFrame

	local catLayout = Instance.new("UIListLayout")
	catLayout.FillDirection = Enum.FillDirection.Horizontal
	catLayout.Padding = UDim.new(0, 6)
	catLayout.SortOrder = Enum.SortOrder.LayoutOrder
	catLayout.Parent = categoryBar

	contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, -16, 1, -90)
	contentFrame.Position = UDim2.new(0, 8, 0, 80)
	contentFrame.BackgroundTransparency = 1
	contentFrame.ScrollBarThickness = 4
	contentFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.BorderSizePixel = 0
	contentFrame.Parent = mainFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 80, 0, 90)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.Name
	gridLayout.Parent = contentFrame

	local contentPad = Instance.new("UIPadding")
	contentPad.PaddingTop = UDim.new(0, 4)
	contentPad.Parent = contentFrame

	local categories = organizeByCategory()

	local sortOrder = 0
	categoryButtons = {}

	local sortedNames = {}
	for name in categories do
		table.insert(sortedNames, name)
	end
	table.sort(sortedNames, function(a, b)
		if a == "All" then return true end
		if b == "All" then return false end
		return a < b
	end)

	for _, catName in sortedNames do
		local items = categories[catName]
		if #items == 0 and catName ~= "All" then continue end

		local catBtn = Instance.new("TextButton")
		catBtn.Name = catName
		catBtn.Size = UDim2.new(0, 0, 1, 0)
		catBtn.AutomaticSize = Enum.AutomaticSize.X
		catBtn.BackgroundColor3 = COLORS.category
		catBtn.BorderSizePixel = 0
		catBtn.TextColor3 = COLORS.text
		catBtn.Font = Enum.Font.GothamMedium
		catBtn.TextSize = 12
		catBtn.Text = "  " .. catName .. "  "
		catBtn.LayoutOrder = sortOrder
		catBtn.Parent = categoryBar

		local catCorner = Instance.new("UICorner")
		catCorner.CornerRadius = UDim.new(0, 4)
		catCorner.Parent = catBtn

		categoryButtons[catName] = catBtn
		sortOrder += 1

		catBtn.MouseButton1Click:Connect(function()
			buildCategoryContent(catName, items)
		end)
	end

	if categories.All then
		buildCategoryContent("All", categories.All)
	end
end

function InventoryUI.Open()
	if gui then
		gui.Enabled = true
		isOpen = true
	end
end

function InventoryUI.Close()
	if gui then
		gui.Enabled = false
		isOpen = false
	end
end

function InventoryUI.Toggle()
	if isOpen then
		InventoryUI.Close()
	else
		InventoryUI.Open()
	end
end

function InventoryUI.IsOpen(): boolean
	return isOpen
end

return InventoryUI
