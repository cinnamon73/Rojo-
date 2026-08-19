--!strict
--[[
	Theme — every colour, size, and timing the UI uses.

	One place to restyle the whole game. Nothing in a controller should contain
	a literal Color3 or UDim2 padding value; pull it from here so a visual pass
	is one file instead of twenty.

	Class colours are NOT duplicated here — they live in ClassConfig, because
	they are game data (a class's weapon tint), not chrome.
]]

local Theme = {}

--========================================================================
-- Palette
--========================================================================

Theme.Color = {
	-- Surfaces, darkest to lightest.
	Backdrop = Color3.fromRGB(16, 18, 26),
	Panel = Color3.fromRGB(26, 29, 40),
	PanelRaised = Color3.fromRGB(35, 39, 53),
	PanelHover = Color3.fromRGB(44, 49, 66),
	Divider = Color3.fromRGB(52, 58, 76),

	-- Text.
	Text = Color3.fromRGB(240, 243, 250),
	TextMuted = Color3.fromRGB(150, 158, 178),
	TextDim = Color3.fromRGB(104, 112, 132),

	-- Brand / action.
	Accent = Color3.fromRGB(96, 132, 255),
	AccentHover = Color3.fromRGB(124, 156, 255),
	AccentPressed = Color3.fromRGB(76, 108, 224),

	-- Semantic.
	Positive = Color3.fromRGB(78, 204, 128),
	Negative = Color3.fromRGB(236, 88, 96),
	Warning = Color3.fromRGB(244, 180, 62),

	-- Currency.
	Coins = Color3.fromRGB(255, 202, 84),
	Gems = Color3.fromRGB(126, 214, 255),
	Luck = Color3.fromRGB(140, 232, 158),
	Power = Color3.fromRGB(255, 138, 96),

	-- Overlays.
	Shadow = Color3.fromRGB(0, 0, 0),
	Scrim = Color3.fromRGB(0, 0, 0),
}

Theme.Transparency = {
	Scrim = 0.45,
	Shadow = 0.75,
	Disabled = 0.55,
}

--========================================================================
-- Typography
--========================================================================

Theme.Font = {
	Regular = Enum.Font.Gotham,
	Medium = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Display = Enum.Font.GothamBlack,
}

--[[ Text sizes in pixels at a 1080p reference height. ]]
Theme.TextSize = {
	Tiny = 12,
	Small = 14,
	Body = 16,
	Large = 20,
	Title = 28,
	Display = 44,
}

--========================================================================
-- Metrics
--========================================================================

Theme.Spacing = {
	XS = 4,
	S = 8,
	M = 12,
	L = 18,
	XL = 28,
}

Theme.Radius = {
	Small = UDim.new(0, 6),
	Medium = UDim.new(0, 10),
	Large = UDim.new(0, 16),
	Pill = UDim.new(1, 0),
}

Theme.Stroke = {
	Thin = 1,
	Medium = 2,
	Thick = 3,
}

--========================================================================
-- Motion
--========================================================================

Theme.Tween = {
	-- Hover / press feedback. Must feel instant.
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Panel open/close.
	Normal = TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	-- Emphasis: reveals, level ups.
	Slow = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	-- Overshoot for things that should feel celebratory.
	Pop = TweenInfo.new(0.30, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

--========================================================================
-- Layout
--========================================================================

Theme.Layout = {
	-- Minimum touch target. Anything interactive must be at least this on its
	-- smaller axis or it fails on phones.
	MinTouchPx = 44,

	-- Viewport width below which we switch to the compact arrangement.
	CompactBreakpointPx = 700,

	HUDMargin = 16,
	PanelMaxWidthPx = 880,
	PanelMaxHeightPx = 620,
}

--[[
	Scales a pixel value for small screens so the HUD does not swallow a phone.
	Clamped rather than linear — text below ~11px is unreadable regardless of
	how small the viewport gets.
]]
function Theme.ScaleForViewport(basePx: number, viewportWidth: number): number
	if viewportWidth >= Theme.Layout.CompactBreakpointPx then
		return basePx
	end

	local ratio = math.clamp(viewportWidth / Theme.Layout.CompactBreakpointPx, 0.72, 1)
	return math.max(11, math.floor(basePx * ratio + 0.5))
end

return Theme
