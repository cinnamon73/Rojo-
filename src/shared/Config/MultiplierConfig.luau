--!strict
--[[
	MultiplierConfig — the escalating luck multiplier rolled alongside each item.

	The multiplier is AN ENTRY IN THE ROLL POOL, not a hidden pre-roll.

	A 2x card sits in the pool alongside the items. Landing on it does not award
	anything — it consumes that roll and immediately starts another one, with
	the next rung swapped into the pool in its place. So the second roll offers
	4x instead of 2x, the third 8x, and so on. The chain ends the first time you
	land on a real item, and the accumulated multiplier applies to that roll.

	That is why the client spins once per chain step: each rung was a genuine
	roll the player landed on, not a number revealed after the fact.

	Odds at the default 0.22 pool chance:

	    2x    22%          (about 1 in 4.5)
	    4x    4.8%         (about 1 in 21)
	    8x    1.07%        (about 1 in 94)
	    16x   0.23%        (about 1 in 425)
	    32x   0.05%        (about 1 in 1900)

	A 32x is roughly a once-an-evening event for a steady roller, which is the
	right frequency for something the whole screen reacts to.
]]

local MultiplierConfig = {}

export type Rung = {
	Value: number,
	Label: string,
	Color: Color3,
	-- Presentation weight, mirroring RarityConfig.VFXTier: 0 is silent,
	-- higher rungs earn progressively louder feedback.
	Tier: number,
	--[[
		Rarities below this are removed from the pool entirely for that roll.

		This is what makes a big multiplier a PROMISE rather than a nudge. Luck
		alone only reweights — it can always still hand you a Common — so a 32x
		could legitimately drop a Tattered Boots, which reads as the game
		ignoring you. A floor makes each rung categorically better than the one
		below instead of merely more likely to be.

		nil means no floor: the rung improves the odds and nothing more.
	]]
	MinRarity: string?,
}

--[[
	The ladder, lowest first. Index 1 is the no-multiplier case and is never
	shown — a "1x" card every roll would be noise.

	Capped at 32x deliberately. Past that the luck curve is saturated (see
	RNGService.ComputeWeights) and another rung would look bigger without
	rolling better, which is worse than not offering it.
]]
MultiplierConfig.Ladder = {
	{ Value = 1, Label = "", Color = Color3.fromRGB(150, 158, 178), Tier = 0 },

	-- 2x is the common one (about 1 in 5). Odds only — a floor here would make
	-- Rare routine and flatten the bottom of the ladder.
	{ Value = 2, Label = "2X", Color = Color3.fromRGB(96, 220, 128), Tier = 1 },

	-- From 4x up, every rung guarantees a tier you did not have before.
	{ Value = 4, Label = "4X", Color = Color3.fromRGB(96, 196, 255), Tier = 2, MinRarity = "Rare" },
	{ Value = 8, Label = "8X", Color = Color3.fromRGB(168, 124, 255), Tier = 3, MinRarity = "Epic" },
	{ Value = 16, Label = "16X", Color = Color3.fromRGB(255, 152, 72), Tier = 4, MinRarity = "Legendary" },
	{ Value = 32, Label = "32X", Color = Color3.fromRGB(255, 88, 108), Tier = 5, MinRarity = "Mythic" },
} :: { Rung }

--[[
	Chance that a given roll lands on the multiplier card rather than an item.

	Flat per roll, which is what "the 4x replaces the 2x in the pool" means: the
	slot is equally likely each time, and deep chains are rare by compounding.
]]
MultiplierConfig.PoolChance = 0.22

--[[ Highest rung index. Above this the pool holds no multiplier card. ]]
function MultiplierConfig.MaxRung(): number
	return #MultiplierConfig.Ladder
end

--[[
	Rolls the chain.

	Returns the final multiplier value, the final rung index, and the list of
	rungs landed on in order — the client replays that list as one spin each,
	so what it shows is exactly what happened rather than a reconstruction.

	`random` is injected for the same reason ItemInstance.Create takes one: the
	whole roll path has to be seedable and testable, and a bare math.random
	here would break that.
]]
function MultiplierConfig.RollChain(random: Random): (number, number, { number })
	local rung = 1
	local chain: { number } = {}

	while rung < MultiplierConfig.MaxRung() do
		if random:NextNumber() >= MultiplierConfig.PoolChance then
			break
		end

		rung += 1
		table.insert(chain, rung)
	end

	return MultiplierConfig.Ladder[rung].Value, rung, chain
end

function MultiplierConfig.GetRung(index: number): Rung
	local ladder = MultiplierConfig.Ladder
	return ladder[math.clamp(index, 1, #ladder)]
end

--[[ True when this rung is worth showing at all. ]]
function MultiplierConfig.IsActive(index: number): boolean
	return index > 1
end

return MultiplierConfig
