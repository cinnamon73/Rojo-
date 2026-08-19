--!strict
--[[
	InventoryController — the inventory and equipment panel.

	Reads entirely from the replicated profile view. Every mutation goes to the
	server and the panel only redraws when the server pushes back, so the UI can
	never show a state the server disagrees with. That costs one round trip per
	action and is worth it: optimistic updates in an inventory are how items
	appear to duplicate.

	Layout is grid on the left, detail and comparison on the right. The
	comparison is the part that earns its keep — "+15 Damage, -3 Defense"
	against what you already have is the single most useful thing an RPG
	inventory can tell you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Remotes = require(Modules.Remotes)
local Logger = require(Modules.Logger)
local ItemInstance = require(Modules.ItemInstance)
local Progression = require(Modules.Progression)
local ItemConfig = require(Config.ItemConfig)
local RarityConfig = require(Config.RarityConfig)
local ModifierConfig = require(Config.ModifierConfig)

local UIController = require(script.Parent.UIController)

local log = Logger.new("InventoryController")
local player = Players.LocalPlayer

local InventoryController = {}

local SLOT_FILTERS = { "All", "Weapon", "Helmet", "Chest", "Legs", "Boots", "Accessory", "Gear" }
local STAT_ORDER = { "Damage", "Defense", "Health", "AttackSpeed", "CritChance", "CritDamage", "MoveSpeed", "Luck" }

local gui: ScreenGui? = nil
local panel: Frame? = nil
local grid: ScrollingFrame? = nil
local detailPane: Frame? = nil
local countLabel: TextLabel? = nil

local client: any = nil
local open = false
local activeFilter = "All"
local searchText = ""
local selectedId: string? = nil
local filterButtons: { [string]: Create.Button } = {}

--========================================================================
-- Helpers
--========================================================================

local function statText(name: string, value: number): string
	if name == "AttackSpeed" then
		return string.format("%.2f Atk Spd", value)
	elseif name == "Luck" then
		return string.format("+%.0f%% Luck", value * 100)
	elseif name == "CritChance" then
		return string.format("+%.0f%% Crit", value)
	elseif name == "CritDamage" then
		return string.format("+%.0f%% Crit Dmg", value)
	end
	return string.format("+%d %s", math.floor(value + 0.5), name)
end

--[[ Signed delta with a colour tag, for the comparison block. ]]
local function deltaText(name: string, delta: number): string
	if math.abs(delta) < 0.005 then
		return ""
	end

	local positive = delta > 0
	local colour = if positive then Theme.Color.Positive else Theme.Color.Negative
	local hex = string.format("#%02X%02X%02X", colour.R * 255, colour.G * 255, colour.B * 255)

	local body
	if name == "AttackSpeed" then
		body = string.format("%s%.2f Atk Spd", positive and "+" or "", delta)
	elseif name == "Luck" then
		body = string.format("%s%.0f%% Luck", positive and "+" or "", delta * 100)
	else
		body = string.format("%s%d %s", positive and "+" or "", math.floor(delta + 0.5), name)
	end

	return string.format('<font color="%s">%s</font>', hex, body)
end

local function ownedItems(): { any }
	local profile = client and client.Profile
	if not profile or not profile.Inventory then
		return {}
	end

	local list = {}
	for _, instance in pairs(profile.Inventory.Items) do
		table.insert(list, instance)
	end

	-- Rarest first, then highest power, then name — so the best thing a player
	-- owns is always the first card they see.
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

local function isEquipped(instanceId: string): boolean
	local profile = client and client.Profile
	if not profile or not profile.Equipment then
		return false
	end

	for _, id in pairs(profile.Equipment) do
		if id == instanceId then
			return true
		end
	end

	return false
end

--========================================================================
-- Detail pane
--========================================================================

local function renderDetail()
	local pane = detailPane
	if not pane then
		return
	end

	for _, child in ipairs(pane:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") then
			child:Destroy()
		end
	end

	local profile = client and client.Profile
	local instance = if selectedId and profile then profile.Inventory.Items[selectedId] else nil

	if not instance then
		Create.Label("Select an item", {
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Theme.Color.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = 1,
			Parent = pane,
		})
		return
	end

	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return
	end

	local rarity = RarityConfig.Get(instance.Rarity) or RarityConfig.Definitions.Common
	local stats = ItemInstance.GetStats(instance)
	local equipped = isEquipped(instance.Id)

	Create.Label(string.upper(rarity.Name) .. "  ·  " .. template.Slot, {
		Size = UDim2.new(1, 0, 0, 16),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = rarity.Color,
		LayoutOrder = 1,
		Parent = pane,
	})

	Create.Label(ItemInstance.GetStackLabel(instance), {
		Size = UDim2.new(1, 0, 0, 28),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Large,
		TextColor3 = Theme.Color.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 2,
		Parent = pane,
	})

	Create.Label(template.Description, {
		Size = UDim2.new(1, 0, 0, 32),
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		TextWrapped = true,
		LayoutOrder = 3,
		Parent = pane,
	})

	if instance.Modifier then
		local modifier = ModifierConfig.Get(instance.Modifier)
		if modifier then
			Create.Label(modifier.Name .. " — " .. modifier.Description, {
				Size = UDim2.new(1, 0, 0, 18),
				Font = Theme.Font.Medium,
				TextSize = Theme.TextSize.Tiny,
				TextColor3 = modifier.Color,
				LayoutOrder = 4,
				Parent = pane,
			})
		end
	end

	local statLines = {}
	for _, name in ipairs(STAT_ORDER) do
		if stats[name] and stats[name] ~= 0 then
			table.insert(statLines, statText(name, stats[name]))
		end
	end

	Create.Label(table.concat(statLines, "\n"), {
		Size = UDim2.new(1, 0, 0, 16 * math.max(#statLines, 1)),
		Font = Theme.Font.Medium,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 5,
		Parent = pane,
	})

	Create.Label("POWER " .. tostring(ItemInstance.GetPower(instance)), {
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Power,
		LayoutOrder = 6,
		Parent = pane,
	})

	-- Comparison against whatever occupies this slot right now.
	local current = equippedIn(template.Slot)
	if current and current.Id ~= instance.Id then
		local currentStats = ItemInstance.GetStats(current)
		local deltas = {}

		for _, name in ipairs(STAT_ORDER) do
			local text = deltaText(name, (stats[name] or 0) - (currentStats[name] or 0))
			if text ~= "" then
				table.insert(deltas, text)
			end
		end

		Create.Label("vs equipped: " .. ItemInstance.GetDisplayName(current), {
			Size = UDim2.new(1, 0, 0, 16),
			Font = Theme.Font.Medium,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.TextMuted,
			LayoutOrder = 7,
			Parent = pane,
		})

		Create.Label(if #deltas > 0 then table.concat(deltas, "\n") else "identical stats", {
			Size = UDim2.new(1, 0, 0, 16 * math.max(#deltas, 1)),
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Small,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = 8,
			Parent = pane,
		})
	end

	-- No "requires level" line: the server no longer gates equipping on level,
	-- so showing a requirement here would describe a rule that does not exist.
	-- See EquipmentService.Equip.

	-- Actions
	local actions = Create.new("Frame", {
		Name = "Actions",
		Size = UDim2.new(1, 0, 0, Theme.Layout.MinTouchPx),
		BackgroundTransparency = 1,
		LayoutOrder = 20,
		Parent = pane,
	}, {
		Create.ListLayout(Enum.FillDirection.Horizontal, Theme.Spacing.S),
	})

	local equipButton = Create.Button(if equipped then "UNEQUIP" else "EQUIP", {
		Size = UDim2.fromOffset(104, Theme.Layout.MinTouchPx),
		LayoutOrder = 1,
		Parent = actions,
	}, function()
		local remote = Remotes.Get("EquipRequest") :: RemoteFunction
		local result
		if equipped then
			result = remote:InvokeServer({ Action = "Unequip", Slot = template.Slot })
		else
			result = remote:InvokeServer({ InstanceId = instance.Id })
		end

		if type(result) == "table" and not result.Success then
			log:Warn("equip refused: %s", tostring(result.Error))
		end
	end)
	equipButton.Instance.Parent = actions

	local favButton = Create.Button(if instance.Favorite then "UNLOCK" else "LOCK", {
		Size = UDim2.fromOffset(88, Theme.Layout.MinTouchPx),
		BackgroundColor3 = Theme.Color.PanelRaised,
		HoverColor = Theme.Color.PanelHover,
		PressColor = Theme.Color.Panel,
		LayoutOrder = 2,
		Parent = actions,
	}, function()
		local remote = Remotes.Get("FavoriteRequest") :: RemoteEvent
		remote:FireServer({ InstanceId = instance.Id, Favorite = not instance.Favorite })
	end)
	favButton.Instance.Parent = actions

	local sellButton = Create.Button("SELL " .. Progression.FormatNumber(ItemInstance.GetSellValue(instance)), {
		Size = UDim2.fromOffset(116, Theme.Layout.MinTouchPx),
		BackgroundColor3 = Theme.Color.Negative,
		HoverColor = Color3.fromRGB(248, 110, 118),
		PressColor = Color3.fromRGB(200, 68, 76),
		LayoutOrder = 3,
		Parent = actions,
	}, function()
		local remote = Remotes.Get("SellRequest") :: RemoteFunction
		local result = remote:InvokeServer({ InstanceIds = { instance.Id } })

		-- The server asks for confirmation above Epic; re-send with the flag.
		if type(result) == "table" and result.Error == "ConfirmationRequired" then
			result = remote:InvokeServer({ InstanceIds = { instance.Id }, Confirmed = true })
		end

		if type(result) == "table" and result.Success then
			selectedId = nil
		end
	end)
	sellButton.Instance.Parent = actions

	sellButton.SetEnabled(not equipped and not instance.Favorite)
end

--========================================================================
-- Grid
--========================================================================

local function makeCard(instance: any, order: number): Frame
	local template = ItemConfig.Get(instance.TemplateId)
	local rarity = RarityConfig.Get(instance.Rarity) or RarityConfig.Definitions.Common
	local equipped = isEquipped(instance.Id)

	local card = Create.Panel({
		Name = instance.Id,
		Size = UDim2.fromOffset(132, 96),
		BackgroundColor3 = if selectedId == instance.Id then Theme.Color.PanelHover else Theme.Color.Panel,
		LayoutOrder = order,
	}, {
		Create.Label(ItemInstance.GetStackLabel(instance), {
			Size = UDim2.new(1, -16, 0, 32),
			Position = UDim2.fromOffset(8, 10),
			Font = Theme.Font.Medium,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.Text,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		Create.Label(rarity.Name, {
			Size = UDim2.new(1, -16, 0, 14),
			Position = UDim2.new(0, 8, 1, -34),
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = rarity.Color,
		}),
		Create.Label(tostring(ItemInstance.GetPower(instance)), {
			Size = UDim2.new(1, -16, 0, 14),
			Position = UDim2.new(0, 8, 1, -18),
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.Power,
		}),
	})

	-- Rarity border carries the read at a glance.
	local stroke = Create.Stroke(rarity.Color, if selectedId == instance.Id then Theme.Stroke.Thick else Theme.Stroke.Medium, 0.15)
	stroke.Parent = card

	-- Corner badges: E for equipped, a padlock glyph for locked.
	local badges = {}
	if equipped then
		table.insert(badges, "E")
	end
	if instance.Favorite then
		table.insert(badges, "L")
	end

	if #badges > 0 then
		Create.Label(table.concat(badges, " "), {
			Size = UDim2.fromOffset(30, 14),
			Position = UDim2.new(1, -36, 0, 8),
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.Positive,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
	end

	local button = Create.new("TextButton", {
		Name = "Hit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 5,
		Parent = card,
	}) :: TextButton

	button.Activated:Connect(function()
		selectedId = instance.Id
		InventoryController.Render()
	end)

	return card
end

local function renderGrid()
	local frame = grid
	if not frame then
		return
	end

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local items = ownedItems()
	local shown = 0
	local needle = string.lower(searchText)

	for _, instance in ipairs(items) do
		local template = ItemConfig.Get(instance.TemplateId)
		if template then
			local slotOk = activeFilter == "All" or template.Slot == activeFilter
			local searchOk = needle == ""
				or string.find(string.lower(template.Name), needle, 1, true) ~= nil
				or string.find(string.lower(instance.Rarity), needle, 1, true) ~= nil

			if slotOk and searchOk then
				shown += 1
				makeCard(instance, shown).Parent = frame
			end
		end
	end

	local rows = math.ceil(shown / 4)
	frame.CanvasSize = UDim2.fromOffset(0, rows * (96 + Theme.Spacing.S) + Theme.Spacing.S)

	if countLabel then
		-- No capacity any more: duplicates stack, so what matters is how many
		-- copies you own and how many distinct stacks that is.
		local copies = 0
		for _, instance in ipairs(items) do
			copies += ItemInstance.GetCount(instance)
		end

		countLabel.Text = string.format("%d shown  ·  %d items in %d stacks", shown, copies, #items)
	end
end

function InventoryController.Render()
	if not open then
		return
	end
	renderGrid()
	renderDetail()
end

--========================================================================
-- Build
--========================================================================

local function build()
	local screen = Create.new("ScreenGui", {
		Name = "InventoryPanel",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	Create.new("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Scrim,
		BackgroundTransparency = Theme.Transparency.Scrim,
		Parent = screen,
	})

	local main = Create.Panel({
		Name = "Panel",
		Size = UDim2.new(1, -80, 1, -80),
		Position = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Theme.Color.Backdrop,
		Parent = screen,
	}, {
		Create.Padding(Theme.Spacing.L),
	}) :: Frame

	local maxSize = Create.new("UISizeConstraint", {
		MaxSize = Vector2.new(Theme.Layout.PanelMaxWidthPx, Theme.Layout.PanelMaxHeightPx),
	})
	maxSize.Parent = main

	Create.Label("INVENTORY", {
		Name = "Title",
		Size = UDim2.new(0, 200, 0, 28),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Large,
		Parent = main,
	})

	countLabel = Create.Label("", {
		Name = "Count",
		Size = UDim2.new(0, 260, 0, 16),
		Position = UDim2.fromOffset(0, 30),
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		Parent = main,
	})

	local close = Create.Button("CLOSE", {
		Size = UDim2.fromOffset(88, Theme.Layout.MinTouchPx),
		Position = UDim2.new(1, -88, 0, 0),
		BackgroundColor3 = Theme.Color.PanelRaised,
		HoverColor = Theme.Color.PanelHover,
		PressColor = Theme.Color.Panel,
		Parent = main,
	}, function()
		InventoryController.SetOpen(false)
	end)
	close.Instance.Parent = main

	-- Filter row
	local filters = Create.new("Frame", {
		Name = "Filters",
		Size = UDim2.new(1, -220, 0, 30),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = main,
	}, {
		Create.ListLayout(Enum.FillDirection.Horizontal, Theme.Spacing.XS),
	})

	for index, slot in ipairs(SLOT_FILTERS) do
		local button = Create.Button(slot, {
			Size = UDim2.fromOffset(if slot == "Accessory" then 84 else 66, 30),
			BackgroundColor3 = if slot == activeFilter then Theme.Color.Accent else Theme.Color.PanelRaised,
			HoverColor = Theme.Color.PanelHover,
			PressColor = Theme.Color.Panel,
			TextSize = Theme.TextSize.Tiny,
			LayoutOrder = index,
			Parent = filters,
		}, function()
			activeFilter = slot
			for id, other in pairs(filterButtons) do
				other.Instance.BackgroundColor3 = if id == slot then Theme.Color.Accent else Theme.Color.PanelRaised
			end
			InventoryController.Render()
		end)

		filterButtons[slot] = button
		button.Instance.Parent = filters
	end

	local search = Create.new("TextBox", {
		Name = "Search",
		Size = UDim2.fromOffset(200, 30),
		Position = UDim2.new(1, -200, 0, 56),
		BackgroundColor3 = Theme.Color.PanelRaised,
		BorderSizePixel = 0,
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		PlaceholderText = "Search items...",
		PlaceholderColor3 = Theme.Color.TextDim,
		Text = "",
		ClearTextOnFocus = false,
		Parent = main,
	}, {
		Create.Corner(Theme.Radius.Small),
		Create.Padding(8),
	}) :: TextBox

	search:GetPropertyChangedSignal("Text"):Connect(function()
		searchText = search.Text
		renderGrid()
	end)

	grid = Create.new("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.new(1, -300, 1, -100),
		Position = UDim2.fromOffset(0, 96),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Color.Divider,
		CanvasSize = UDim2.fromOffset(0, 0),
		Parent = main,
	}, {
		Create.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(132, 96),
			CellPadding = UDim2.fromOffset(Theme.Spacing.S, Theme.Spacing.S),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame

	detailPane = Create.Panel({
		Name = "Detail",
		Size = UDim2.new(0, 284, 1, -100),
		Position = UDim2.new(1, -284, 0, 96),
		BackgroundColor3 = Theme.Color.Panel,
		Parent = main,
	}, {
		Create.Padding(Theme.Spacing.M),
		Create.ListLayout(Enum.FillDirection.Vertical, Theme.Spacing.XS),
	}) :: Frame

	panel = main
	gui = screen
end

--========================================================================
-- Open / close
--========================================================================

function InventoryController.SetOpen(value: boolean)
	if not gui then
		return
	end

	local screen = gui :: ScreenGui
	open = value
	screen.Enabled = value

	if value then
		InventoryController.Render()

		local main = panel :: Frame
		main.BackgroundTransparency = 1
		TweenService:Create(main, Theme.Tween.Normal, { BackgroundTransparency = 0 }):Play()
	end
end

local started = false

function InventoryController.Start(clientState: any)
	if started then
		return
	end
	started = true

	client = clientState

	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("InventoryPanel")
	if existing then
		existing:Destroy()
	end

	build()

	UIController.NavActivated:Connect(function(name: string)
		-- "Gear" belongs to GearController now; this panel owns Inventory only.
		-- Both answering it would open two overlapping panels on one click.
		if name == "Inventory" then
			activeFilter = "All"
			InventoryController.SetOpen(not open)
		end
	end)

	-- Redraw whenever the server pushes a new profile view.
	client.ProfileChanged:Connect(function()
		InventoryController.Render()
	end)

	log:Info("ready")
end

return InventoryController
