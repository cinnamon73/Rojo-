--!strict
--[[
	ClassSelectController — pick your class.

	Opens from the "Class" nav button. Reads every class from ClassConfig and
	renders one card each, showing what the class is and what its ability does,
	because a name and a tier tell a player nothing about how it plays.

	The lock state shown here is ADVISORY. ClassConfig.IsUnlocked is evaluated
	client-side to grey a card out, but the server re-checks on every request —
	including gamepass ownership, which is queried live rather than trusted from
	the profile. A player who edits their way past this UI gets refused.

	Selection takes effect on the next spawn, and the card says so. That is a
	server rule (swapping mid-fight would dodge damage and desync health), not a
	UI limitation, so it is stated rather than hidden.
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
local ClassConfig = require(Config.ClassConfig)

local UIController = require(script.Parent.UIController)

local log = Logger.new("ClassSelectController")
local player = Players.LocalPlayer

local ClassSelectController = {}

local CARD_WIDTH = 210
local CARD_HEIGHT = 168

local client: any = nil
local screenGui: ScreenGui? = nil
local grid: ScrollingFrame? = nil
local open = false

--========================================================================
-- Helpers
--========================================================================

local function tierLabel(definition: ClassConfig.ClassDefinition): string
	if definition.RequiresGamepass then
		return "PAID"
	end
	return "TIER " .. tostring(definition.Tier)
end

local function tierColor(definition: ClassConfig.ClassDefinition): Color3
	if definition.RequiresGamepass then
		return Theme.Color.Coins
	elseif definition.Tier >= 3 then
		return Theme.Color.Power
	elseif definition.Tier == 2 then
		return Theme.Color.Accent
	end
	return Theme.Color.TextMuted
end

--[[ The one-line summary of what makes this class worth picking. ]]
local function statLine(definition: ClassConfig.ClassDefinition): string
	return string.format(
		"%d HP   %d DMG   %d reach",
		definition.Health,
		definition.Damage,
		definition.AttackRange
	)
end

--========================================================================
-- Cards
--========================================================================

local function makeCard(definition: ClassConfig.ClassDefinition, order: number, parent: Instance)
	local profile = client and client.Profile
	local isCurrent = profile ~= nil and profile.Class == definition.Id

	-- Gamepass ownership is not in the profile view, so a paid class always
	-- renders locked here. The server is the one that actually knows.
	local unlocked, reason = ClassConfig.IsUnlocked(definition, profile, false)

	local card = Create.new("TextButton", {
		Name = definition.Id,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = if isCurrent then Theme.Color.PanelHover else Theme.Color.Panel,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Medium }),
		Create.new("UIStroke", {
			Color = if isCurrent then Theme.Color.Accent else tierColor(definition),
			Thickness = if isCurrent then Theme.Stroke.Thick else Theme.Stroke.Thin,
			Transparency = if unlocked then 0.2 else 0.6,
		}),
		Create.new("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			PaddingBottom = UDim.new(0, 10),
		}),
	}) :: TextButton

	Create.Label(tierLabel(definition) .. "  ·  " .. definition.Role, {
		Size = UDim2.new(1, 0, 0, 14),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = tierColor(definition),
		Parent = card,
	})

	Create.Label(definition.Name, {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 16),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Large,
		TextColor3 = if unlocked then Theme.Color.Text else Theme.Color.TextDim,
		Parent = card,
	})

	Create.Label(statLine(definition), {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 44),
		Font = Theme.Font.Medium,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextMuted,
		Parent = card,
	})

	Create.Label(definition.Ability.Name .. "  ·  " .. tostring(definition.Ability.Cooldown) .. "s", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.fromOffset(0, 66),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.Accent,
		Parent = card,
	})

	Create.Label(definition.Ability.Description, {
		Size = UDim2.new(1, 0, 0, 42),
		Position = UDim2.fromOffset(0, 82),
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})

	local footer = if isCurrent
		then "EQUIPPED"
		elseif unlocked then "SELECT"
		elseif reason == "GamepassRequired" then "GAMEPASS"
		else "LEVEL " .. tostring(definition.UnlockLevel)

	Create.Label(footer, {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = if isCurrent
			then Theme.Color.Positive
			elseif unlocked then Theme.Color.Text
			else Theme.Color.Negative,
		Parent = card,
	})

	if unlocked and not isCurrent then
		card.Activated:Connect(function()
			local remote = Remotes.Get("ClassSelectRequest") :: RemoteFunction
			local ok, result = pcall(function()
				return remote:InvokeServer({ ClassId = definition.Id })
			end)

			if not ok or type(result) ~= "table" or not result.Success then
				log:Warn("class select refused: %s", tostring(type(result) == "table" and result.Error or result))
				return
			end

			-- The panel redraws from ProfileChanged when the server pushes.
			ClassSelectController.SetOpen(false)
		end)
	end
end

--========================================================================
-- Render
--========================================================================

function ClassSelectController.Render()
	local frame = grid
	if not frame then
		return
	end

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for order, classId in ipairs(ClassConfig.Order) do
		local definition = ClassConfig.Get(classId)
		if definition then
			makeCard(definition, order, frame)
		end
	end

	local rows = math.ceil(#ClassConfig.Order / 3)
	frame.CanvasSize = UDim2.fromOffset(0, rows * (CARD_HEIGHT + Theme.Spacing.M) + Theme.Spacing.M)
end

--========================================================================
-- Build
--========================================================================

local function build(): ScreenGui
	local gui = Create.new("ScreenGui", {
		Name = "ClassSelect",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	Create.new("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Scrim,
		BackgroundTransparency = Theme.Transparency.Scrim,
		Parent = gui,
	})

	local panel = Create.new("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_WIDTH * 3 + Theme.Spacing.M * 4, 620),
		BackgroundColor3 = Theme.Color.Backdrop,
		Parent = gui,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Large }),
		Create.new("UIStroke", { Color = Theme.Color.Divider, Thickness = Theme.Stroke.Medium }),
	}) :: Frame

	Create.Label("CHOOSE YOUR CLASS", {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 18),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	Create.Label("Takes effect when you next respawn", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 50),
		Font = Theme.Font.Medium,
		TextSize = Theme.TextSize.Tiny,
		TextColor3 = Theme.Color.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})

	grid = Create.new("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(Theme.Spacing.M, 78),
		Size = UDim2.new(1, -Theme.Spacing.M * 2, 1, -134),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		CanvasSize = UDim2.new(),
		Parent = panel,
	}, {
		Create.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			CellPadding = UDim2.fromOffset(Theme.Spacing.M, Theme.Spacing.M),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}) :: ScrollingFrame

	local close = Create.Button("CLOSE", {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(160, Theme.Layout.MinTouchPx),
		BackgroundColor3 = Theme.Color.PanelRaised,
		HoverColor = Theme.Color.PanelHover,
		PressColor = Theme.Color.Panel,
		Parent = panel,
	}, function()
		ClassSelectController.SetOpen(false)
	end)

	if close and close.Instance then
		close.Instance.Parent = panel
	end

	return gui
end

--========================================================================
-- Open / close
--========================================================================

function ClassSelectController.SetOpen(value: boolean)
	open = value

	if screenGui then
		screenGui.Enabled = value
	end

	if value then
		ClassSelectController.Render()
	end
end

function ClassSelectController.Start(clientState: any)
	client = clientState

	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("ClassSelect")
	if existing then
		existing:Destroy()
	end

	screenGui = build()

	UIController.NavActivated:Connect(function(name: string)
		if name == "Class" then
			ClassSelectController.SetOpen(not open)
		end
	end)

	client.ProfileChanged:Connect(function()
		if open then
			ClassSelectController.Render()
		end
	end)

	log:Info("ready (%d classes)", #ClassConfig.Order)
end

return ClassSelectController
