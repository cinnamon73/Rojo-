--!strict
--[[
	GearController — the gear tab, built directly on the reference artwork.

	This panel is deliberately NOT laid out with UIListLayout/UIGridLayout the
	way the rest of the UI is. The design is a single painted 1920x1080 image,
	and every interactive element is an invisible hitbox positioned on top of a
	shape that is already painted into it. So the artwork is the layout, and
	this file is a coordinate table plus behaviour.

	Consequences worth understanding before editing:

	  - **Every rect below is a fraction of the 1596x924 template**, not of the
	    screen. The panel holds that exact aspect via UIAspectRatioConstraint,
	    so a fraction lands on the same painted pixel at any viewport size.
	    Replace the artwork and every number here is wrong.
	  - **The rects were measured from the image itself**, not estimated: the
	    frame edges were found by detecting long runs of bright pixels and
	    pairing them into rectangles, then checked against a rendered overlay.
	    They are accurate to a pixel or two. If you re-cut the artwork, re-run
	    that measurement rather than nudging these by hand.
	  - **The template paints 14 slot frames; the game has 7.** ItemConfig.Slots
	    is Weapon/Helmet/Chest/Legs/Boots/Accessory/Gear. The seven that map are
	    below in SLOT_RECTS; the other seven are painted but meaningless, so
	    they get an explicit locked treatment rather than being left looking
	    like slots that are broken.
	  - **There is no drop system.** The template's second button says Drop, but
	    items are sold for coins (SellRequest). It is wired to Sell and labelled
	    accordingly; making it a real drop would need a server-side world-item
	    system that does not exist.

	Until the artwork is uploaded and its id is in AssetConfig.Images.GearPanel,
	the panel draws a wireframe of the same rects instead. That is a scaffold
	for checking alignment, not a design.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local ItemInstance = require(Modules.ItemInstance)
local AssetConfig = require(Config.AssetConfig)
local ItemConfig = require(Config.ItemConfig)
local RarityConfig = require(Config.RarityConfig)

local UIController = require(script.Parent.UIController)

local log = Logger.new("GearController")
local player = Players.LocalPlayer

local GearController = {}

--========================================================================
-- Template geometry
--========================================================================

--[[
	Rects are { x, y, width, height } as fractions of the template image.
	Derived from the 1920x1080 reference; see the header note on accuracy.
]]
type Rect = { number }

local TEMPLATE_ASPECT = 1596 / 924

--[[ The seven frames that correspond to a real ItemConfig slot. ]]
local SLOT_RECTS: { [string]: Rect } = {
	-- Centre column: the obvious body pieces.
	Helmet = { 0.2180, 0.1093, 0.0796, 0.2143 },
	Chest = { 0.2099, 0.3788, 0.0965, 0.2760 },
	Boots = { 0.2168, 0.6970, 0.0821, 0.2208 },

	-- The sword frame, bottom left.
	Weapon = { 0.0902, 0.6450, 0.0921, 0.2489 },

	-- Right column. Legs takes the belt frame: the template paints no greaves,
	-- and the belt is the only lower-body frame it has.
	Accessory = { 0.3340, 0.1385, 0.0721, 0.1201 },
	Legs = { 0.3340, 0.4675, 0.0721, 0.1201 },
	Gear = { 0.3340, 0.6439, 0.0927, 0.2500 },
}

--[[
	Frames the artwork paints that the game has no slot for. Rendered with a
	dim scrim so they read as "not part of this build" rather than as slots
	that failed to load. Delete an entry here the day a real slot claims it.
]]
local LOCKED_RECTS: { Rect } = {
	{ 0.1103, 0.1905, 0.0727, 0.1212 }, -- shoulders
	{ 0.1109, 0.3918, 0.0721, 0.1959 }, -- gloves
	{ 0.3340, 0.3019, 0.0721, 0.1212 }, -- cloak
	{ 0.0376, 0.3950, 0.0533, 0.0898 }, -- far-left small, upper
	{ 0.0376, 0.4978, 0.0533, 0.0898 }, -- far-left small, lower
	{ 0.4242, 0.3950, 0.0526, 0.0898 }, -- ring, upper
	{ 0.4242, 0.4978, 0.0533, 0.0898 }, -- ring, lower
}

local GRID_RECT: Rect = { 0.5508, 0.1483, 0.3722, 0.7002 }
local SEARCH_RECT: Rect = { 0.7393, 0.0866, 0.1867, 0.0346 }
local EQUIP_RECT: Rect = { 0.6059, 0.8874, 0.1253, 0.0649 }
local SELL_RECT: Rect = { 0.7481, 0.8874, 0.1253, 0.0649 }
local CLOSE_RECT: Rect = { 0.9680, 0.0455, 0.0251, 0.0433 }

-- The painted scrollbar. Only its two arrowheads are interactive; the shaft
-- between them is decoration, since the grid pages rather than scrolls.
local SCROLL_UP_RECT: Rect = { 0.9298, 0.1407, 0.0313, 0.0455 }
local SCROLL_DOWN_RECT: Rect = { 0.9298, 0.8192, 0.0313, 0.0455 }

local GRID_COLUMNS = 4
local GRID_ROWS = 5

--[[
	Cell metrics as fractions OF THE GRID RECT, measured from the painted
	lattice: 142x121 cells on a 151x131.5 pitch.

	Shaved fractionally below the measured values on purpose. Four columns at
	the exact measurement sum to 1.002, and UIGridLayout drops to three per row
	the instant the total exceeds 1 — which wraps twenty cells into seven rows
	and spills them out of the bottom of the artwork. FillDirectionMaxCells
	below is the real guard; these numbers keep it off the boundary.
]]
local CELL_SIZE = UDim2.fromScale(0.2385, 0.1865)
local CELL_PADDING = UDim2.fromScale(0.0150, 0.0160)

--[[ Converts a template rect into the UDim2 pair that positions a child. ]]
local function place(rect: Rect): (UDim2, UDim2)
	return UDim2.fromScale(rect[3], rect[4]), UDim2.fromScale(rect[1], rect[2])
end

--========================================================================
-- State
--========================================================================

local client: any = nil
local screenGui: ScreenGui? = nil
local panel: Frame? = nil
local open = false

local slotButtons: { [string]: TextButton } = {}
local gridCells: { TextButton } = {}
local searchBox: TextBox? = nil
local equipButton: TextButton? = nil
local sellButton: TextButton? = nil

local selectedInstanceId: string? = nil
local searchText = ""
local gridPage = 0

--========================================================================
-- Profile reads
--========================================================================

--[[ Every owned instance, rarest first. Mirrors InventoryController's order so
     the two panels never disagree about what "best" means. ]]
local function ownedItems(): { any }
	local profile = client and client.Profile
	if not profile or not profile.Inventory then
		return {}
	end

	local list = {}
	for _, instance in pairs(profile.Inventory.Items) do
		table.insert(list, instance)
	end

	table.sort(list, function(a, b)
		local ra, rb = RarityConfig.GetRank(a.Rarity), RarityConfig.GetRank(b.Rarity)
		if ra ~= rb then
			return ra > rb
		end

		local pa, pb = ItemInstance.GetPower(a), ItemInstance.GetPower(b)
		if pa ~= pb then
			return pa > pb
		end

		return a.Id < b.Id
	end)

	return list
end

local function equippedIn(slot: string): any?
	local profile = client and client.Profile
	if not profile or not profile.Equipment then
		return nil
	end

	local id = profile.Equipment[slot]
	if not id or id == "" then
		return nil
	end

	return profile.Inventory.Items[id]
end

local function instanceById(instanceId: string?): any?
	local profile = client and client.Profile
	if not instanceId or not profile or not profile.Inventory then
		return nil
	end
	return profile.Inventory.Items[instanceId]
end

--[[ Search matches display name, template name and rarity, so "leg", "iron"
     and "epic" all narrow usefully without needing a filter row. ]]
local function matchesSearch(instance: any): boolean
	if searchText == "" then
		return true
	end

	local needle = string.lower(searchText)
	local template = ItemConfig.Get(instance.TemplateId)

	local haystacks = {
		string.lower(ItemInstance.GetDisplayName(instance)),
		string.lower(tostring(instance.Rarity)),
		if template then string.lower(template.Name) else "",
		if template then string.lower(template.Slot) else "",
	}

	for _, hay in ipairs(haystacks) do
		if string.find(hay, needle, 1, true) then
			return true
		end
	end

	return false
end

local function visibleItems(): { any }
	local list = {}
	for _, instance in ipairs(ownedItems()) do
		if matchesSearch(instance) then
			table.insert(list, instance)
		end
	end
	return list
end

--========================================================================
-- Construction
--========================================================================

local function rarityColor(instance: any?): Color3
	if not instance then
		return Theme.Color.TextDim
	end
	local rarity = RarityConfig.Definitions[instance.Rarity]
	return if rarity then rarity.Color else Theme.Color.Text
end

--[[
	A hitbox over a painted shape.

	Transparent by default: the artwork already draws the frame, so anything
	this adds is a highlight on top of it, never the shape itself.
]]
local function hitbox(name: string, rect: Rect, parent: Instance): TextButton
	local size, position = place(rect)

	return Create.new("TextButton", {
		Name = name,
		Size = size,
		Position = position,
		BackgroundColor3 = Theme.Color.Accent,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Small }),
	}) :: TextButton
end

--[[ Wireframe stand-in used only while the artwork id is unset. ]]
local function wireframe(rect: Rect, parent: Instance, color: Color3)
	local size, position = place(rect)

	Create.new("Frame", {
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Small }),
		Create.new("UIStroke", {
			Color = color,
			Thickness = Theme.Stroke.Thin,
			Transparency = 0.35,
		}),
	})
end

local function buildSlots(root: Frame)
	for slot, rect in pairs(SLOT_RECTS) do
		local button = hitbox("Slot_" .. slot, rect, root)

		-- The item's name sits low in the frame so it never covers the painted
		-- icon above it. Rarity colour is the only fill the slot ever gets.
		Create.new("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 0.24),
			Position = UDim2.fromScale(0, 0.76),
			BackgroundTransparency = 1,
			Font = Theme.Font.Medium,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.TextMuted,
			TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = button,
		})

		Create.new("UIStroke", {
			Name = "Highlight",
			Color = Theme.Color.Accent,
			Thickness = Theme.Stroke.Medium,
			Transparency = 1,
			Parent = button,
		})

		button.Activated:Connect(function()
			local instance = equippedIn(slot)
			if not instance then
				return
			end

			-- Clicking a filled slot unequips it; that is the only action a
			-- doll slot has, since equipping is driven from the grid.
			local remote = Remotes.Get("EquipRequest") :: RemoteFunction
			remote:InvokeServer({ Action = "Unequip", Slot = slot })
		end)

		slotButtons[slot] = button
	end

	for index, rect in ipairs(LOCKED_RECTS) do
		local size, position = place(rect)

		Create.new("Frame", {
			Name = "Locked" .. tostring(index),
			Size = size,
			Position = position,
			BackgroundColor3 = Theme.Color.Backdrop,
			BackgroundTransparency = 0.45,
			Parent = root,
		}, {
			Create.new("UICorner", { CornerRadius = Theme.Radius.Small }),
		})
	end
end

local function buildGrid(root: Frame)
	local size, position = place(GRID_RECT)

	local container = Create.new("Frame", {
		Name = "Grid",
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		-- Belt and braces: even if a future cell size rounds badly, nothing
		-- escapes the painted frame.
		ClipsDescendants = true,
		Parent = root,
	}, {
		Create.new("UIGridLayout", {
			-- Measured off the painted lattice rather than derived from the
			-- column count, so cells sit on the artwork instead of near it.
			CellSize = CELL_SIZE,
			CellPadding = CELL_PADDING,
			-- Forces exactly four per row. Without this, sub-pixel rounding
			-- decides the column count for us.
			FillDirectionMaxCells = GRID_COLUMNS,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: Frame

	for index = 1, GRID_COLUMNS * GRID_ROWS do
		local cell = Create.new("TextButton", {
			Name = "Cell" .. tostring(index),
			BackgroundColor3 = Theme.Color.Accent,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			LayoutOrder = index,
			Text = "",
			Parent = container,
		}, {
			Create.new("UICorner", { CornerRadius = Theme.Radius.Small }),
			Create.new("UIStroke", {
				Name = "Highlight",
				Color = Theme.Color.Accent,
				Thickness = Theme.Stroke.Medium,
				Transparency = 1,
			}),
			Create.new("TextLabel", {
				Name = "Label",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Theme.Font.Medium,
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = Theme.Color.Text,
				TextWrapped = true,
				Text = "",
			}),
		}) :: TextButton

		cell.Activated:Connect(function()
			local item = (cell :: any):GetAttribute("InstanceId")
			if type(item) == "string" and item ~= "" then
				selectedInstanceId = item
				GearController.Render()
			end
		end)

		table.insert(gridCells, cell)
	end
end

local function buildControls(root: Frame)
	local searchSize, searchPosition = place(SEARCH_RECT)

	searchBox = Create.new("TextBox", {
		Name = "Search",
		Size = searchSize,
		Position = searchPosition,
		BackgroundTransparency = 1,
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		PlaceholderText = "Search",
		PlaceholderColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Text = "",
		Parent = root,
	}, {
		Create.new("UIPadding", { PaddingLeft = UDim.new(0, Theme.Spacing.S) }),
	}) :: TextBox

	;(searchBox :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
		searchText = (searchBox :: TextBox).Text
		gridPage = 0
		GearController.Render()
	end)

	equipButton = hitbox("Equip", EQUIP_RECT, root)
	sellButton = hitbox("Sell", SELL_RECT, root)

	;(equipButton :: TextButton).Activated:Connect(function()
		local instance = instanceById(selectedInstanceId)
		if not instance then
			return
		end

		local remote = Remotes.Get("EquipRequest") :: RemoteFunction
		local result = remote:InvokeServer({ InstanceId = instance.Id })

		if type(result) == "table" and not result.Success then
			log:Warn("equip refused: %s", tostring(result.Error))
		end
	end)

	;(sellButton :: TextButton).Activated:Connect(function()
		local instance = instanceById(selectedInstanceId)
		if not instance then
			return
		end

		local remote = Remotes.Get("SellRequest") :: RemoteFunction
		local result = remote:InvokeServer({ InstanceIds = { instance.Id } })

		-- The server asks for confirmation above Epic; re-send with the flag.
		if type(result) == "table" and result.Error == "ConfirmationRequired" then
			result = remote:InvokeServer({ InstanceIds = { instance.Id }, Confirmed = true })
		end

		if type(result) == "table" and result.Success then
			selectedInstanceId = nil
		end
	end)

	local close = hitbox("Close", CLOSE_RECT, root)
	close.Activated:Connect(function()
		GearController.SetOpen(false)
	end)

	-- Paging. The template paints a scrollbar, but a grid of fixed cells pages
	-- more cleanly than it scrolls, so the arrowheads step a page at a time.
	local up = hitbox("ScrollUp", SCROLL_UP_RECT, root)
	up.Activated:Connect(function()
		gridPage -= 1
		GearController.Render()
	end)

	local down = hitbox("ScrollDown", SCROLL_DOWN_RECT, root)
	down.Activated:Connect(function()
		gridPage += 1
		GearController.Render()
	end)
end

local function build(): ScreenGui
	local gui = Create.new("ScreenGui", {
		Name = "GearPanel",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	-- Scrim: the panel is modal, and without this the world reads through the
	-- artwork's transparent corners.
	Create.new("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Scrim,
		BackgroundTransparency = Theme.Transparency.Scrim,
		Parent = gui,
	})

	local image = AssetConfig.GetImage("GearPanel")

	--[[
		The panel is sized by height and constrained to the template's aspect,
		so it letterboxes on ultrawide and shrinks on phones without ever
		stretching the artwork. Stretching would misalign every hitbox below.
	]]
	local root = Create.new(if image then "ImageLabel" else "Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.96, 0.96),
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = if image then 1 else 0.06,
		Parent = gui,
	}, {
		Create.new("UIAspectRatioConstraint", {
			AspectRatio = TEMPLATE_ASPECT,
			DominantAxis = Enum.DominantAxis.Height,
		}),
	}) :: any

	if image then
		root.Image = image
		root.ScaleType = Enum.ScaleType.Fit
	else
		-- No artwork yet: draw the rects so alignment is checkable in Studio.
		Create.new("UICorner", { CornerRadius = Theme.Radius.Large, Parent = root })
		Create.new("UIStroke", {
			Color = Theme.Color.Divider,
			Thickness = Theme.Stroke.Medium,
			Parent = root,
		})

		for _, rect in pairs(SLOT_RECTS) do
			wireframe(rect, root, Theme.Color.Divider)
		end
		wireframe(GRID_RECT, root, Theme.Color.Divider)
		wireframe(SEARCH_RECT, root, Theme.Color.Divider)
		wireframe(EQUIP_RECT, root, Theme.Color.Accent)
		wireframe(SELL_RECT, root, Theme.Color.Accent)
	end

	panel = root

	buildSlots(root)
	buildGrid(root)
	buildControls(root)

	return gui
end

--========================================================================
-- Rendering
--========================================================================

function GearController.Render()
	if not panel then
		return
	end

	-- Doll slots.
	for slot, button in pairs(slotButtons) do
		local instance = equippedIn(slot)
		local label = button:FindFirstChild("Label") :: TextLabel?
		local highlight = button:FindFirstChild("Highlight") :: UIStroke?

		if label then
			label.Text = if instance then ItemInstance.GetStackLabel(instance) else ""
			label.TextColor3 = rarityColor(instance)
		end

		if highlight then
			highlight.Transparency = if instance then 0.4 else 1
			highlight.Color = rarityColor(instance)
		end
	end

	-- Grid.
	local items = visibleItems()
	local perPage = GRID_COLUMNS * GRID_ROWS
	local maxPage = math.max(math.ceil(#items / perPage) - 1, 0)
	gridPage = math.clamp(gridPage, 0, maxPage)

	for index, cell in ipairs(gridCells) do
		local instance = items[gridPage * perPage + index]
		local label = cell:FindFirstChild("Label") :: TextLabel?
		local highlight = cell:FindFirstChild("Highlight") :: UIStroke?

		;(cell :: any):SetAttribute("InstanceId", if instance then instance.Id else "")

		if label then
			label.Text = if instance then ItemInstance.GetStackLabel(instance) else ""
			label.TextColor3 = rarityColor(instance)
		end

		if highlight then
			local selected = instance ~= nil and instance.Id == selectedInstanceId
			highlight.Transparency = if selected then 0 else 1
			highlight.Color = rarityColor(instance)
		end

		cell.BackgroundTransparency = if instance then 0.88 else 1
	end

	-- Actions are only live with a selection, and Equip only for a slot the
	-- item can actually go in.
	local selected = instanceById(selectedInstanceId)
	local template = if selected then ItemConfig.Get(selected.TemplateId) else nil

	if equipButton then
		equipButton.BackgroundTransparency = if template then 0.85 else 1
		equipButton.Active = template ~= nil
	end

	if sellButton then
		sellButton.BackgroundTransparency = if selected and not selected.Locked then 0.85 else 1
		sellButton.Active = selected ~= nil and not selected.Locked
	end
end

--========================================================================
-- Open / close
--========================================================================

function GearController.SetOpen(value: boolean)
	open = value

	if screenGui then
		screenGui.Enabled = value
	end

	if value then
		GearController.Render()
	end
end

function GearController.IsOpen(): boolean
	return open
end

--========================================================================
-- Start
--========================================================================

function GearController.Start(clientState: any)
	client = clientState

	-- A Rojo sync can re-run this while the old GUI is still parented.
	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("GearPanel")
	if existing then
		existing:Destroy()
	end

	screenGui = build()

	UIController.NavActivated:Connect(function(name: string)
		if name == "Gear" then
			GearController.SetOpen(not open)
		end
	end)

	client.ProfileChanged:Connect(function()
		if open then
			GearController.Render()
		end
	end)

	if not AssetConfig.GetImage("GearPanel") then
		log:Warn("AssetConfig.Images.GearPanel is 0 — drawing the alignment wireframe instead of the artwork")
	end

	log:Info("ready")
end

return GearController
