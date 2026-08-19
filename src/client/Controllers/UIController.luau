--!strict
--[[
	UIController — the persistent HUD.

	Phase 1 scope: the shell and its live bindings. Everything reads from the
	replicated profile view and updates when the server pushes a change. The
	roll button and nav panels are wired to real behaviour in later phases; the
	layout, responsiveness, and update path are real now so those phases only
	add handlers.

	Responsiveness is handled with a single UIScale driven by viewport width
	rather than per-element scale rules. One knob, predictable everywhere, and
	touch targets stay above the minimum because the base sizes already clear it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Logger = require(Modules.Logger)
local Progression = require(Modules.Progression)
local Signal = require(Modules.Signal)

local log = Logger.new("UIController")
local player = Players.LocalPlayer

local UIController = {}

--[[
	Fired when the player presses ROLL. UIController owns the button's look and
	state; RollController owns what pressing it means. Keeping those apart means
	the HUD has no idea the RNG service exists.
]]
UIController.RollActivated = Signal.new()

--[[ Fired with a panel name when a nav button is pressed. ]]
UIController.NavActivated = Signal.new()

local screenGui: ScreenGui? = nil
local scale: UIScale? = nil
local rollButton: Create.Button? = nil
local autoButton: Create.Button? = nil

-- Live references to the bits that change every profile push.
local bindings: { [string]: TextLabel } = {}
local xpFill: Frame? = nil

--========================================================================
-- Components
--========================================================================

--[[
	A stat pill: coloured dot, name, value. The value label is registered in
	`bindings` under `key` so updates are a table lookup rather than a search.
]]
local function StatPill(key: string, label: string, accent: Color3, order: number): Frame
	local value = Create.Label("0", {
		Name = "Value",
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		Size = UDim2.new(1, -58, 1, 0),
		Position = UDim2.fromOffset(50, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	bindings[key] = value

	return Create.Panel({
		Name = key,
		Size = UDim2.fromOffset(178, 34),
		BackgroundColor3 = Theme.Color.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = order,
	}, {
		Create.new("Frame", {
			Name = "Dot",
			Size = UDim2.fromOffset(8, 8),
			Position = UDim2.new(0, 12, 0.5, -4),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
		}, {
			Create.Corner(Theme.Radius.Pill),
		}),

		Create.Label(label, {
			Name = "Label",
			Font = Theme.Font.Medium,
			TextSize = Theme.TextSize.Small,
			TextColor3 = Theme.Color.TextMuted,
			Size = UDim2.new(0, 80, 1, 0),
			Position = UDim2.fromOffset(28, 0),
		}),

		value,
	})
end

--[[ Level pill with an XP fill bar across the bottom. ]]
local function LevelPill(order: number): Frame
	local value = Create.Label("Lv 1", {
		Name = "Value",
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local xpText = Create.Label("0 / 85", {
		Name = "XPText",
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local fill = Create.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
	}, {
		Create.Corner(Theme.Radius.Pill),
	}) :: Frame

	bindings.Level = value
	bindings.XPText = xpText
	xpFill = fill

	return Create.Panel({
		Name = "LevelPill",
		Size = UDim2.fromOffset(178, 48),
		BackgroundColor3 = Theme.Color.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = order,
	}, {
		value,
		xpText,
		Create.new("Frame", {
			Name = "XPTrack",
			Size = UDim2.new(1, -24, 0, 5),
			Position = UDim2.new(0, 12, 1, -11),
			BackgroundColor3 = Theme.Color.Backdrop,
			BorderSizePixel = 0,
		}, {
			Create.Corner(Theme.Radius.Pill),
			fill,
		}),
	})
end

local function NavButton(text: string, order: number): Create.Button
	return Create.Button(text, {
		Name = text,
		Size = UDim2.fromOffset(104, Theme.Layout.MinTouchPx),
		BackgroundColor3 = Theme.Color.PanelRaised,
		HoverColor = Theme.Color.PanelHover,
		PressColor = Theme.Color.Panel,
		TextSize = Theme.TextSize.Small,
		LayoutOrder = order,
	}, function()
		UIController.NavActivated:Fire(text)
	end)
end

--========================================================================
-- Layout
--========================================================================

local function build(): ScreenGui
	local gui = Create.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
	}) :: ScreenGui

	local root = Create.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}) :: Frame

	scale = Create.new("UIScale", { Scale = 1, Parent = root }) :: UIScale

	local margin = Theme.Layout.HUDMargin

	--[[
		Every readout lives in one left-hand column: currency, level, then the
		derived combat stats.

		Power and Luck used to sit top-right. They moved because the gear strip
		now owns the right edge, and numbers split across both sides while gear
		occupies one of them reads as two competing HUDs. Labels left,
		equipment right — each side has exactly one job.
	]]
	Create.new("Frame", {
		Name = "TopLeft",
		Size = UDim2.fromOffset(178, 240),
		Position = UDim2.fromOffset(margin, margin),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Create.ListLayout(Enum.FillDirection.Vertical, Theme.Spacing.S),
		StatPill("Coins", "Coins", Theme.Color.Coins, 1),
		LevelPill(2),
		StatPill("Power", "Power", Theme.Color.Power, 3),
		StatPill("Luck", "Luck", Theme.Color.Luck, 4),
	})

	-- The primary action. Deliberately the largest thing on screen.
	local roll = Create.Button("ROLL", {
		Name = "RollButton",
		Size = UDim2.fromOffset(240, 68),
		Position = UDim2.new(0.5, -120, 1, -68 - margin - 56),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Title,
		Parent = root,
	}, function()
		UIController.RollActivated:Fire()
	end)

	rollButton = roll

	Create.Stroke(Theme.Color.AccentHover, Theme.Stroke.Medium, 0.4).Parent = roll.Instance

	-- Auto-roll toggle, tucked beside the main button so it reads as secondary.
	local auto = Create.Button("AUTO", {
		Name = "AutoButton",
		Size = UDim2.fromOffset(84, 68),
		Position = UDim2.new(0.5, 128, 1, -68 - margin - 56),
		BackgroundColor3 = Theme.Color.PanelRaised,
		HoverColor = Theme.Color.PanelHover,
		PressColor = Theme.Color.Panel,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		Parent = root,
	}, function()
		UIController.NavActivated:Fire("__AutoToggle")
	end)

	autoButton = auto

	-- Bottom-right navigation.
	Create.new("Frame", {
		Name = "Nav",
		Size = UDim2.fromOffset(220, Theme.Layout.MinTouchPx * 2 + Theme.Spacing.S),
		Position = UDim2.new(1, -220 - margin, 1, -(Theme.Layout.MinTouchPx * 2 + Theme.Spacing.S) - margin),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Create.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(104, Theme.Layout.MinTouchPx),
			CellPadding = UDim2.fromOffset(Theme.Spacing.S, Theme.Spacing.S),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		NavButton("Inventory", 1).Instance,
		NavButton("Gear", 2).Instance,
		NavButton("Quests", 3).Instance,
		NavButton("Shop", 4).Instance,
	})

	return gui
end

--========================================================================
-- Binding
--========================================================================

--[[
	Pushes profile values into the HUD. Tolerant of a partial profile: this can
	fire before later phases have populated their sections.
]]
function UIController.Render(profile: any)
	if not profile or not screenGui then
		return
	end

	local coins = bindings.Coins
	if coins and profile.Currency then
		coins.Text = Progression.FormatNumber(profile.Currency.Coins or 0)
	end

	local levelLabel = bindings.Level
	local xpText = bindings.XPText

	if profile.Progression then
		local level = profile.Progression.Level or 1
		local xp = profile.Progression.XP or 0
		local required = Progression.XPForNextLevel(level)

		if levelLabel then
			levelLabel.Text = "Lv " .. tostring(level)
		end

		if xpText then
			xpText.Text = if required == math.huge
				then "MAX"
				else string.format("%s / %s", Progression.FormatNumber(xp), Progression.FormatNumber(required))
		end

		if xpFill then
			TweenService:Create(xpFill, Theme.Tween.Normal, {
				Size = UDim2.fromScale(Progression.GetProgress(level, xp), 1),
			}):Play()
		end
	end

	local luck = bindings.Luck
	if luck and profile.Luck then
		-- Base 1.0 plus permanent bonuses. Temporary boosts fold in at Phase 7.
		luck.Text = string.format("%.2fx", 1 + (profile.Luck.Permanent or 0))
	end

	local power = bindings.Power
	if power and profile.Stats then
		power.Text = Progression.FormatNumber(profile.Stats.HighestPower or 0)
	end
end

--[[ Single responsive knob: shrink the whole HUD on narrow viewports. ]]
local function updateScale()
	local gui = screenGui
	if not gui or not scale then
		return
	end

	local width = gui.AbsoluteSize.X
	if width <= 0 then
		return
	end

	scale.Scale = if width >= Theme.Layout.CompactBreakpointPx
		then 1
		else math.clamp(width / Theme.Layout.CompactBreakpointPx, 0.72, 1)
end

local started = false

function UIController.Start(client: any)
	if started then
		return
	end
	started = true

	local playerGui = player:WaitForChild("PlayerGui")

	-- Replace rather than duplicate: a Rojo sync during a live session can run
	-- this twice, and two HUDs stacked is a confusing bug to chase.
	local existing = playerGui:FindFirstChild("HUD")
	if existing then
		existing:Destroy()
	end

	local gui = build()
	gui.Parent = playerGui
	screenGui = gui

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	updateScale()

	if client then
		client.ProfileChanged:Connect(UIController.Render)
		if client.Profile then
			UIController.Render(client.Profile)
		end
	end

	log:Info("HUD ready")
end

--[[ Enables/disables the roll button — cooldown feedback. ]]
function UIController.SetRollEnabled(enabled: boolean)
	if rollButton then
		rollButton.SetEnabled(enabled)
	end
end

--[[ Recolours the AUTO button to show whether auto-roll is running. ]]
function UIController.SetAutoActive(active: boolean)
	if not autoButton then
		return
	end

	local button = autoButton.Instance
	button.BackgroundColor3 = if active then Theme.Color.Positive else Theme.Color.PanelRaised
	button.Text = if active then "STOP" else "AUTO"
end

--[[ The HUD's root frame, for controllers that need to parent into it. ]]
function UIController.GetRoot(): Frame?
	if not screenGui then
		return nil
	end
	return screenGui:FindFirstChild("Root") :: Frame?
end

return UIController
