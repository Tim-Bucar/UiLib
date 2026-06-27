--!strict
--[[
	UILib  -  a tiny Instance.new UI library for mod-menu style windows.

	PLACEMENT
		ModuleScript  -> ReplicatedStorage (name it "UILib")
		LocalScript   -> StarterPlayer > StarterPlayerScripts (requires the module)

	QUICK API
		local Lib = require(game.ReplicatedStorage.UILib)

		local Window = Lib:CreateWindow({ Name = "MyMenu", Accent = Color3.fromRGB(100,170,255) })
		Window:AddTitle("<b>My</b> Powerplant")           -- RichText + Fredoka One on the top bar

		local Tab = Window:AddTab("rbxassetid://...", "Main")   -- icon on the left, title on the right

		local t = Tab:AddToggle({ Title = "Godmode", Default = false, Callback = function(on) end })
		Tab:AddSlider({ Title = "Speed", Min = 0, Max = 100, Default = 16, Callback = function(v) end })
		Tab:AddTextBox({ Title = "Name", Default = "", Placeholder = "type...", Callback = function(s) end })

	NESTING (the "show stuff when something is enabled" part)
		Anything you add ON a toggle appears indented underneath it and is only
		visible while that toggle is ON:

		local main = Tab:AddToggle({ Title = "Auto Farm", Default = false })
		main:AddSlider({ Title = "Range", Min = 1, Max = 50, Default = 10 })
		main:AddToggle({ Title = "Notify on drop", Default = true })

	OBJECT METHODS
		Toggle  : SetValue(bool) / GetValue() / AddToggle / AddSlider / AddTextBox
		Slider  : SetValue(num)  / GetValue()
		TextBox : SetValue(str)  / GetValue()

	Every element returns its object so you can keep a reference and drive it from code.
]]

--========================================================================--
-- Services
--========================================================================--
local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")

--========================================================================--
-- Theme  (tweak everything in one place)
--========================================================================--
local Theme = {
	TopBar   = Color3.fromRGB(20, 20, 22),
	Sidebar  = Color3.fromRGB(26, 26, 28),
	Content  = Color3.fromRGB(40, 40, 43),
	Element  = Color3.fromRGB(52, 52, 56),
	Divider  = Color3.fromRGB(58, 58, 64),
	Accent   = Color3.fromRGB(100, 170, 255),
	Text     = Color3.fromRGB(235, 235, 240),
	SubText  = Color3.fromRGB(160, 160, 170),

	TitleFont = Enum.Font.FredokaOne, -- top bar / headers, as requested
	BodyFont  = Enum.Font.Gotham,     -- values / textboxes
}

--========================================================================--
-- Small helpers
--========================================================================--

-- Thin wrapper over Instance.new so element code stays readable.
-- Parent is applied LAST (cheaper, avoids extra reflows).
local function make(class: string, props: { [string]: any }): Instance
	local inst = Instance.new(class)
	local parent = props.Parent
	props.Parent = nil
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

local function corner(parent: Instance, radius: number)
	make("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function padding(parent: Instance, px: number)
	make("UIPadding", {
		PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

local function listLayout(parent: Instance, gap: number): UIListLayout
	return make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
		Parent = parent,
	}) :: UIListLayout
end

local function roundTo(value: number, increment: number): number
	if increment <= 0 then return value end
	return math.floor(value / increment + 0.5) * increment
end

local function fmt(v: number): string
	if v % 1 == 0 then
		return tostring(math.floor(v))
	end
	return string.format("%.2f", v)
end

--========================================================================--
-- Library root
--========================================================================--
local Library = {}
Library.__index = Library

local Window  = {}; Window.__index  = Window
local Tab     = {}; Tab.__index     = Tab

-- Forward declarations of the element creators so toggles can reuse them.
local createToggle, createSlider, createTextBox, createButton

--------------------------------------------------------------------------
-- Library:CreateWindow(config?)
--------------------------------------------------------------------------
function Library:CreateWindow(config)
	config = config or {}
	local self = setmetatable({}, Window)

	self.Accent = config.Accent or Theme.Accent
	self.Tabs   = {}            -- { button = TextButton, page = ScrollingFrame }
	self.Active = nil

	local playerGui = game:WaitForChild("CoreGui")

	-- ScreenGui ---------------------------------------------------------
	self.Gui = make("ScreenGui", {
		Name = config.Name or "UILib",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = playerGui,
	})

	-- Main window -------------------------------------------------------
	self.Main = make("Frame", {
		Name = "Window",
		Size = config.Size or UDim2.fromOffset(560, 360),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		ClipsDescendants = true,            -- so square inner frames respect the rounded corner
		Parent = self.Gui,
	})
	corner(self.Main, 8)
	make("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0),
		Transparency = 0.45,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = self.Main,
	})

	-- Top bar -----------------------------------------------------------
	self.TopBar = make("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = Theme.TopBar,
		BorderSizePixel = 0,
		Parent = self.Main,
	})
	self.TitleLabel = make("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -56, 1, 0),       -- leave room for the minimize button
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 18,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,                    -- RichText enabled, as requested
		Text = "Window",
		Parent = self.TopBar,
	})

	-- thin separation line under the top bar
	make("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.fromOffset(0, 38),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = self.TopBar,
	})

	-- Minimize button (top-right of the bar) - drawn line, no glyph
	self.MinButton = make("TextButton", {
		Name = "Minimize",
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -32, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 1,          -- only shows on hover
		AutoButtonColor = false,
		Text = "",
		Parent = self.TopBar,
	})
	corner(self.MinButton, 6)
	-- the little line that reads as "minimize"
	self.MinIcon = make("Frame", {
		Size = UDim2.fromOffset(12, 2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.SubText,
		BorderSizePixel = 0,
		Parent = self.MinButton,
	})
	corner(self.MinIcon, 1)
	-- hover feedback
	self.MinButton.MouseEnter:Connect(function()
		TweenService:Create(self.MinButton, TweenInfo.new(0.12), { BackgroundTransparency = 0 }):Play()
		self.MinIcon.BackgroundColor3 = Theme.Text
	end)
	self.MinButton.MouseLeave:Connect(function()
		TweenService:Create(self.MinButton, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		self.MinIcon.BackgroundColor3 = Theme.SubText
	end)

	-- Sidebar -----------------------------------------------------------
	self.Sidebar = make("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 140, 1, -38),
		Position = UDim2.fromOffset(0, 38),
		BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0,
		Parent = self.Main,
	})
	local tabHolder = make("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = self.Sidebar,
	})
	padding(tabHolder, 8)
	listLayout(tabHolder, 6)
	self.TabHolder = tabHolder

	-- subtle divider between sidebar and content (the faint line in your image)
	self.Divider = make("Frame", {
		Size = UDim2.new(0, 1, 1, -38),
		Position = UDim2.fromOffset(140, 38),
		BackgroundColor3 = Theme.Divider,
		BorderSizePixel = 0,
		Parent = self.Main,
	})

	-- Content holder (pages get parented here) --------------------------
	self.Content = make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -141, 1, -38),
		Position = UDim2.fromOffset(141, 38),
		BackgroundTransparency = 1,
		Parent = self.Main,
	})

	-- Dragging by the top bar ------------------------------------------
	do
		local dragging, dragStart, startPos
		self.TopBar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos  = self.Main.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				self.Main.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	-- Resize grip (bottom-right corner) - drawn lines, no glyph
	self.MinSize = config.MinSize or Vector2.new(360, 240)
	self.ResizeGrip = make("TextButton", {
		Name = "ResizeGrip",
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(1, -18, 1, -18),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
		Parent = self.Main,
	})
	-- two short diagonal lines in the corner
	for i, len in ipairs({ 7, 12 }) do
		make("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -3, 1, -3),
			Size = UDim2.fromOffset(len, 1.5),
			Rotation = -45,
			BackgroundColor3 = Theme.SubText,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = self.ResizeGrip,
		})
	end
	do
		local resizing, startInput, startSize
		self.ResizeGrip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				startInput = input.Position
				startSize  = self.Main.AbsoluteSize
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if resizing and not self.Minimized and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - startInput
				local w = math.max(self.MinSize.X, startSize.X + delta.X)
				local h = math.max(self.MinSize.Y, startSize.Y + delta.Y)
				self.Main.Size = UDim2.fromOffset(w, h)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				resizing = false
			end
		end)
	end

	-- Minimize / restore -----------------------------------------------
	self.Minimized = false
	self.MinButton.MouseButton1Click:Connect(function()
		self:SetMinimized(not self.Minimized)
	end)

	return self
end

--------------------------------------------------------------------------
-- Window:SetMinimized(bool)  -- collapse to just the top bar, or restore
--------------------------------------------------------------------------
function Window:SetMinimized(state: boolean)
	if state == self.Minimized then return end
	if self._animating then return end          -- ignore clicks mid-animation
	self.Minimized = state
	self._animating = true

	local dur  = 0.22
	local info = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if state then
		-- COLLAPSE -------------------------------------------------------
		self._fullSize = self.Main.Size          -- remember current (possibly resized) size
		self.ResizeGrip.Visible = false
		local collapsed = UDim2.new(self._fullSize.X.Scale, self._fullSize.X.Offset, 0, 38)
		TweenService:Create(self.Main, info, { Size = collapsed }):Play()
		task.delay(dur, function()
			-- hide the panels so nothing can poke out below the bar
			if self.Minimized then
				self.Sidebar.Visible = false
				self.Content.Visible = false
				self.Divider.Visible = false
			end
			self._animating = false
		end)
	else
		-- EXPAND ---------------------------------------------------------
		-- show panels first; ClipsDescendants keeps them hidden until the
		-- window grows past them, so they reveal smoothly as it expands
		self.Sidebar.Visible = true
		self.Content.Visible = true
		self.Divider.Visible = true
		TweenService:Create(self.Main, info, { Size = self._fullSize }):Play()
		task.delay(dur, function()
			if not self.Minimized then self.ResizeGrip.Visible = true end
			self._animating = false
		end)
	end
end

--------------------------------------------------------------------------
-- Window:AddTitle(text)   -- sets the top-bar title (RichText ok)
--------------------------------------------------------------------------
function Window:AddTitle(text: string)
	self.TitleLabel.Text = text
	return self
end

--------------------------------------------------------------------------
-- Window:AddTab(image, title)  -> Tab
--   icon on the left, title to the right of it
--------------------------------------------------------------------------
function Window:AddTab(image: string?, title: string)
	local tab = setmetatable({}, Tab)
	tab.Window = self

	-- Sidebar button
	local button = make("TextButton", {
		Name = title,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = Theme.Element,
		BackgroundTransparency = 1, -- highlighted only when active / hovered
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		Parent = self.TabHolder,
	})
	corner(button, 6)

	-- active accent bar on the left (kept out of the layout flow)
	local indicator = make("Frame", {
		Name = "Indicator",
		Size = UDim2.new(0, 3, 0.5, 0),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = self.Accent,
		BorderSizePixel = 0,
		Visible = false,
		Parent = button,
	})
	corner(indicator, 2)

	-- inner content frame holds the icon + title row
	local content = make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = button,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = content,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), Parent = content })

	make("ImageLabel", {
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Image = image or "",
		ImageColor3 = Theme.SubText,
		LayoutOrder = 1,
		Parent = content,
	})
	make("TextLabel", {
		Size = UDim2.new(1, -40, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 14,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = title,
		LayoutOrder = 2,
		Parent = content,
	})

	-- hover feedback (only when not the active tab)
	button.MouseEnter:Connect(function()
		if self.Active ~= tab then
			TweenService:Create(button, TweenInfo.new(0.12), { BackgroundTransparency = 0.88 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		if self.Active ~= tab then
			TweenService:Create(button, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		end
	end)

	-- Page (scrolling content for this tab)
	local page = make("ScrollingFrame", {
		Name = title,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Divider,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = self.Content,
	})
	padding(page, 10)
	listLayout(page, 8)

	tab.Button = button
	tab.Indicator = indicator
	tab.Page   = page
	table.insert(self.Tabs, tab)

	-- Selection logic
	button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	-- First tab auto-selected
	if not self.Active then
		self:SelectTab(tab)
	end

	return tab
end

function Window:SelectTab(tab)
	for _, t in ipairs(self.Tabs) do
		local on = (t == tab)
		t.Page.Visible = on
		t.Indicator.Visible = on
		TweenService:Create(t.Button, TweenInfo.new(0.12),
			{ BackgroundTransparency = on and 0 or 1 }):Play()
		local content = t.Button:FindFirstChild("Content")
		local label = content and content:FindFirstChildOfClass("TextLabel")
		if label then label.TextColor3 = on and Theme.Text or Theme.SubText end
		local icon = content and content:FindFirstChildOfClass("ImageLabel")
		if icon then icon.ImageColor3 = on and self.Accent or Theme.SubText end
	end
	self.Active = tab
end

--========================================================================--
-- ELEMENTS
-- Each creator takes (window, parent, config) and returns an object.
-- `parent` is a tab page OR a toggle's nested holder, so nesting just works.
--========================================================================--

-- Base "card" row. AutomaticSize.Y means it grows to fit wrapped text.
-- The `minHeight` you pass acts as the minimum (single-line) height.
-- `vpad` adds symmetric top/bottom padding so short content stays centered
-- and longer content gets breathing room.
local function makeRow(parent: Instance, minHeight: number, vpad: number?): Frame
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, minHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	corner(row, 6)
	if vpad then
		make("UIPadding", {
			PaddingTop = UDim.new(0, vpad), PaddingBottom = UDim.new(0, vpad),
			Parent = row,
		})
	end
	return row
end

-- Wrapping title + optional description, stacked on the left.
-- The row must use AutomaticSize.Y so it grows when the text wraps.
--   rightReserve = px kept clear on the right for the control
--   xOffset      = left inset (0 if the parent already has left padding)
local function makeHeader(parent: Instance, title: string, description: string?,
		rightReserve: number?, xOffset: number?): TextLabel
	rightReserve = rightReserve or 64
	xOffset = xOffset or 12

	local header = make("Frame", {
		Position = UDim2.new(0, xOffset, 0, 0),
		Size = UDim2.new(1, -(rightReserve + xOffset), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		Parent = header,
	})

	local titleLbl = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = title,
		LayoutOrder = 1,
		Parent = header,
	}) :: TextLabel

	if description ~= nil and description ~= "" then
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = Theme.BodyFont,
			TextSize = 11,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Text = description,
			LayoutOrder = 2,
			Parent = header,
		})
	end

	return titleLbl
end

--------------------------------------------------------------------------
-- TOGGLE
--------------------------------------------------------------------------
function createToggle(window, parent, config)
	config = config or {}
	local obj = {}
	local state = config.Default == true
	local callback = config.Callback

	-- Container holds the row + a nested holder (for child elements).
	-- AutomaticSize Y means it shrinks/grows as nested items show/hide.
	local container = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	listLayout(container, 6)

	local row = makeRow(container, 40, 11)
	makeHeader(row, config.Title or "Toggle", config.Description, 64)

	-- clickable overlay (expands past the row's vertical padding)
	local hit = make("TextButton", {
		Size = UDim2.new(1, 0, 1, 22),
		Position = UDim2.new(0, 0, 0, -11),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})

	-- pill switch
	local switch = make("Frame", {
		Size = UDim2.fromOffset(42, 22),
		Position = UDim2.new(1, -54, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Divider,
		BorderSizePixel = 0,
		Parent = row,
	})
	corner(switch, 11)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		Parent = switch,
	})
	corner(knob, 8)

	-- nested holder (children appear here, indented, only while ON)
	local nested = make("Frame", {
		Name = "Nested",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = state,
		Parent = container,
	})
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), Parent = nested })
	-- thin accent line so nested items read as "belonging" to the toggle
	make("Frame", {
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = window.Accent,
		BorderSizePixel = 0,
		Parent = nested,
	})
	local nestedList = make("Frame", {
		Size = UDim2.new(1, -10, 0, 0),
		Position = UDim2.fromOffset(10, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = nested,
	})
	listLayout(nestedList, 6)

	local function render(animated: boolean)
		local goalPos   = state and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3)
		local goalColor = state and window.Accent or Theme.Divider
		if animated then
			TweenService:Create(knob, TweenInfo.new(0.15), { Position = goalPos }):Play()
			TweenService:Create(switch, TweenInfo.new(0.15), { BackgroundColor3 = goalColor }):Play()
		else
			knob.Position = goalPos
			switch.BackgroundColor3 = goalColor
		end
		nested.Visible = state
	end
	render(false)

	hit.MouseButton1Click:Connect(function()
		state = not state
		render(true)
		if callback then callback(state) end
	end)

	-- public methods
	function obj:GetValue() return state end
	function obj:SetValue(v: boolean)
		state = v == true
		render(true)
		if callback then callback(state) end
	end
	obj.Instance = container

	-- nesting: add child elements that live under this toggle
	function obj:AddToggle(c)  return createToggle(window, nestedList, c) end
	function obj:AddSlider(c)  return createSlider(window, nestedList, c) end
	function obj:AddTextBox(c) return createTextBox(window, nestedList, c) end
	function obj:AddButton(c)  return createButton(window, nestedList, c) end

	return obj
end

--------------------------------------------------------------------------
-- SLIDER
--------------------------------------------------------------------------
function createSlider(window, parent, config)
	config = config or {}
	local obj = {}
	local min  = config.Min or 0
	local max  = config.Max or 100
	local inc  = config.Increment or 1
	local value = math.clamp(roundTo(config.Default or min, inc), min, max)
	local callback = config.Callback

	local row = makeRow(parent, 50)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		Parent = row,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		Parent = row,
	})

	-- top line: title/description on the left, value on the right
	local top = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = row,
	})
	makeHeader(top, config.Title or "Slider", config.Description, 90, 0)

	local valueLabel = make("TextLabel", {
		Size = UDim2.new(0, 80, 0, 18),
		Position = UDim2.new(1, 0, 0, 1),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = fmt(value),
		Parent = top,
	})

	-- bar (sits below the title line)
	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.Divider,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = row,
	})
	corner(bar, 3)
	local fill = make("Frame", {
		Size = UDim2.fromScale((value - min) / (max - min), 1),
		BackgroundColor3 = window.Accent,
		BorderSizePixel = 0,
		Parent = bar,
	})
	corner(fill, 3)
	local knob = make("Frame", {
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bar,
	})
	corner(knob, 7)

	local function setFromScale(scale: number, fire: boolean)
		scale = math.clamp(scale, 0, 1)
		value = math.clamp(roundTo(min + (max - min) * scale, inc), min, max)
		local realScale = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(realScale, 1)
		knob.Position = UDim2.new(realScale, 0, 0.5, 0)
		valueLabel.Text = fmt(value)
		if fire and callback then callback(value) end
	end

	-- drag handling
	local dragging = false
	local function update(input)
		local rel = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
		setFromScale(rel, true)
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			update(input)
		end
	end)
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	function obj:GetValue() return value end
	function obj:SetValue(v: number)
		setFromScale((math.clamp(v, min, max) - min) / (max - min), true)
	end
	obj.Instance = row
	return obj
end

--------------------------------------------------------------------------
-- TEXTBOX
--------------------------------------------------------------------------
function createTextBox(window, parent, config)
	config = config or {}
	local obj = {}
	local callback = config.Callback

	local row = makeRow(parent, 40, 11)
	makeHeader(row, config.Title or "Input", config.Description, 150)

	local box = make("TextBox", {
		Size = UDim2.new(0, 130, 0, 26),
		Position = UDim2.new(1, -142, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		Font = Theme.BodyFont,
		TextSize = 13,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		PlaceholderText = config.Placeholder or "...",
		Text = config.Default or "",
		ClearTextOnFocus = false,
		Parent = row,
	})
	corner(box, 5)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		Parent = box,
	})

	box.FocusLost:Connect(function(enterPressed)
		if callback then callback(box.Text, enterPressed) end
	end)

	function obj:GetValue() return box.Text end
	function obj:SetValue(s: string)
		box.Text = s
		if callback then callback(box.Text, false) end
	end
	obj.Instance = row
	return obj
end

--------------------------------------------------------------------------
-- BUTTON  -  a full-width clickable row that runs a callback
--------------------------------------------------------------------------
function createButton(window, parent, config)
	config = config or {}
	local obj = {}
	local callback = config.Callback

	-- the whole row is the button
	local row = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 40),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	corner(row, 6)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11), Parent = row,
	})

	local label = makeHeader(row, config.Title or "Button", config.Description, 28)

	-- small chevron-ish accent on the right so it reads as actionable
	make("Frame", {
		Size = UDim2.fromOffset(6, 6),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = window.Accent,
		BorderSizePixel = 0,
		Parent = row,
	})

	-- hover + press feedback
	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12),
			{ BackgroundColor3 = Color3.fromRGB(64, 64, 70) }):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12),
			{ BackgroundColor3 = Theme.Element }):Play()
	end)

	row.MouseButton1Click:Connect(function()
		-- quick press flash
		TweenService:Create(row, TweenInfo.new(0.08),
			{ BackgroundColor3 = window.Accent }):Play()
		task.delay(0.1, function()
			TweenService:Create(row, TweenInfo.new(0.15),
				{ BackgroundColor3 = Theme.Element }):Play()
		end)
		if callback then task.spawn(callback) end
	end)

	function obj:SetTitle(text: string) label.Text = text end
	obj.Instance = row
	return obj
end

--========================================================================--
-- Tab method wrappers (top-level elements live directly on the page)
--========================================================================--
function Tab:AddToggle(config)  return createToggle(self.Window, self.Page, config) end
function Tab:AddSlider(config)  return createSlider(self.Window, self.Page, config) end
function Tab:AddTextBox(config) return createTextBox(self.Window, self.Page, config) end
function Tab:AddButton(config)  return createButton(self.Window, self.Page, config) end

-- bonus: a small section header, handy for splitting a tab like a real mod menu
function Tab:AddSection(text: string)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = string.upper(text),
		Parent = self.Page,
	})
	return self
end

--========================================================================--
-- Library:CreateKeySystem(config)
--   A standalone key gate. Shows a centered card with an input + submit.
--   When config.Validate(key) returns true: plays a fade, destroys the
--   key UI, then calls config.OnSuccess().
--
--   config = {
--     Name        = "KeySystem",            -- ScreenGui name
--     Title       = "Key System",
--     Subtitle    = "Enter your key to continue",
--     Placeholder = "Paste key here...",
--     Accent      = Color3...,              -- optional, defaults to theme
--     Validate    = function(key) -> boolean  -- may yield (HttpService is fine)
--     OnSuccess   = function() end,         -- runs after the gate is destroyed
--     OnFail      = function(key) end,      -- optional
--     GetKeyText  = "Get Key",              -- optional button label
--     OnGetKey    = function() end,         -- optional, runs when "Get Key" clicked
--   }
--========================================================================--
function Library:CreateKeySystem(config)
	config = config or {}
	local accent = config.Accent or Theme.Accent
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = make("ScreenGui", {
		Name = config.Name or "KeySystem",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		Parent = playerGui,
	})

	-- dim the screen behind the card
	local dim = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Parent = gui,
	})

	-- card
	local card = make("Frame", {
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		Parent = gui,
	})
	corner(card, 10)
	make("UIStroke", {
		Color = Color3.fromRGB(0, 0, 0), Transparency = 0.45, Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	})
	padding(card, 18)
	local cardList = listLayout(card, 10)
	cardList.HorizontalAlignment = Enum.HorizontalAlignment.Center

	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = Theme.TitleFont,
		TextSize = 20,
		TextColor3 = Theme.Text,
		Text = config.Title or "Key System",
		LayoutOrder = 1,
		Parent = card,
	})
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = 13,
		TextColor3 = Theme.SubText,
		Text = config.Subtitle or "Enter your key to continue",
		LayoutOrder = 2,
		Parent = card,
	})

	-- key input
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		Font = Theme.BodyFont,
		TextSize = 14,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.SubText,
		PlaceholderText = config.Placeholder or "Paste key here...",
		Text = "",
		ClearTextOnFocus = false,
		LayoutOrder = 3,
		Parent = card,
	})
	corner(box, 6)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = box })

	-- status line (errors / checking)
	local status = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Font = Theme.BodyFont,
		TextSize = 12,
		TextColor3 = Theme.SubText,
		Text = "",
		LayoutOrder = 4,
		Parent = card,
	})

	-- submit button
	local submit = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.TitleFont,
		TextSize = 15,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "Submit",
		LayoutOrder = 5,
		Parent = card,
	})
	corner(submit, 6)

	-- optional "Get Key" button
	if config.OnGetKey then
		local getKey = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.BodyFont,
			TextSize = 13,
			TextColor3 = Theme.SubText,
			Text = config.GetKeyText or "Get Key",
			LayoutOrder = 6,
			Parent = card,
		})
		corner(getKey, 6)
		getKey.MouseButton1Click:Connect(function()
			pcall(config.OnGetKey)
		end)
	end

	-- public object
	local obj = {}
	obj.Gui = gui

	function obj:SetStatus(text: string, color: Color3?)
		status.Text = text
		status.TextColor3 = color or Theme.SubText
	end

	function obj:Destroy()
		gui:Destroy()
	end

	-- little horizontal shake on a wrong key
	local function shake()
		local base = card.Position
		for _, off in ipairs({ 8, -8, 5, -5, 0 }) do
			card.Position = base + UDim2.fromOffset(off, 0)
			task.wait(0.03)
		end
		card.Position = base
	end

	local busy = false
	local function attempt()
		if busy then return end
		local key = box.Text
		if key == "" then
			obj:SetStatus("Enter a key first.", Color3.fromRGB(235, 180, 90))
			return
		end
		busy = true
		submit.Text = "Checking..."
		submit.AutoButtonColor = false
		obj:SetStatus("", Theme.SubText)

		-- Validate may yield (e.g. HttpService); pcall handles errors/yields.
		local ok, result = pcall(function()
			return config.Validate and config.Validate(key) or false
		end)
		local valid = ok and result == true

		if valid then
			submit.Text = "Success"
			submit.BackgroundColor3 = Color3.fromRGB(80, 190, 120)
			-- fade everything out, then destroy and fire OnSuccess
			TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(card, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("GuiObject") then
					local goal = { BackgroundTransparency = 1 }
					if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
						goal.TextTransparency = 1
					end
					if d:IsA("ImageLabel") or d:IsA("ImageButton") then
						goal.ImageTransparency = 1
					end
					TweenService:Create(d, TweenInfo.new(0.25), goal):Play()
				end
			end
			task.delay(0.28, function()
				gui:Destroy()
				if config.OnSuccess then
					task.spawn(config.OnSuccess)
				end
			end)
		else
			busy = false
			submit.Text = "Submit"
			submit.AutoButtonColor = true
			obj:SetStatus("Invalid key. Try again.", Color3.fromRGB(235, 90, 90))
			if config.OnFail then task.spawn(config.OnFail, key) end
			task.spawn(shake)
		end
	end

	submit.MouseButton1Click:Connect(attempt)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then attempt() end
	end)

	return obj
end

return Library
