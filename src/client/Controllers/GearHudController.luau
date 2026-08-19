--!strict
--[[
	GearHudController — the gear strip down the RIGHT of the screen.

	Seven tiles, one per ItemConfig slot, showing what is equipped and its
	Power, under a header that collapses the whole tray.

	Sides are split by role: equipment right, every numeric readout left (see
	UIController's TopLeft column). Numbers on both sides while gear occupies
	one of them reads as two competing HUDs.

	Its other job is to be the feedback channel during auto-roll. Rolls are
	demoted to a small top-of-screen ticker while auto is running, so this is
	what tells the player something actually improved. A slot flashes when its
	item changes, which is exactly that moment — EquipmentService.EquipIfBetter
	only ever swaps upward.

	NO NEW ART WAS UPLOADED FOR THIS.
	---------------------------------
	The icons are cut out of the gear panel image at runtime, sprite-sheet
	style, via ImageRectOffset/ImageRectSize. Every slot frame is already
	painted into that one asset, so pointing at sub-rectangles of it gives
	seven icons for zero extra assets and guarantees they match the panel.

	The rectangles below are in the pixel space of the UPLOADED asset, which is
	1024x593 — the 1596x924 source scaled by 1024/1596. They were derived from
	the same edge-detection pass that produced GearController's fractions, then
	multiplied by that scale. If the artwork is ever re-uploaded at a different
	size, these are wrong and must be rescaled by the new factor.

	Falls back to a text tile when AssetConfig.Images.GearPanel is 0, so this
	still works before any art exists.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Logger = require(Modules.Logger)
local ItemInstance = require(Modules.ItemInstance)
local AssetConfig = require(Config.AssetConfig)
local ItemConfig = require(Config.ItemConfig)
local RarityConfig = require(Config.RarityConfig)

local log = Logger.new("GearHudController")
local player = Players.LocalPlayer

local GearHudController = {}

--========================================================================
-- Sprite atlas
--========================================================================

--[[ { x, y, width, height } in the 1024x593 uploaded asset. ]]
type Sprite = { number }

local ATLAS_SIZE = Vector2.new(1024, 593)

--[[
	Top-to-bottom reading order: what you swing, then head down the body, then
	the two accessory slots. Deliberately not alphabetical — the column should
	read like a character, not a list.
]]
local SLOT_ORDER = { "Weapon", "Helmet", "Chest", "Legs", "Boots", "Accessory", "Gear" }

local SPRITES: { [string]: Sprite } = {
	Weapon = { 92, 382, 94, 148 },
	Helmet = { 223, 65, 81, 127 },
	Chest = { 215, 225, 99, 164 },
	Legs = { 342, 277, 74, 71 },
	Boots = { 222, 413, 84, 131 },
	Accessory = { 342, 82, 74, 71 },
	Gear = { 342, 382, 95, 148 },
}

local TILE = 76
local GAP = 4
local HEADER_HEIGHT = 22
local ICON_FILL = 0.94
local EMPTY_TRANSPARENCY = 0.66

local TRAY_HEIGHT = TILE * #SLOT_ORDER + GAP * (#SLOT_ORDER - 1)

--[[
	Reference viewport height the tile sizes were chosen against. The column is
	scaled down below this so seven tiles plus a header still fit on a short
	landscape phone screen instead of running off the top and bottom.
]]
local REFERENCE_HEIGHT = 900
local MIN_SCALE = 0.62

--========================================================================
-- State
--========================================================================

local client: any = nil
local screenGui: ScreenGui? = nil
local tray: Frame? = nil
local chevron: TextLabel? = nil
local tiles: { [string]: Frame } = {}
local lastEquipped: { [string]: string } = {}
local collapsed = false
local started = false

--========================================================================
-- Helpers
--========================================================================

local function equippedIn(slot: string): any?
	local profile = client and client.Profile
	if not profile or not profile.Equipment or not profile.Inventory then
		return nil
	end

	local id = profile.Equipment[slot]
	if not id or id == "" then
		return nil
	end

	return profile.Inventory.Items[id]
end

local function rarityColor(instance: any?): Color3
	if not instance then
		return Theme.Color.TextDim
	end
	local rarity = RarityConfig.Definitions[instance.Rarity]
	return if rarity then rarity.Color else Theme.Color.Text
end

--[[
	Every icon gets the same AREA, not the same bounding box.

	Fitting each sprite to the tile meant the largest dimension always hit the
	edge — so a square frame (the belt, the rings) filled the full width while
	a tall narrow one (the greatsword) used barely half of it. The belt ended
	up with about 50% more pixels than the sword and read as the bigger item,
	which is nonsense.

	Equal area makes them look the same size whatever their shape. Aspect is
	still preserved, so nothing is squashed.

	ICON_AREA is the largest area that keeps even the most extreme aspect in
	the set inside the tile — derived from the sprites rather than hardcoded,
	so re-cutting the artwork cannot silently push an icon out of its cell.
]]
local ICON_AREA = (function(): number
	local tightest = 1

	for _, sprite in pairs(SPRITES) do
		local aspect = sprite[3] / sprite[4]
		tightest = math.min(tightest, math.min(aspect, 1 / aspect))
	end

	local box = TILE * ICON_FILL
	return box * box * tightest
end)()

local function iconSize(sprite: Sprite): UDim2
	local aspect = sprite[3] / sprite[4]
	local height = math.sqrt(ICON_AREA / aspect)

	return UDim2.fromOffset(math.round(aspect * height), math.round(height))
end

--========================================================================
-- Construction
--========================================================================

local function buildTile(slot: string, order: number, parent: Instance): Frame
	local sprite = SPRITES[slot]
	local image = AssetConfig.GetImage("GearPanel")

	--[[
		No panel, no corner, no stroke — just the painted icon on the world.

		The artwork already draws its own ornate frame, so wrapping it in one of
		ours was a box inside a box. Rarity now reads from the Power number
		underneath instead of from a border, and the change flash is a scale pop
		on the icon rather than a stroke that no longer exists.
	]]
	local tile = Create.new("Frame", {
		Name = slot,
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, {
		Create.new("UIScale", { Name = "Pop", Scale = 1 }),
	}) :: Frame

	if image then
		Create.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = iconSize(sprite),
			BackgroundTransparency = 1,
			Image = image,
			-- The sprite-sheet cut: show only this slot's painted frame.
			ImageRectOffset = Vector2.new(sprite[1], sprite[2]),
			ImageRectSize = Vector2.new(sprite[3], sprite[4]),
			ImageTransparency = EMPTY_TRANSPARENCY,
			Parent = tile,
		})
	else
		-- No artwork configured: name the slot so the strip is still usable.
		Create.new("TextLabel", {
			Name = "Icon",
			Size = UDim2.fromScale(1, 0.7),
			BackgroundTransparency = 1,
			Font = Theme.Font.Medium,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.TextDim,
			Text = string.sub(slot, 1, 4),
			Parent = tile,
		})
	end

	--[[
		Power sits over the bottom of the icon with a heavy stroke rather than
		below it in its own strip — without a panel behind it, plain text on
		the game world is unreadable against light ground.
	]]
	Create.new("TextLabel", {
		Name = "Power",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 15),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		Text = "",
		Parent = tile,
	}, {
		Create.new("UIStroke", {
			Color = Theme.Color.Backdrop,
			Thickness = 2,
			Transparency = 0.15,
		}),
	})

	return tile
end

--[[
	Collapses or expands the tray.

	Animates height rather than toggling Visible so the column does not pop,
	and the tray clips its children so tiles slide away behind the header
	instead of vanishing mid-tween.
]]
function GearHudController.SetCollapsed(value: boolean)
	collapsed = value

	local frame = tray
	if frame then
		TweenService:Create(frame, Theme.Tween.Normal, {
			Size = UDim2.fromOffset(TILE, if value then 0 else TRAY_HEIGHT),
		}):Play()
	end

	if chevron then
		chevron.Text = if value then "\u{25B8}" else "\u{25BE}"
	end
end

function GearHudController.IsCollapsed(): boolean
	return collapsed
end

local function build(): ScreenGui
	local gui = Create.new("ScreenGui", {
		Name = "GearHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 3,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	--[[
		Very top right, hard against the HUD margin. Equipment owns this corner;
		every numeric readout lives in the left column in UIController.

		Anchored top-right rather than centre-right so it starts at the corner
		and grows downward — with the boxes gone the column has no outline to
		centre, and hanging it from the corner is what makes it read as chrome
		rather than as something floating in the middle of the screen.
	]]
	local column = Create.new("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Layout.HUDMargin, 0, Theme.Layout.HUDMargin),
		Size = UDim2.fromOffset(TILE, HEADER_HEIGHT + GAP + TRAY_HEIGHT),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Create.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, GAP),
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		-- Shrinks the whole column on short screens rather than letting seven
		-- tiles run off the top and bottom.
		Create.new("UIScale", { Name = "Fit", Scale = 1 }),
	}) :: Frame

	-- Boxless like the tiles: the chevron carries a stroke so it stays legible
	-- against the world without a panel behind it.
	local header = Create.new("TextButton", {
		Name = "Toggle",
		Size = UDim2.fromOffset(TILE, HEADER_HEIGHT),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 0,
		Parent = column,
	}) :: TextButton

	chevron = Create.new("TextLabel", {
		Name = "Chevron",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		Text = "\u{25BE}",
		Parent = header,
	}, {
		Create.new("UIStroke", {
			Color = Theme.Color.Backdrop,
			Thickness = 2,
			Transparency = 0.2,
		}),
	}) :: TextLabel

	header.Activated:Connect(function()
		GearHudController.SetCollapsed(not collapsed)
	end)

	local frame = Create.new("Frame", {
		Name = "Tray",
		Size = UDim2.fromOffset(TILE, TRAY_HEIGHT),
		BackgroundTransparency = 1,
		-- So collapsing slides the tiles away instead of leaving them poking
		-- out of a zero-height frame.
		ClipsDescendants = true,
		LayoutOrder = 1,
		Parent = column,
	}, {
		Create.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	tray = frame

	for order, slot in ipairs(SLOT_ORDER) do
		tiles[slot] = buildTile(slot, order, frame)
	end

	--[[
		Keep the column inside the viewport on short screens. Recomputed on
		resize because Studio's device emulator and a real rotation both change
		this without reloading the GUI.
	]]
	local fit = column:FindFirstChild("Fit") :: UIScale?
	local camera = workspace.CurrentCamera

	local function refit()
		if not fit or not camera then
			return
		end
		local available = camera.ViewportSize.Y
		fit.Scale = math.clamp(available / REFERENCE_HEIGHT, MIN_SCALE, 1)
	end

	refit()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	end

	return gui
end

--========================================================================
-- Rendering
--========================================================================

--[[
	Brief pulse on a slot that just changed.

	Only ever fired from a real change in equipped instance id, so during
	auto-roll this is a discrete "that one was an upgrade" rather than a
	constant strobe.
]]
local function flash(tile: Frame)
	local pop = tile:FindFirstChild("Pop") :: UIScale?
	if not pop then
		return
	end

	-- Scale punch rather than a border glow: there is no border any more, and
	-- a bare icon jumping in place is legible from the corner of the eye.
	pop.Scale = 1.35
	TweenService:Create(pop, Theme.Tween.Pop, { Scale = 1 }):Play()
end

function GearHudController.Render()
	for _, slot in ipairs(SLOT_ORDER) do
		local tile = tiles[slot]
		if not tile then
			continue
		end

		local instance = equippedIn(slot)
		local icon = tile:FindFirstChild("Icon")
		local power = tile:FindFirstChild("Power") :: TextLabel?

		local color = rarityColor(instance)

		if icon and icon:IsA("ImageLabel") then
			icon.ImageTransparency = if instance then 0 else EMPTY_TRANSPARENCY
		elseif icon and icon:IsA("TextLabel") then
			icon.TextColor3 = color
		end

		if power then
			power.Text = if instance then tostring(ItemInstance.GetPower(instance)) else ""
			power.TextColor3 = color
		end

		local currentId = if instance then instance.Id else ""

		if lastEquipped[slot] ~= nil and lastEquipped[slot] ~= currentId and instance then
			flash(tile)
		end

		lastEquipped[slot] = currentId
	end
end

--========================================================================
-- Start
--========================================================================

function GearHudController.Start(clientState: any)
	if started then
		return
	end
	started = true

	client = clientState

	-- A Rojo sync can re-run this while the old GUI is still parented.
	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("GearHud")
	if existing then
		existing:Destroy()
	end

	screenGui = build()
	GearHudController.Render()

	client.ProfileChanged:Connect(function()
		GearHudController.Render()
	end)

	if not AssetConfig.GetImage("GearPanel") then
		log:Warn("GearPanel image unset — gear strip is showing text tiles")
	end

	log:Info("ready (%d slots)", #SLOT_ORDER)
end

return GearHudController
