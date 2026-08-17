--!strict
--[[
	ModifierConfig — the affixes that can roll onto higher-tier items.

	An item carries AT MOST ONE modifier. That is the guard against broken
	combinations: no stacking Heavy + Sharp + Berserker into a single absurd
	weapon. If richer builds are wanted later, add a second slot deliberately
	with its own compatibility rules rather than removing this limit.

	Multipliers are applied to the item's base stats; Adds are flat. Effects are
	behavioural flags read by CombatService in Phase 4 — the data lives here so
	balance changes never require touching combat code.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RarityConfig"))

export type Modifier = {
	Id: string,
	Name: string,
	-- Relative selection weight among eligible modifiers.
	Weight: number,
	-- Lowest item rarity this can appear on.
	MinRarity: string,
	-- Stat name -> multiplier (1.15 = +15%).
	Multipliers: { [string]: number },
	-- Stat name -> flat addition.
	Adds: { [string]: number },
	-- Behavioural flag consumed by combat, with its magnitude.
	Effect: { Kind: string, Value: number }?,
	Color: Color3,
	Description: string,
}

local ModifierConfig = {}

--[[
	Chance that an eligible item rolls a modifier at all, by rarity rank.
	Rarer items are more likely to be interesting.
]]
ModifierConfig.ChanceByRarity = {
	Rare = 0.20,
	Epic = 0.35,
	Legendary = 0.50,
	Mythic = 0.65,
	Divine = 0.80,
	Celestial = 1.00,
}

local definitions: { [string]: Modifier } = {
	Sharp = {
		Id = "Sharp",
		Name = "Sharp",
		Weight = 100,
		MinRarity = "Rare",
		Multipliers = { Damage = 1.12 },
		Adds = {},
		Effect = nil,
		Color = Color3.fromRGB(198, 206, 220),
		Description = "+12% Damage",
	},

	Heavy = {
		Id = "Heavy",
		Name = "Heavy",
		Weight = 90,
		MinRarity = "Rare",
		-- The classic trade: real upside, real cost.
		Multipliers = { Damage = 1.15, AttackSpeed = 0.95 },
		Adds = {},
		Effect = nil,
		Color = Color3.fromRGB(190, 150, 110),
		Description = "+15% Damage, -5% Attack Speed",
	},

	Swift = {
		Id = "Swift",
		Name = "Swift",
		Weight = 90,
		MinRarity = "Rare",
		Multipliers = { AttackSpeed = 1.10 },
		Adds = {},
		Effect = nil,
		Color = Color3.fromRGB(140, 220, 240),
		Description = "+10% Attack Speed",
	},

	Fortified = {
		Id = "Fortified",
		Name = "Fortified",
		Weight = 90,
		MinRarity = "Rare",
		Multipliers = { Defense = 1.20 },
		Adds = {},
		Effect = nil,
		Color = Color3.fromRGB(150, 176, 210),
		Description = "+20% Defense",
	},

	Lucky = {
		Id = "Lucky",
		Name = "Lucky",
		Weight = 55,
		MinRarity = "Rare",
		Multipliers = {},
		Adds = { Luck = 0.05 },
		Effect = nil,
		Color = Color3.fromRGB(130, 226, 150),
		Description = "+5% Luck",
	},

	Critical = {
		Id = "Critical",
		Name = "Critical",
		Weight = 60,
		MinRarity = "Epic",
		Multipliers = {},
		Adds = { CritChance = 6, CritDamage = 12 },
		Effect = nil,
		Color = Color3.fromRGB(255, 186, 92),
		Description = "+6% Crit Chance, +12% Crit Damage",
	},

	Burning = {
		Id = "Burning",
		Name = "Burning",
		Weight = 45,
		MinRarity = "Epic",
		Multipliers = {},
		Adds = {},
		-- Percent of hit damage repeated as burn over 3s.
		Effect = { Kind = "Burn", Value = 0.30 },
		Color = Color3.fromRGB(240, 128, 60),
		Description = "Hits burn for 30% extra over 3s",
	},

	Frozen = {
		Id = "Frozen",
		Name = "Frozen",
		Weight = 45,
		MinRarity = "Epic",
		Multipliers = {},
		Adds = {},
		-- Fractional slow applied to the target on hit.
		Effect = { Kind = "Slow", Value = 0.25 },
		Color = Color3.fromRGB(150, 214, 255),
		Description = "Hits slow enemies by 25%",
	},

	Vampiric = {
		Id = "Vampiric",
		Name = "Vampiric",
		Weight = 30,
		MinRarity = "Legendary",
		Multipliers = {},
		Adds = {},
		-- Fraction of damage dealt returned as healing. Kept low: lifesteal
		-- scales with damage and trivialises combat if it is generous.
		Effect = { Kind = "Lifesteal", Value = 0.05 },
		Color = Color3.fromRGB(216, 72, 96),
		Description = "Heal for 5% of damage dealt",
	},

	Berserker = {
		Id = "Berserker",
		Name = "Berserker",
		Weight = 25,
		MinRarity = "Legendary",
		Multipliers = {},
		Adds = {},
		-- Up to +35% damage, scaling as health drops. High risk, high payoff.
		Effect = { Kind = "LowHealthDamage", Value = 0.35 },
		Color = Color3.fromRGB(232, 88, 72),
		Description = "Up to +35% Damage at low health",
	},
}

ModifierConfig.Definitions = definitions

function ModifierConfig.Get(modifierId: string): Modifier?
	return definitions[modifierId]
end

--[[
	Modifiers legal on an item of this rarity, sorted for reproducibility.
]]
function ModifierConfig.GetEligible(rarityId: string): { Modifier }
	local rank = RarityConfig.GetRank(rarityId)
	local eligible = {}

	for _, modifier in pairs(definitions) do
		if rank >= RarityConfig.GetRank(modifier.MinRarity) then
			table.insert(eligible, modifier)
		end
	end

	table.sort(eligible, function(a, b)
		return a.Id < b.Id
	end)

	return eligible
end

--[[ Probability that an item of this rarity rolls any modifier at all. ]]
function ModifierConfig.GetChance(rarityId: string): number
	return ModifierConfig.ChanceByRarity[rarityId] or 0
end

--[[
	Picks a modifier for `rarityId`, or nil for none.
	`random` is passed in so the roll is seedable and testable.
]]
function ModifierConfig.Roll(rarityId: string, random: Random): Modifier?
	if random:NextNumber() >= ModifierConfig.GetChance(rarityId) then
		return nil
	end

	local eligible = ModifierConfig.GetEligible(rarityId)
	if #eligible == 0 then
		return nil
	end

	local total = 0
	for _, modifier in ipairs(eligible) do
		total += modifier.Weight
	end

	local roll = random:NextNumber() * total
	local cursor = 0

	for _, modifier in ipairs(eligible) do
		cursor += modifier.Weight
		if roll <= cursor then
			return modifier
		end
	end

	return eligible[#eligible]
end

return ModifierConfig
