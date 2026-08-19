--!strict
--[[
	RNGService — server-authoritative rolling.

	The client sends "I want to roll". Everything else happens here: cooldown,
	luck, pity, which rarity, which item, what modifier, and the write into the
	inventory. The client is told the outcome only after it is already committed.

	How the odds are actually built, in order:

	  1. Start from RarityConfig weights (exact integers out of 10,000,000).
	  2. Multiply tiers at or above LuckMinRank by the player's clamped luck.
	     Luck deliberately does not touch Common/Uncommon — boosting those would
	     spend the budget on outcomes nobody wants.
	  3. Multiply any tier the player is past pity on, ramping with how far past
	     they are, capped at PityMaxMultiplier. Pity nudges; it never guarantees.
	  4. Enforce a floor on Common's share, so no amount of stacked luck can
	     collapse the ladder.

	The result is understandable — a player can be told exactly what their luck
	does — and bounded, so no combination of boosts breaks the economy.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local RarityConfig = require(Config.RarityConfig)
local ItemConfig = require(Config.ItemConfig)
local MultiplierConfig = require(Config.MultiplierConfig)
local GameConfig = require(Config.GameConfig)
local ItemInstance = require(Modules.ItemInstance)
local Logger = require(Modules.Logger)
local Signal = require(Modules.Signal)
local Remotes = require(Modules.Remotes)

local DataService = require(script.Parent.DataService)
local NetGuard = require(script.Parent.NetGuard)
local ReplicationService = require(script.Parent.ReplicationService)

local log = Logger.new("RNGService")

local RNGService = {}

--[[ Fires (player, instance, rarityId) after a roll is committed. ]]
RNGService.ItemRolled = Signal.new()

local random = Random.new()
local lastRollAt: { [Player]: number } = {}

--========================================================================
-- Luck
--========================================================================

--[[
	Total luck multiplier: 1.0 base, plus permanent progression luck, plus any
	Luck stat on equipped items, plus active temporary boosts.

	Clamped by the caller — this returns the raw sum so the UI can show a
	player their true luck even when it exceeds the roll cap.
]]
function RNGService.GetEffectiveLuck(profile: any): number
	local luck = 1 + (profile.Luck.Permanent or 0)

	for _, instanceId in pairs(profile.Equipment) do
		if instanceId ~= "" then
			local instance = profile.Inventory.Items[instanceId]
			if instance then
				local stats = ItemInstance.GetStats(instance)
				luck += stats.Luck or 0
			end
		end
	end

	local now = os.time()
	for _, boost in pairs(profile.Boosts) do
		if type(boost) == "table" and (boost.ExpiresAt or 0) > now then
			luck += (boost.LuckBonus or 0)
		end
	end

	return luck
end

--========================================================================
-- Weighting
--========================================================================

--[[
	Pity multiplier for one tier. 1.0 until the player passes the threshold,
	then ramps linearly and caps.
]]
local function pityMultiplier(rarityId: string, pity: any): number
	local rarity = RarityConfig.Get(rarityId)
	if not rarity or not rarity.PityThreshold then
		return 1
	end

	local counter = pity[rarityId] or 0
	local threshold = rarity.PityThreshold

	if counter <= threshold then
		return 1
	end

	local ramp = 1 + (counter - threshold) / threshold
	return math.min(ramp, GameConfig.RNG.PityMaxMultiplier)
end

--[[
	Effective weights for this roll. Pure — safe to call from the UI to show a
	player their real odds, which is what keeps the system transparent.
]]
function RNGService.ComputeWeights(
	luck: number,
	pity: any,
	multiplier: number?,
	minRank: number?
): { [string]: number }
	local settings = GameConfig.RNG

	--[[
		MaxLuck caps STACKED BOOSTS, which is the job it was added for. A roll
		multiplier is a different thing — a deliberate, per-roll spike — so it
		applies ON TOP of that cap rather than being swallowed by it.

		Folding it in before the clamp would make 8x and 16x identical for any
		player already near the ceiling, which is precisely the player most
		likely to see them.
	]]
	local clampedLuck = math.clamp(luck, 1, settings.MaxLuck) * math.max(multiplier or 1, 1)

	local weights: { [string]: number } = {}
	local total = 0

	for _, rarityId in ipairs(RarityConfig.Order) do
		local rarity = RarityConfig.Definitions[rarityId]
		local weight = rarity.Weight

		-- A multiplier floor removes everything below it from the pool. Zero,
		-- not "very small": the whole point is that it CANNOT be rolled.
		if minRank and rarity.Rank < minRank then
			weights[rarityId] = 0
			continue
		end

		if rarity.Rank >= settings.LuckMinRank then
			--[[
				Higher tiers scale harder, so a large multiplier moves you UP
				the ladder rather than merely out of Common. A flat multiplier
				leaves the ratios inside the boosted block untouched, which is
				what made a 32x land on a Rare more often than anything else.

				At luck 1 the exponent is irrelevant (1^x == 1), so base rates
				are exactly what they were before this existed.
			]]
			local steps = rarity.Rank - settings.LuckMinRank
			weight *= clampedLuck ^ (1 + settings.LuckRankScaling * steps)
		end

		weight *= pityMultiplier(rarityId, pity)

		weights[rarityId] = weight
		total += weight
	end

	--[[
		Floor Common's share. Scale the boosted tiers down rather than inflating
		Common, so the relative ordering among rare tiers is preserved.

		Skipped entirely when a multiplier floor is active — re-inflating Common
		there would directly contradict the guarantee the floor just made.
	]]
	local commonWeight = if minRank then 0 else weights.Common
	local minCommon = total * settings.MinCommonWeightRatio

	if commonWeight < minCommon and commonWeight > 0 then
		local targetOthers = commonWeight * (1 - settings.MinCommonWeightRatio) / settings.MinCommonWeightRatio
		local currentOthers = total - commonWeight

		if currentOthers > 0 then
			local scale = targetOthers / currentOthers
			for rarityId, weight in pairs(weights) do
				if rarityId ~= "Common" then
					weights[rarityId] = weight * scale
				end
			end
		end
	end

	return weights
end

--[[ Weighted pick over the computed table. ]]
function RNGService.PickRarity(weights: { [string]: number }, rng: Random): string
	local total = 0
	for _, rarityId in ipairs(RarityConfig.Order) do
		total += weights[rarityId] or 0
	end

	local roll = rng:NextNumber() * total
	local cursor = 0

	for _, rarityId in ipairs(RarityConfig.Order) do
		cursor += weights[rarityId] or 0
		if roll <= cursor then
			return rarityId
		end
	end

	--[[
		Fallback for floating-point drift at the very top of the range.

		Returns the last tier that actually had weight, NOT a hardcoded Common:
		when a multiplier floors the table, Common's weight is zero and handing
		it back would silently break the guarantee the floor exists to make.
	]]
	for index = #RarityConfig.Order, 1, -1 do
		local rarityId = RarityConfig.Order[index]
		if (weights[rarityId] or 0) > 0 then
			return rarityId
		end
	end

	return "Common"
end

--========================================================================
-- Pity bookkeeping
--========================================================================

--[[
	Rolling a tier resets its counter and every tier below it — getting a
	Legendary should clear Rare and Epic pity too, since the player just got
	something better than either was protecting against.
]]
local function updatePity(profile: any, rolledRarityId: string)
	local rolledRank = RarityConfig.GetRank(rolledRarityId)

	for rarityId in pairs(profile.Pity) do
		local rank = RarityConfig.GetRank(rarityId)
		if rank > 0 then
			if rolledRank >= rank then
				profile.Pity[rarityId] = 0
			else
				profile.Pity[rarityId] += 1
			end
		end
	end
end

--========================================================================
-- Rolling
--========================================================================

function RNGService.GetCooldown(profile: any): number
	-- Gamepass and boost reductions fold in at Phase 9; the clamp is here now
	-- so no future multiplier can drive the cooldown to zero.
	return math.max(GameConfig.Roll.CooldownSeconds, GameConfig.Roll.MinCooldownSeconds)
end

--[[
	Total items held, counting every copy in every stack.

	Distinct from #Items, which is now the number of STACKS. Both are useful:
	stacks is what the grid draws, total is what the player thinks they own.

	There is no capacity any more. Inventory.BaseCapacity remains in the schema
	and is still replicated, but nothing enforces it — see Roll().
]]
function RNGService.CountItems(profile: any): number
	local total = 0
	for _, instance in pairs(profile.Inventory.Items) do
		total += ItemInstance.GetCount(instance)
	end
	return total
end

--[[
	Performs one roll. Returns a result table; never throws.

	Every failure path returns a named Error the client can present, rather than
	a bare false, so the UI can say something useful.
]]
function RNGService.Roll(player: Player): any
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	local now = os.clock()
	local cooldown = RNGService.GetCooldown(profile)
	local last = lastRollAt[player]

	if last and (now - last) < cooldown then
		return { Success = false, Error = "Cooldown", RetryAfter = cooldown - (now - last) }
	end

	--[[
		No capacity check. Duplicates stack instead of occupying slots, so the
		inventory grows by distinct item-and-modifier combinations rather than
		by rolls — bounded by the item table, not by how long you auto-roll.

		That bound is what makes an unlimited inventory safe rather than merely
		generous: every instance carries a Variance table, and storing one per
		roll would grow the profile without limit and eventually exceed the
		DataStore value limit mid-session.
	]]
	lastRollAt[player] = now

	--[[
		The multiplier chain.

		Landing on the multiplier card consumes that roll and starts another,
		with the next rung swapped into the pool. `chain` is every rung landed
		on, in order, so the client can replay one spin per step — what it
		shows is what happened, not a reconstruction.

		The whole chain resolves here rather than across several remote calls:
		one RollRequest is still one roll from the player's side, and doing it
		in a single server pass means the cooldown cannot be gamed by a chain.
	]]
	local multiplier, multiplierRung, multiplierChain = MultiplierConfig.RollChain(random)

	-- A rung may guarantee a minimum tier, not just better odds.
	local rungInfo = MultiplierConfig.GetRung(multiplierRung)
	local minRank = if rungInfo.MinRarity then RarityConfig.GetRank(rungInfo.MinRarity) else nil

	local luck = RNGService.GetEffectiveLuck(profile)
	local weights = RNGService.ComputeWeights(luck, profile.Pity, multiplier, minRank)
	local rarityId = RNGService.PickRarity(weights, random)

	local candidates = ItemConfig.GetByRarity(rarityId)
	if #candidates == 0 then
		-- Guarded against at require time, but a live config edit could break it.
		log:Error("no items exist for rarity '%s'", rarityId)
		return { Success = false, Error = "NoItemsForRarity" }
	end

	local templateId = candidates[random:NextInteger(1, #candidates)]

	local instanceId = "i" .. tostring(profile.Inventory.NextInstanceId)
	profile.Inventory.NextInstanceId += 1

	local instance = ItemInstance.Create(templateId, instanceId, random)
	if not instance then
		log:Error("failed to create instance of '%s'", templateId)
		return { Success = false, Error = "InstanceCreationFailed" }
	end

	--[[
		Stack onto an existing pile of the same item, or start a new one.

		When a stack already exists we keep the BEST-rolled copy and count the
		rest. Variance is a continuous roll, so duplicates are never actually
		identical and something has to be discarded; discarding the weaker roll
		is the only choice that never takes anything away from the player —
		auto-equip would have picked the best one anyway.

		The stack keeps its original Id. Equipment stores instance ids, so
		reusing the id means a stack you are wearing silently improves when a
		better copy lands, with no re-equip and no dangling reference.
	]]
	local stackKey = ItemInstance.StackKey(instance)
	local stack: any = nil

	for _, owned in pairs(profile.Inventory.Items) do
		if ItemInstance.StackKey(owned) == stackKey then
			stack = owned
			break
		end
	end

	if stack then
		stack.Count = ItemInstance.GetCount(stack) + 1

		if ItemInstance.GetPower(instance) > ItemInstance.GetPower(stack) then
			stack.Variance = instance.Variance
		end

		-- Everything downstream (the reveal, ItemRolled, auto-equip) should see
		-- the stack, not the throwaway copy that merged into it.
		instance = stack
	else
		instance.Count = 1
		profile.Inventory.Items[instanceId] = instance
	end

	updatePity(profile, rarityId)

	local stats = profile.Stats
	stats.TotalRolls += 1
	stats.ItemsObtained += 1

	local rank = RarityConfig.GetRank(rarityId)
	if rank > (stats.BestRarityRank or 0) then
		stats.BestRarityRank = rank
		stats.BestItemId = templateId
	end

	RNGService.ItemRolled:Fire(player, instance, rarityId)

	local rarity = RarityConfig.Definitions[rarityId]
	local displayName = ItemInstance.GetDisplayName(instance)

	if rarity.AnnounceGlobal then
		local oneInN = RarityConfig.GetOneInN(rarityId)
		ReplicationService.Announce(
			string.format(
				"%s just obtained %s — 1 in %s!",
				player.DisplayName,
				string.upper(displayName),
				if oneInN then tostring(math.floor(oneInN)) else "???"
			),
			rarityId
		)
		log:Info("%s rolled %s (%s)", player.Name, displayName, rarityId)
	end

	ReplicationService.Push(player)

	return {
		Success = true,
		Instance = instance,
		Rarity = rarityId,
		DisplayName = displayName,
		Stats = ItemInstance.GetStats(instance),
		Power = ItemInstance.GetPower(instance),
		SellValue = ItemInstance.GetSellValue(instance),
		Cooldown = cooldown,
		Announced = rarity.AnnounceGlobal,
		Multiplier = multiplier,
		MultiplierRung = multiplierRung,
		-- Every rung landed on, in order. The client spins once per entry.
		Chain = multiplierChain,
		Count = ItemInstance.GetCount(instance),
	}
end

--========================================================================
-- Auto-roll
--========================================================================

type AutoState = {
	StopAtRank: number,
	StartedAt: number,
}

local autoRolling: { [Player]: AutoState } = {}

--[[
	Starts or stops auto-roll.

	Server-driven on purpose: a client loop firing RollRequest would be
	indistinguishable from a script doing the same thing, and would put the
	pacing under client control. Here the server owns the cadence, applies the
	same cooldown as a manual roll, and stops itself on the player's condition.
]]
function RNGService.SetAutoRoll(player: Player, enabled: boolean, stopAtRarity: string?)
	if not enabled then
		autoRolling[player] = nil
		return
	end

	if not GameConfig.Roll.AutoRollEnabled then
		return
	end

	if not DataService.Get(player) then
		return
	end

	autoRolling[player] = {
		-- 0 means "never stop on rarity".
		StopAtRank = if stopAtRarity then RarityConfig.GetRank(stopAtRarity) else 0,
		StartedAt = os.clock(),
	}
end

function RNGService.IsAutoRolling(player: Player): boolean
	return autoRolling[player] ~= nil
end

--[[
	One central loop rather than a task per player: at 30 players that is one
	timer instead of thirty, and rolls stay naturally staggered.
]]
local function startAutoLoop()
	task.spawn(function()
		local rollResult = Remotes.Get("RollResult") :: RemoteEvent

		while true do
			task.wait(0.25)

			for player, state in pairs(autoRolling) do
				if not player.Parent then
					autoRolling[player] = nil
					continue
				end

				-- Hard ceiling so an idle session cannot roll forever.
				if os.clock() - state.StartedAt > GameConfig.Roll.MaxAutoRollDuration then
					autoRolling[player] = nil
					ReplicationService.Notify(player, "Auto-roll stopped (time limit).", "Info")
					continue
				end

				--[[
					Auto pacing, separate from the shared roll cooldown.

					Without this the loop rolls the instant the cooldown allows,
					which is faster than the reveal can play — spins get cut off
					mid-flight and a chain is unwatchable. A chain also earns
					extra time, since it is several spins rather than one.
				]]
				if (state.NextAt or 0) > os.clock() then
					continue
				end

				local result = RNGService.Roll(player)

				if result.Success then
					rollResult:FireClient(player, result)

					state.NextAt = os.clock()
						+ GameConfig.Roll.AutoRollIntervalSeconds
						+ #(result.Chain or {}) * GameConfig.Roll.AutoRollChainPauseSeconds

					if state.StopAtRank > 0 and RarityConfig.GetRank(result.Rarity) >= state.StopAtRank then
						autoRolling[player] = nil
						ReplicationService.Notify(
							player,
							string.format("Auto-roll stopped: %s found!", result.DisplayName),
							"Success"
						)
					end
				elseif result.Error == "ProfileNotLoaded" then
					autoRolling[player] = nil
				end
				-- "Cooldown" is the normal case between ticks; just wait.
			end
		end
	end)
end

local started = false

function RNGService.Start()
	if started then
		return
	end
	started = true

	NetGuard.OnFunction("RollRequest", function(player)
		return RNGService.Roll(player)
	end)

	NetGuard.OnEvent("AutoRollRequest", function(player, payload)
		if type(payload) ~= "table" then
			return
		end

		local stopAt = payload.StopAtRarity
		if stopAt ~= nil and (type(stopAt) ~= "string" or not RarityConfig.Get(stopAt)) then
			stopAt = nil
		end

		RNGService.SetAutoRoll(player, payload.Enabled == true, stopAt)
	end)

	startAutoLoop()

	Players.PlayerRemoving:Connect(function(player)
		lastRollAt[player] = nil
		autoRolling[player] = nil
	end)

	log:Info("started (%d item templates)", ItemConfig.Count())
end

return RNGService
