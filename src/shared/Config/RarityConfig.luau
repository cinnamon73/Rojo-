--!strict
--[[
	RarityConfig — the rarity ladder.

	Weights are integers out of WeightTotal (10,000,000) rather than floats, so
	the odds are exact and readable. Changing a weight changes drop rates
	everywhere with no other edits.

	Approximate base chances at Luck 1.0:
		Common     ~74.7%
		Uncommon   ~20%
		Rare       1 in 25
		Epic       1 in 100
		Legendary  1 in 500
		Mythic     1 in 2,500
		Divine     1 in 10,000
		Celestial  1 in 100,000
]]

export type Rarity = {
	Id: string,
	Name: string,
	Rank: number,
	Weight: number,
	StatMultiplier: number,
	Color: Color3,
	GlowColor: Color3,
	SoundTier: number,
	VFXTier: number,
	AnnounceGlobal: boolean,
	-- Rolls without this rarity before pity begins nudging odds upward.
	-- nil means this tier has no pity track.
	PityThreshold: number?,
}

local RarityConfig = {}

RarityConfig.WeightTotal = 10_000_000

--[[
	Ordered low -> high. Rank is the index; use it for comparisons like
	"stop auto-roll at Legendary or better" instead of comparing names.
]]
RarityConfig.Order = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Divine",
	"Celestial",
}

local definitions: { [string]: Rarity } = {
	Common = {
		Id = "Common",
		Name = "Common",
		Rank = 1,
		Weight = 7_474_900,
		StatMultiplier = 1.0,
		Color = Color3.fromRGB(168, 175, 185),
		GlowColor = Color3.fromRGB(200, 205, 212),
		SoundTier = 1,
		VFXTier = 1,
		AnnounceGlobal = false,
		PityThreshold = nil,
	},

	Uncommon = {
		Id = "Uncommon",
		Name = "Uncommon",
		Rank = 2,
		Weight = 2_000_000,
		StatMultiplier = 1.25,
		Color = Color3.fromRGB(88, 196, 110),
		GlowColor = Color3.fromRGB(130, 226, 150),
		SoundTier = 1,
		VFXTier = 1,
		AnnounceGlobal = false,
		PityThreshold = nil,
	},

	Rare = {
		Id = "Rare",
		Name = "Rare",
		Rank = 3,
		Weight = 400_000,
		StatMultiplier = 1.6,
		Color = Color3.fromRGB(66, 148, 240),
		GlowColor = Color3.fromRGB(120, 182, 255),
		SoundTier = 2,
		VFXTier = 2,
		AnnounceGlobal = false,
		PityThreshold = 40,
	},

	Epic = {
		Id = "Epic",
		Name = "Epic",
		Rank = 4,
		Weight = 100_000,
		StatMultiplier = 2.1,
		Color = Color3.fromRGB(163, 96, 235),
		GlowColor = Color3.fromRGB(196, 146, 255),
		SoundTier = 3,
		VFXTier = 3,
		AnnounceGlobal = false,
		PityThreshold = 150,
	},

	Legendary = {
		Id = "Legendary",
		Name = "Legendary",
		Rank = 5,
		Weight = 20_000,
		StatMultiplier = 3.0,
		Color = Color3.fromRGB(244, 168, 54),
		GlowColor = Color3.fromRGB(255, 205, 120),
		SoundTier = 4,
		VFXTier = 4,
		AnnounceGlobal = false,
		PityThreshold = 700,
	},

	Mythic = {
		Id = "Mythic",
		Name = "Mythic",
		Rank = 6,
		Weight = 4_000,
		StatMultiplier = 4.5,
		Color = Color3.fromRGB(232, 68, 84),
		GlowColor = Color3.fromRGB(255, 122, 136),
		SoundTier = 5,
		VFXTier = 5,
		AnnounceGlobal = false,
		PityThreshold = 3_000,
	},

	Divine = {
		Id = "Divine",
		Name = "Divine",
		Rank = 7,
		Weight = 1_000,
		StatMultiplier = 7.0,
		Color = Color3.fromRGB(255, 238, 158),
		GlowColor = Color3.fromRGB(255, 250, 214),
		SoundTier = 6,
		VFXTier = 6,
		-- 1 in 10,000 is rare enough that a server-wide callout stays special.
		AnnounceGlobal = true,
		PityThreshold = nil,
	},

	Celestial = {
		Id = "Celestial",
		Name = "Celestial",
		Rank = 8,
		Weight = 100,
		StatMultiplier = 11.0,
		Color = Color3.fromRGB(126, 240, 255),
		GlowColor = Color3.fromRGB(196, 250, 255),
		SoundTier = 6,
		VFXTier = 6,
		AnnounceGlobal = true,
		PityThreshold = nil,
	},
}

RarityConfig.Definitions = definitions

--[[ Returns the rarity definition, or nil if the id is unknown. ]]
function RarityConfig.Get(rarityId: string): Rarity?
	return definitions[rarityId]
end

--[[ Rank of a rarity id, or 0 if unknown. Safe to compare directly. ]]
function RarityConfig.GetRank(rarityId: string): number
	local rarity = definitions[rarityId]
	return if rarity then rarity.Rank else 0
end

--[[ True if `rarityId` is at least as rare as `minimumId`. ]]
function RarityConfig.IsAtLeast(rarityId: string, minimumId: string): boolean
	return RarityConfig.GetRank(rarityId) >= RarityConfig.GetRank(minimumId)
end

--[[ Rarity id by rank, or nil. Used to walk the ladder. ]]
function RarityConfig.FromRank(rank: number): string?
	return RarityConfig.Order[rank]
end

--[[
	1-in-N odds for a rarity at base luck. Display only — the roller works in
	weights, this is for UI text like "1 in 10,000".
]]
function RarityConfig.GetOneInN(rarityId: string): number?
	local rarity = definitions[rarityId]
	if not rarity or rarity.Weight <= 0 then
		return nil
	end
	return RarityConfig.WeightTotal / rarity.Weight
end

--[[
	Validates the ladder at require time. A weight typo silently skewing every
	drop rate in the game is exactly the bug worth failing loudly on.
]]
local function validate()
	local sum = 0
	for rank, rarityId in ipairs(RarityConfig.Order) do
		local rarity = definitions[rarityId]
		assert(rarity, string.format("RarityConfig: '%s' is in Order but has no definition", rarityId))
		assert(
			rarity.Rank == rank,
			string.format("RarityConfig: '%s' has Rank %d but sits at index %d in Order", rarityId, rarity.Rank, rank)
		)
		sum += rarity.Weight
	end

	assert(
		sum == RarityConfig.WeightTotal,
		string.format("RarityConfig: weights sum to %d, expected %d", sum, RarityConfig.WeightTotal)
	)
end

validate()

return RarityConfig
