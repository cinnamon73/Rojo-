--!strict
--[[
	RollController — pressing ROLL, and the reveal that follows.

	The server has already decided and committed the outcome before this runs.
	Everything here is presentation: the reel, the card, the escalation for rare
	drops. That separation is deliberate — no amount of tampering with this file
	can change what a player receives.

	Presentation escalates with RarityConfig.VFXTier so a Celestial feels
	categorically different from a Common, without making Commons annoying:

	    tier 1-2   small pop, no scrim, short hold
	    tier 3-4   scrim, coloured stroke, longer hold
	    tier 5-6   heavy scrim, screen flash, longest hold
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
local ItemConfig = require(Config.ItemConfig)
local RarityConfig = require(Config.RarityConfig)
local GameConfig = require(Config.GameConfig)

local UIController = require(script.Parent.UIController)

local log = Logger.new("RollController")
local player = Players.LocalPlayer

local RollController = {}

local gui: ScreenGui? = nil
local scrim: Frame? = nil
local flash: Frame? = nil
local card: Frame? = nil
local cardStroke: UIStroke? = nil
local rarityLabel: TextLabel? = nil
local nameLabel: TextLabel? = nil
local statsLabel: TextLabel? = nil
local powerLabel: TextLabel? = nil

local client: any = nil
local revealing = false
local autoActive = false
local rollBusy = false

-- Reel filler, built once. Names only — no server data involved.
local reelNames: { string } = {}

--========================================================================
-- Build
--========================================================================

local function build()
	local screen = Create.new("ScreenGui", {
		Name = "RollReveal",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		IgnoreGuiInset = true,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	scrim = Create.new("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Scrim,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 1,
		Parent = screen,
	}) :: Frame

	flash = Create.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 30,
		Parent = screen,
	}) :: Frame

	rarityLabel = Create.Label("", {
		Name = "Rarity",
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		Size = UDim2.new(1, -32, 0, 18),
		Position = UDim2.fromOffset(16, 14),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12,
	})

	nameLabel = Create.Label("", {
		Name = "ItemName",
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Title,
		TextColor3 = Theme.Color.Text,
		Size = UDim2.new(1, -32, 0, 40),
		Position = UDim2.fromOffset(16, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = false,
		ZIndex = 12,
	})

	statsLabel = Create.Label("", {
		Name = "Stats",
		Font = Theme.Font.Medium,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		Size = UDim2.new(1, -32, 0, 76),
		Position = UDim2.fromOffset(16, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 12,
	})

	powerLabel = Create.Label("", {
		Name = "Power",
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Power,
		Size = UDim2.new(1, -32, 0, 20),
		Position = UDim2.new(0, 16, 1, -32),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 12,
	})

	card = Create.Panel({
		Name = "Card",
		Size = UDim2.fromOffset(340, 200),
		Position = UDim2.new(0.5, -170, 0.5, -120),
		BackgroundColor3 = Theme.Color.PanelRaised,
		Visible = false,
		ZIndex = 11,
		Parent = screen,
	}, {
		rarityLabel,
		nameLabel,
		statsLabel,
		powerLabel,
	})

	local stroke = Create.Stroke(Theme.Color.Divider, Theme.Stroke.Medium, 0)
	stroke.Parent = card
	cardStroke = stroke

	-- Scale from the centre so the pop reads correctly.
	Create.new("UIScale", { Name = "Scale", Scale = 1, Parent = card })

	gui = screen
end

--========================================================================
-- Reveal
--========================================================================

local function formatStats(stats: { [string]: number }): string
	local order = { "Damage", "Defense", "Health", "AttackSpeed", "CritChance", "CritDamage", "MoveSpeed", "Luck" }
	local parts = {}

	for _, statName in ipairs(order) do
		local value = stats[statName]
		if value and value ~= 0 then
			if statName == "AttackSpeed" then
				table.insert(parts, string.format("%.2f Atk Spd", value))
			elseif statName == "Luck" then
				table.insert(parts, string.format("+%.0f%% Luck", value * 100))
			elseif statName == "CritChance" or statName == "CritDamage" then
				table.insert(parts, string.format("+%.0f%% %s", value, if statName == "CritChance" then "Crit" else "Crit Dmg"))
			else
				table.insert(parts, string.format("+%d %s", math.floor(value + 0.5), statName))
			end
		end
	end

	return table.concat(parts, "   ")
end

--[[
	Runs the whole reveal. Yields, so callers should spawn it.
	`result` is the server's roll result, already committed.
]]
local function reveal(result: any)
	if revealing or not gui then
		return
	end
	revealing = true

	local rarity = RarityConfig.Get(result.Rarity) or RarityConfig.Definitions.Common
	local tier = rarity.VFXTier

	local settings = (client and client.Profile and client.Profile.Settings) or {}
	local speed = settings.RollSpeed or "Normal"
	local reduced = settings.ReducedEffects == true

	local duration = GameConfig.Roll.RevealDuration[speed] or GameConfig.Roll.RevealDuration.Normal
	if reduced then
		duration = math.min(duration, GameConfig.Roll.RevealDuration.Fast)
	end

	local cardFrame = card :: Frame
	local cardScale = cardFrame:FindFirstChild("Scale") :: UIScale

	-- Hoisted once rather than casting inline at each use. Besides being
	-- clearer, a statement that begins with `(` is a Luau parse hazard: it is
	-- ambiguous with a call continuing the previous line, and a leading `;` is
	-- not accepted at the start of a block.
	local nameText = nameLabel :: TextLabel
	local rarityText = rarityLabel :: TextLabel
	local statsText = statsLabel :: TextLabel
	local powerText = powerLabel :: TextLabel
	local stroke = cardStroke :: UIStroke
	local scrimFrame = scrim :: Frame

	cardFrame.Visible = true
	cardScale.Scale = 0.85
	nameText.TextColor3 = Theme.Color.Text
	powerText.Text = ""
	statsText.Text = ""
	rarityText.Text = "ROLLING"
	rarityText.TextColor3 = Theme.Color.TextDim
	stroke.Color = Theme.Color.Divider

	-- Scrim only from tier 3 up, so common rolls never dim the screen.
	if tier >= 3 and not reduced then
		scrimFrame.Visible = true
		scrimFrame.BackgroundTransparency = 1
		TweenService:Create(scrimFrame, Theme.Tween.Normal, {
			BackgroundTransparency = 1 - (0.18 + 0.08 * (tier - 3)),
		}):Play()
	end

	TweenService:Create(cardScale, Theme.Tween.Pop, { Scale = 1 }):Play()

	-- Reel: cycle filler names, decelerating.
	if duration > 0 and #reelNames > 0 then
		local elapsed = 0
		local interval = 0.045

		while elapsed < duration do
			nameText.Text = reelNames[math.random(1, #reelNames)]
			task.wait(interval)
			elapsed += interval
			-- Ease out: each tick a little slower than the last.
			interval = math.min(interval * 1.18, 0.22)
		end
	end

	-- Final state.
	nameText.Text = result.DisplayName
	nameText.TextColor3 = rarity.Color
	rarityText.Text = string.upper(rarity.Name)
	rarityText.TextColor3 = rarity.Color
	statsText.Text = formatStats(result.Stats or {})
	powerText.Text = "POWER " .. tostring(result.Power or 0)
	stroke.Color = rarity.GlowColor
	stroke.Thickness = if tier >= 5 then Theme.Stroke.Thick else Theme.Stroke.Medium

	cardScale.Scale = 0.94
	TweenService:Create(cardScale, Theme.Tween.Pop, { Scale = 1 }):Play()

	-- Screen flash for the top tiers only.
	if tier >= 5 and not reduced then
		local flashFrame = flash :: Frame
		flashFrame.Visible = true
		flashFrame.BackgroundColor3 = rarity.GlowColor
		flashFrame.BackgroundTransparency = 0.45
		TweenService:Create(flashFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.5, function()
			flashFrame.Visible = false
		end)
	end

	-- Rarer drops linger longer.
	local hold = 0.5 + 0.22 * tier
	if speed == "Skip" then
		hold = math.min(hold, 0.6)
	end
	task.wait(hold)

	TweenService:Create(cardScale, Theme.Tween.Fast, { Scale = 0.9 }):Play()
	TweenService:Create(scrimFrame, Theme.Tween.Normal, { BackgroundTransparency = 1 }):Play()
	task.wait(Theme.Tween.Normal.Time)

	cardFrame.Visible = false
	scrimFrame.Visible = false

	revealing = false
end

--========================================================================
-- Rolling
--========================================================================

local function requestRoll()
	if rollBusy then
		return
	end
	rollBusy = true

	UIController.SetRollEnabled(false)

	local remote = Remotes.Get("RollRequest") :: RemoteFunction
	local ok, result = pcall(function()
		return remote:InvokeServer()
	end)

	if not ok or type(result) ~= "table" then
		log:Warn("roll request failed: %s", tostring(result))
		rollBusy = false
		UIController.SetRollEnabled(true)
		return
	end

	if result.Success then
		reveal(result)
	elseif result.Error == "Cooldown" then
		-- Expected when clicking fast; not worth surfacing.
	elseif result.Error == "InventoryFull" then
		log:Warn("inventory full")
	else
		log:Warn("roll refused: %s", tostring(result.Error))
	end

	-- Re-enable after the server's own cooldown, so the button state matches
	-- the authoritative gate rather than guessing.
	local cooldown = result.Cooldown or result.RetryAfter or GameConfig.Roll.CooldownSeconds
	task.delay(cooldown, function()
		rollBusy = false
		UIController.SetRollEnabled(true)
	end)
end

local function setAuto(enabled: boolean)
	autoActive = enabled
	UIController.SetAutoActive(enabled)

	local remote = Remotes.Get("AutoRollRequest") :: RemoteEvent
	remote:FireServer({ Enabled = enabled })
end

--========================================================================
-- Start
--========================================================================

local started = false

function RollController.Start(clientState: any)
	if started then
		return
	end
	started = true

	client = clientState

	-- Filler names for the reel, drawn from real templates so it looks like
	-- possibilities rather than gibberish.
	for _, template in pairs(ItemConfig.Templates) do
		table.insert(reelNames, template.Name)
	end
	table.sort(reelNames)

	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("RollReveal")
	if existing then
		existing:Destroy()
	end

	build()

	UIController.RollActivated:Connect(function()
		task.spawn(requestRoll)
	end)

	UIController.NavActivated:Connect(function(panel: string)
		if panel == "__AutoToggle" then
			setAuto(not autoActive)
		end
	end)

	-- Server-driven auto-roll results arrive here rather than as invoke returns.
	local rollResult = Remotes.Get("RollResult") :: RemoteEvent
	rollResult.OnClientEvent:Connect(function(result)
		if type(result) == "table" and result.Success then
			task.spawn(reveal, result)
		end
	end)

	log:Info("ready (%d reel entries)", #reelNames)
end

return RollController
