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
local MultiplierConfig = require(Config.MultiplierConfig)

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

--[[
	THE REEL
	--------
	A case-opening strip: cards scroll UPWARD past a fixed centre line,
	decelerating onto the one you won. Two of them exist, built from the same
	code — the big one in the reveal, and a compact one at the top of the
	screen that runs during auto-roll so rolls stay visible while you play.

	Vertical rather than horizontal: item names are long and read far better in
	a tall card than a wide one, and a vertical strip leaves the middle of the
	screen clear instead of cutting across it.

	Why Quint/Out easing: it is fast for most of its travel and then crawls the
	last few cards, which is the whole feel of a case opening. A linear or
	Quad tween arrives without any tension.

	The landing point carries a deliberate jitter so the winner does not stop
	dead-centre every single time. Kept well inside half a card width, so the
	winning card is always unambiguously the one under the marker.
]]
--[[
	Reels are narrower than a single one would need to be, because a chain puts
	several side by side. Six is the worst case (five rungs plus the item), and
	the row scales itself down to fit rather than running off screen.
]]
local BIG_REEL = {
	Width = 230,
	Height = 360,
	CardHeight = 76,
	Gap = 6,
	-- Winner sits near the end so there is a long run-up, with a few cards
	-- left over so the strip never runs out mid-tween.
	Count = 44,
	WinnerIndex = 38,
	TextSize = Theme.TextSize.Small,
	RowGap = 14,
	RowMaxWidth = 1120,
}

local TOP_REEL = {
	Width = 150,
	Height = 156,
	CardHeight = 44,
	Gap = 4,
	Count = 26,
	WinnerIndex = 21,
	TextSize = Theme.TextSize.Tiny,
	RowGap = 8,
	RowMaxWidth = 720,
}

--[[
	Auto-roll spin length. Must stay under the roll cooldown (1.5s default) or
	spins pile up; anything arriving mid-spin is held in `topPending` and only
	the newest survives, so a boosted cadence degrades to showing a subset
	rather than queueing a backlog.
]]
local TOP_SPIN = 1.05

--[[
	A row of reels rather than one reel reused.

	Landing on a multiplier opens a NEW reel beside the last one instead of
	respinning the same strip — the growing row is the payoff, and a chain of
	three is three reels sitting there at once rather than one strip you have
	to remember spun twice.

	Reels are pooled: built on first use, hidden between rolls, never destroyed.
	A deep chain during auto-roll would otherwise rebuild six reels every spin.
]]
local bigRow: any = nil
local topRow: any = nil

--[[
	Chain spins are a fraction of the full reveal length and hold briefly on the
	rung before the next one starts. A deep chain at full length would take most
	of a minute; these are punctuation, not the main event.
]]
local CHAIN_SPIN_RATIO = 0.45
local CHAIN_BEAT = 0.28

local topBusy = false
local topPending: any = nil

--[[ Reel filler, built once from real templates: name plus its rarity. ]]
type ReelEntry = { Name: string, Rarity: string }
local reelEntries: { ReelEntry } = {}

--========================================================================
-- Build
--========================================================================

--[[ Creates a clipped reel viewport with its strip, marker and edge fades. ]]
local function makeReel(name: string, spec: any, position: UDim2, parent: Instance): (Frame, Frame)
	local viewport = Create.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(spec.Width, spec.Height),
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.12,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 12,
		Parent = parent,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Small }),
		Create.new("UIStroke", {
			Color = Theme.Color.Divider,
			Thickness = Theme.Stroke.Thin,
			Transparency = 0.3,
		}),
	}) :: Frame

	-- Full width, height set by fillReel once the card count is known.
	local strip = Create.new("Frame", {
		Name = "Strip",
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = viewport,
	}) :: Frame

	-- Fixed centre line. The strip lands under this, never the other way.
	Create.new("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Theme.Color.Accent,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = viewport,
	})

	--[[
		Top and bottom fades, so cards dissolve in and out instead of popping at
		the clip boundary. Separate frames rather than one gradient on the
		viewport because the fade has to sit above the cards and below the
		marker, and a gradient on the parent would take the marker with it.

		Rotation 90 runs the gradient down the frame; 270 runs it back up.
	]]
	for _, side in ipairs({ { "FadeTop", 0, 270 }, { "FadeBottom", 1, 90 } }) do
		Create.new("Frame", {
			Name = side[1] :: string,
			AnchorPoint = Vector2.new(0, side[2] :: number),
			Position = UDim2.fromScale(0, side[2] :: number),
			Size = UDim2.new(1, 0, 0, math.floor(spec.Height * 0.22)),
			BackgroundColor3 = Theme.Color.Backdrop,
			BorderSizePixel = 0,
			ZIndex = 19,
			Parent = viewport,
		}, {
			Create.new("UIGradient", {
				Rotation = side[3] :: number,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		})
	end

	return viewport, strip
end

--[[
	Fills a strip with `spec.Count` cards, the real drop at spec.WinnerIndex
	and real item names either side of it, so what scrolls past reads as
	genuine possibilities rather than noise.
]]
local function fillReel(strip: Frame, spec: any, winnerName: string, winnerColor: Color3, poolRung: number?)
	strip:ClearAllChildren()

	--[[
		The multiplier card genuinely sits in the pool, so it has to appear
		among the filler too — otherwise it would only ever be visible on the
		spin that lands on it, and the player would never see the thing they
		were hoping to hit go past.

		One in seven is frequent enough to register as "that is in here" without
		crowding out the items.
	]]
	local poolInfo = if poolRung then MultiplierConfig.GetRung(poolRung) else nil

	for i = 1, spec.Count do
		local name: string
		local color: Color3

		if i == spec.WinnerIndex then
			name = winnerName
			color = winnerColor
		elseif poolInfo and math.random(1, 7) == 1 then
			name = poolInfo.Label
			color = poolInfo.Color
		else
			local entry = if #reelEntries > 0 then reelEntries[math.random(1, #reelEntries)] else nil
			name = if entry then entry.Name else "?"
			local rarity = if entry then RarityConfig.Definitions[entry.Rarity] else nil
			color = if rarity then rarity.Color else Theme.Color.TextMuted
		end

		--[[
			Deliberately plain: one panel, one rarity bar down the left edge,
			one bold name. The old card stacked a stroke, a bottom bar and
			small wrapped text, which at speed read as visual noise rather than
			as items. Colour does the work; the name just has to be legible.
		]]
		Create.new("Frame", {
			Name = "Card" .. tostring(i),
			Size = UDim2.new(1, -16, 0, spec.CardHeight),
			Position = UDim2.fromOffset(8, (i - 1) * (spec.CardHeight + spec.Gap)),
			BackgroundColor3 = Theme.Color.Panel,
			BackgroundTransparency = 0.06,
			ZIndex = 14,
			Parent = strip,
		}, {
			Create.new("UICorner", { CornerRadius = Theme.Radius.Medium }),
			-- Rarity bar on the leading edge: reads instantly even mid-scroll,
			-- and survives a name being truncated.
			Create.new("Frame", {
				Name = "Bar",
				Size = UDim2.new(0, 5, 1, -14),
				Position = UDim2.fromOffset(6, 7),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 15,
			}, {
				Create.new("UICorner", { CornerRadius = Theme.Radius.Pill }),
			}),
			Create.new("TextLabel", {
				Name = "Name",
				Size = UDim2.new(1, -28, 1, 0),
				Position = UDim2.fromOffset(20, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Bold,
				TextSize = spec.TextSize,
				TextColor3 = color,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = name,
				ZIndex = 15,
			}),
		})
	end

	strip.Size = UDim2.new(1, 0, 0, spec.Count * (spec.CardHeight + spec.Gap))
end

--[[
	Scrolls the strip so the winning card ends under the centre marker.
	Returns the tween so callers can wait on it.
]]
local function spinReel(strip: Frame, spec: any, duration: number): Tween
	local function centreOf(index: number): number
		return (index - 1) * (spec.CardHeight + spec.Gap) + spec.CardHeight / 2
	end

	-- Never a full half-card, so the winner is always the card on the line.
	local jitter = (math.random() - 0.5) * spec.CardHeight * 0.45

	strip.Position = UDim2.fromOffset(0, spec.Height / 2 - centreOf(1))

	local tween = TweenService:Create(
		strip,
		TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(0, spec.Height / 2 - centreOf(spec.WinnerIndex) + jitter) }
	)

	tween:Play()
	return tween
end

--[[
	Builds the container a chain's reels sit in: centred, laid out left to
	right, with a UIScale that shrinks the whole row once it outgrows its
	allowance. Reels themselves are added lazily by rowAcquire.
]]
local function makeReelRow(name: string, spec: any, position: UDim2, parent: Instance): any
	local container = Create.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(spec.Width, spec.Height),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 12,
		Parent = parent,
	}, {
		Create.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, spec.RowGap),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Create.new("UIScale", { Name = "Fit", Scale = 1 }),
	}) :: Frame

	return {
		Container = container,
		Spec = spec,
		Reels = {},
	}
end

--[[ Hides every reel in the row and collapses it back to one slot wide. ]]
local function rowReset(row: any)
	for _, reel in ipairs(row.Reels) do
		reel.Holder.Visible = false
	end
	row.Container.Visible = false
end

--[[ Floor on how far history compresses before it stops being readable. ]]
local MIN_OLDER_SCALE = 0.55

--[[
	Returns the nth reel, building it on first use, and resizes the row to hold
	`count` of them. Scale is recomputed each time so the row shrinks as it
	grows rather than overflowing on a deep chain.
]]
local function rowAcquire(row: any, index: number, count: number): (Frame, Frame)
	local spec = row.Spec
	local W, H, gap = spec.Width, spec.Height, spec.RowGap

	while #row.Reels < index do
		local order = #row.Reels + 1

		-- Each reel lives in a holder the list layout sizes. The viewport keeps
		-- its full pixel size and is shrunk by a UIScale instead, so the spin
		-- maths — which is all in spec.Height — stays valid at any scale.
		local holder = Create.new("Frame", {
			Name = "Slot" .. tostring(order),
			Size = UDim2.fromOffset(W, H),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Visible = false,
			Parent = row.Container,
		}) :: Frame

		local viewport, strip = makeReel("Reel", spec, UDim2.new(), holder)
		viewport.AnchorPoint = Vector2.new(0, 0)
		viewport.Position = UDim2.new()
		viewport.Visible = true

		local scale = Create.new("UIScale", { Name = "Shrink", Scale = 1, Parent = viewport }) :: UIScale

		table.insert(row.Reels, { Holder = holder, Viewport = viewport, Strip = strip, Scale = scale })
	end

	--[[
		The NEWEST reel always stays full size; the older ones give up the room.

		The reel you are watching is the one that matters, so shrinking it to
		make space for itself is backwards. Older reels are history — still
		readable, but they are what compresses.
	]]
	local older = 1
	local full = count * W + math.max(count - 1, 0) * gap

	if full > spec.RowMaxWidth and count > 1 then
		older = (spec.RowMaxWidth - W - (count - 1) * gap) / ((count - 1) * W)
		older = math.clamp(older, MIN_OLDER_SCALE, 1)
	end

	local width = W + (count - 1) * (W * older) + math.max(count - 1, 0) * gap

	for i = 1, #row.Reels do
		local reel = row.Reels[i]

		if i <= count then
			local f = if i == count then 1 else older
			reel.Holder.Size = UDim2.fromOffset(W * f, H * f)
			reel.Holder.Visible = true
			reel.Scale.Scale = f
		else
			reel.Holder.Visible = false
		end
	end

	row.Container.Size = UDim2.fromOffset(width, H)
	row.Container.Visible = true

	-- Backstop for the case where even a fully-shrunk history overflows.
	local fit = row.Container:FindFirstChild("Fit") :: UIScale?
	if fit then
		fit.Scale = math.min(1, spec.RowMaxWidth / math.max(width, 1))
	end

	local reel = row.Reels[index]
	return reel.Viewport, reel.Strip
end

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
		-- Sits BELOW the vertical reel now rather than behind it: the reel is
		-- the event, the card is where it resolves.
		Position = UDim2.new(0.5, -170, 0.5, 110),
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

	-- Both reels. The big one sits above the card; the compact one lives at
	-- the top of the screen and only appears while auto-roll is running.
	bigRow = makeReelRow("ReelRow", BIG_REEL, UDim2.new(0.5, 0, 0.5, -90), screen)

	--[[
		There is deliberately no multiplier badge.

		The reel that lands on 2X already IS the announcement, and a card
		repeating the same number beside it said the thing twice while taking
		up the space the next reel now opens into.
	]]
	topRow = makeReelRow(
		"TopReelRow",
		TOP_REEL,
		UDim2.new(0.5, 0, 0, TOP_REEL.Height / 2 + Theme.Layout.HUDMargin),
		screen
	)

	gui = screen
end

--[[
	Steps the multiplier card up through every rung the roll passed.

	Climbing 2X -> 4X -> 8X one pop at a time is the whole appeal: the tension
	is in watching it survive each step, and cutting straight to "8X" throws
	that away. Yields, so callers spawn it alongside the reel rather than
	before it — the two animations run together and the spin covers the climb.
]]
--========================================================================
-- Auto-roll: the top reel
--========================================================================

--[[
	Spins the compact reel for one auto-roll result.

	Anything arriving mid-spin replaces `topPending` rather than queueing, so a
	boosted cadence shows a subset instead of building a backlog that drifts
	further and further behind what the server actually rolled. Showing a stale
	spin would be worse than skipping one.
]]
local function runTopReel(result: any)
	if topBusy then
		topPending = result
		return
	end

	topBusy = true

	task.spawn(function()
		local current = result

		while current and topRow do
			-- Same growing row as the big reveal, just smaller and quicker.
			local chain = current.Chain or {}
			rowReset(topRow)

			--[[
				Chain spins run at FULL length here, not the shortened chain
				pace the reveal uses. Hitting a multiplier during auto-roll is
				the rarest thing that happens on screen, and rushing it was
				exactly what made it unreadable. The server grants extra time
				per rung (AutoRollChainPauseSeconds) to cover this.
			]]
			for step, rung in ipairs(chain) do
				local info = MultiplierConfig.GetRung(rung)
				local _, chainStrip = rowAcquire(topRow, step, step)

				fillReel(chainStrip, TOP_REEL, info.Label, info.Color, rung)
				spinReel(chainStrip, TOP_REEL, TOP_SPIN).Completed:Wait()
				task.wait(CHAIN_BEAT)
			end

			local itemRarity = RarityConfig.Definitions[current.Rarity]
			local itemColor = if itemRarity then itemRarity.Color else Theme.Color.Text

			local nextRung = if #chain > 0 then chain[#chain] + 1 else 2
			local poolRung = if nextRung <= MultiplierConfig.MaxRung() then nextRung else nil

			local last = #chain + 1
			local _, finalStrip = rowAcquire(topRow, last, last)

			fillReel(finalStrip, TOP_REEL, tostring(current.DisplayName or "?"), itemColor, poolRung)
			spinReel(finalStrip, TOP_REEL, TOP_SPIN).Completed:Wait()

			-- Beat on the winner so it is readable before the next spin.
			task.wait(0.35)

			current = topPending
			topPending = nil
		end

		if topRow then
			rowReset(topRow)
		end

		topBusy = false
	end)
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
	-- Cleared rather than left showing the previous drop: the reel above is
	-- what is rolling, and a stale name under it reads as the result.
	nameText.Text = ""
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

	--[[
		The spins.

		One per multiplier landed, then one for the item. Each chain spin puts
		the rung you actually hit under the marker and leaves its card visible
		in the pool, so the escalation is something you watched happen rather
		than a number that appeared.

		Chain spins are shorter than the final one: they are punctuation, and
		at full length a deep chain would take most of a minute.

		On Skip (duration 0) none of this runs and the result lands straight
		away, which is the whole point of that setting.
	]]
	local chain = result.Chain or {}

	if duration > 0 and bigRow then
		rowReset(bigRow)
		-- Cleared first: a badge left over from the previous roll would read as
		-- this roll having escalated when it did not.

		--[[
			One reel per chain step, each opening BESIDE the last rather than
			respinning the one before it. Count is passed as the index so the
			row widens with every reel, pushing the existing ones outward as
			the new one appears.
		]]
		for step, rung in ipairs(chain) do
			local info = MultiplierConfig.GetRung(rung)
			local _, strip = rowAcquire(bigRow, step, step)

			fillReel(strip, BIG_REEL, info.Label, info.Color, rung)
			spinReel(strip, BIG_REEL, duration * CHAIN_SPIN_RATIO).Completed:Wait()
			task.wait(CHAIN_BEAT)
		end

		-- Final reel: the pool now offers the NEXT rung up, which is the one
		-- that was on the table and missed.
		local nextRung = if #chain > 0 then chain[#chain] + 1 else 2
		local poolRung = if nextRung <= MultiplierConfig.MaxRung() then nextRung else nil

		local last = #chain + 1
		local _, finalStrip = rowAcquire(bigRow, last, last)

		fillReel(finalStrip, BIG_REEL, result.DisplayName, rarity.Color, poolRung)
		spinReel(finalStrip, BIG_REEL, duration).Completed:Wait()
		-- Held on screen through the reveal so the winning card stays visible
		-- under the marker next to its own stats.
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

	if bigRow then
		rowReset(bigRow)
	end

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

	-- Filler for the reel, drawn from real templates so what scrolls past looks
	-- like possibilities rather than gibberish. Rarity comes along too, so the
	-- cards going by are coloured like the real thing.
	for _, template in pairs(ItemConfig.Templates) do
		table.insert(reelEntries, { Name = template.Name, Rarity = template.Rarity })
	end

	table.sort(reelEntries, function(a, b)
		return a.Name < b.Name
	end)

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
		if type(result) ~= "table" or not result.Success then
			return
		end

		--[[
			While auto-roll runs, move the roll to the compact top reel.

			It is the same spin, just small and out of the way — the roll still
			happens on screen and you still watch the options go past, but the
			middle of the screen stays clear and the game stays playable. The
			gear strip on the right then shows what actually mattered: whether
			it got equipped.

			Only the auto path is demoted. A manual press still gets the full
			reveal, because that reveal is the thing the player asked for.
		]]
		if autoActive then
			runTopReel(result)
			return
		end

		task.spawn(reveal, result)
	end)

	log:Info("ready (%d reel entries)", #reelEntries)
end

return RollController
