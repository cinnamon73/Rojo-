--!strict
--[[
	ItemConfig — every item template in the game.

	Templates are the DEFINITION of an item. What a player owns is an item
	*instance*: a template id plus rolled variance, a modifier, and a unique
	instance id. See ItemInstance for that half.

	Stats are authored explicitly per item rather than derived from
	RarityConfig.StatMultiplier. That multiplier stays a design reference for
	authoring — applying it on top of hand-tuned numbers would double-scale and
	quietly break balance. If you add an item, read the neighbours in its rarity
	band and stay in range.

	Stat vocabulary (keep it small — RPG stat bloat is a design smell):
		Damage        flat weapon damage per hit
		Defense       flat damage reduction
		Health        bonus max HP
		AttackSpeed   attacks per second (weapons only; 1.0 is the baseline)
		CritChance    percent, 0-100
		CritDamage    percent bonus on a crit, added to a 50% base
		MoveSpeed     flat studs/sec added to the 16 default
		Luck          additive luck; 0.05 means +5%
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("RarityConfig"))

export type Stats = {
	Damage: number?,
	Defense: number?,
	Health: number?,
	AttackSpeed: number?,
	CritChance: number?,
	CritDamage: number?,
	MoveSpeed: number?,
	Luck: number?,
}

export type Appearance = {
	Color: Color3,
	Material: Enum.Material,
	-- Placeholder geometry size. Replaced by real meshes later without any
	-- code change — swap MeshId in here and the spawner picks it up.
	Size: Vector3,
	MeshId: string?,
}

export type ItemTemplate = {
	Id: string,
	Name: string,
	Slot: string,
	Archetype: string?,
	Rarity: string,
	Description: string,
	BaseStats: Stats,
	--[[
		NOT ENFORCED. Kept as a tier hint for sorting and balance work only —
		players can equip anything they roll, at any level. Nothing reads this
		to allow or refuse an equip. See EquipmentService.Equip.
	]]
	LevelRequirement: number,
	SellValue: number,
	Icon: string?,
	Appearance: Appearance,
	Ability: string?,
	AllowModifiers: boolean,
}

local ItemConfig = {}

ItemConfig.Slots = { "Weapon", "Helmet", "Chest", "Legs", "Boots", "Accessory", "Gear" }

--[[ Weapon archetypes. Ability is granted by archetype, not per item. ]]
ItemConfig.Archetypes = {
	Sword = { Ability = "Whirlwind", Description = "Balanced damage and speed." },
	Greatsword = { Ability = "GroundSlam", Description = "Heavy hits, slow swing." },
	Dagger = { Ability = "DashStrike", Description = "Fast, crit-focused." },
	Bow = { Ability = "MultiShot", Description = "Ranged, steady damage." },
	Staff = { Ability = "ArcaneBlast", Description = "Ranged magic burst." },
}

--[[ Sell value scales off rarity so pricing stays consistent as items are added. ]]
local SELL_BY_RARITY = {
	Common = 15,
	Uncommon = 45,
	Rare = 180,
	Epic = 750,
	Legendary = 3_200,
	Mythic = 14_000,
	Divine = 60_000,
	Celestial = 250_000,
}

local templates: { [string]: ItemTemplate } = {}

local function define(template: ItemTemplate)
	assert(not templates[template.Id], "ItemConfig: duplicate item id " .. template.Id)
	assert(RarityConfig.Get(template.Rarity), "ItemConfig: unknown rarity on " .. template.Id)
	templates[template.Id] = template
end

--========================================================================
-- Weapons
--========================================================================

local function weapon(
	id: string,
	name: string,
	archetype: string,
	rarity: string,
	stats: Stats,
	description: string,
	color: Color3,
	material: Enum.Material,
	level: number
)
	local archetypeInfo = ItemConfig.Archetypes[archetype]
	assert(archetypeInfo, "ItemConfig: unknown archetype " .. archetype)

	define({
		Id = id,
		Name = name,
		Slot = "Weapon",
		Archetype = archetype,
		Rarity = rarity,
		Description = description,
		BaseStats = stats,
		LevelRequirement = level,
		SellValue = SELL_BY_RARITY[rarity],
		Appearance = {
			Color = color,
			Material = material,
			Size = if archetype == "Greatsword"
				then Vector3.new(0.4, 6.5, 1.4)
				elseif archetype == "Dagger" then Vector3.new(0.25, 2.4, 0.6)
				elseif archetype == "Bow" then Vector3.new(0.3, 4.5, 0.3)
				elseif archetype == "Staff" then Vector3.new(0.35, 5.5, 0.35)
				else Vector3.new(0.3, 4.2, 0.9),
		},
		-- Rare and above get their archetype's ability. Low-tier weapons stay
		-- simple so a new player is not handed a cooldown to manage.
		Ability = if RarityConfig.GetRank(rarity) >= RarityConfig.GetRank("Rare")
			then archetypeInfo.Ability
			else nil,
		AllowModifiers = RarityConfig.GetRank(rarity) >= RarityConfig.GetRank("Rare"),
	})
end

weapon("rusted_shortsword", "Rusted Shortsword", "Sword", "Common",
	{ Damage = 8, AttackSpeed = 1.0, CritChance = 3 },
	"Someone's first blade. Then someone else's.",
	Color3.fromRGB(132, 126, 112), Enum.Material.Metal, 1)

weapon("cracked_bow", "Cracked Bow", "Bow", "Common",
	{ Damage = 6, AttackSpeed = 1.15, CritChance = 5 },
	"The string is newer than the wood.",
	Color3.fromRGB(120, 92, 62), Enum.Material.Wood, 1)

weapon("iron_sword", "Iron Sword", "Sword", "Uncommon",
	{ Damage = 14, AttackSpeed = 1.0, CritChance = 4 },
	"Honest steel, honestly sharpened.",
	Color3.fromRGB(178, 182, 190), Enum.Material.Metal, 3)

weapon("hunters_bow", "Hunter's Bow", "Bow", "Uncommon",
	{ Damage = 11, AttackSpeed = 1.2, CritChance = 7 },
	"Built for patience.",
	Color3.fromRGB(140, 106, 68), Enum.Material.Wood, 3)

weapon("steel_greatsword", "Steel Greatsword", "Greatsword", "Rare",
	{ Damage = 30, AttackSpeed = 0.65, CritChance = 4, CritDamage = 10 },
	"Slow. Decisive.",
	Color3.fromRGB(160, 168, 182), Enum.Material.Metal, 8)

weapon("swift_dagger", "Swift Dagger", "Dagger", "Rare",
	{ Damage = 12, AttackSpeed = 2.0, CritChance = 12, CritDamage = 15 },
	"Faster than it looks, which is already fast.",
	Color3.fromRGB(196, 200, 208), Enum.Material.Metal, 8)

weapon("emberstaff", "Emberstaff", "Staff", "Epic",
	{ Damage = 34, AttackSpeed = 0.9, CritChance = 8, CritDamage = 20 },
	"Warm to the touch. Warmer to everything else.",
	Color3.fromRGB(226, 118, 54), Enum.Material.Neon, 15)

weapon("stormblade", "Stormblade", "Sword", "Legendary",
	{ Damage = 62, AttackSpeed = 1.15, CritChance = 10, CritDamage = 25 },
	"The air complains when you swing it.",
	Color3.fromRGB(120, 190, 255), Enum.Material.Neon, 22)

weapon("dawnbreaker", "Dawnbreaker", "Greatsword", "Mythic",
	{ Damage = 118, AttackSpeed = 0.7, CritChance = 9, CritDamage = 40 },
	"Forged at the exact moment a night ended.",
	Color3.fromRGB(255, 206, 120), Enum.Material.Neon, 32)

weapon("voidfang", "Voidfang", "Dagger", "Divine",
	{ Damage = 96, AttackSpeed = 2.2, CritChance = 25, CritDamage = 60 },
	"It does not reflect light. It declines to.",
	Color3.fromRGB(78, 44, 128), Enum.Material.Neon, 42)

weapon("celestial_voidblade", "Celestial Voidblade", "Sword", "Celestial",
	{ Damage = 240, AttackSpeed = 1.3, CritChance = 20, CritDamage = 80, Luck = 0.05 },
	"One in a hundred thousand. You already knew that.",
	Color3.fromRGB(150, 244, 255), Enum.Material.Neon, 55)

--========================================================================
-- Armour — five sets across four slots
--========================================================================

type ArmourTier = {
	Prefix: string,
	Rarity: string,
	Level: number,
	Color: Color3,
	Material: Enum.Material,
	-- Per-slot { Defense, Health, MoveSpeed? }
	Helmet: { number },
	Chest: { number },
	Legs: { number },
	Boots: { number },
}

local ARMOUR_TIERS: { ArmourTier } = {
	{
		Prefix = "Tattered", Rarity = "Common", Level = 1,
		Color = Color3.fromRGB(146, 136, 118), Material = Enum.Material.Fabric,
		Helmet = { 2, 5 }, Chest = { 4, 12 }, Legs = { 3, 8 }, Boots = { 2, 5, 0 },
	},
	{
		Prefix = "Leather", Rarity = "Uncommon", Level = 4,
		Color = Color3.fromRGB(126, 88, 56), Material = Enum.Material.Fabric,
		Helmet = { 5, 12 }, Chest = { 9, 26 }, Legs = { 7, 18 }, Boots = { 4, 10, 1 },
	},
	{
		Prefix = "Iron", Rarity = "Rare", Level = 9,
		Color = Color3.fromRGB(168, 174, 186), Material = Enum.Material.Metal,
		Helmet = { 11, 28 }, Chest = { 20, 60 }, Legs = { 15, 42 }, Boots = { 9, 24, 2 },
	},
	{
		Prefix = "Runed", Rarity = "Epic", Level = 16,
		Color = Color3.fromRGB(138, 96, 208), Material = Enum.Material.Metal,
		Helmet = { 22, 60 }, Chest = { 40, 130 }, Legs = { 30, 90 }, Boots = { 18, 50, 3 },
	},
	{
		Prefix = "Dragonscale", Rarity = "Legendary", Level = 24,
		Color = Color3.fromRGB(210, 96, 62), Material = Enum.Material.Metal,
		Helmet = { 44, 130 }, Chest = { 80, 280 }, Legs = { 60, 195 }, Boots = { 36, 110, 4 },
	},
}

local ARMOUR_SLOTS = {
	{ Slot = "Helmet", Noun = "Helm", Size = Vector3.new(2, 1.2, 2) },
	{ Slot = "Chest", Noun = "Chestplate", Size = Vector3.new(2, 2, 1) },
	{ Slot = "Legs", Noun = "Greaves", Size = Vector3.new(1, 2, 1) },
	{ Slot = "Boots", Noun = "Boots", Size = Vector3.new(1, 1, 1) },
}

for _, tier in ipairs(ARMOUR_TIERS) do
	for _, slotInfo in ipairs(ARMOUR_SLOTS) do
		local values = (tier :: any)[slotInfo.Slot] :: { number }

		local stats: Stats = {
			Defense = values[1],
			Health = values[2],
		}
		if values[3] and values[3] > 0 then
			stats.MoveSpeed = values[3]
		end

		define({
			Id = string.lower(tier.Prefix) .. "_" .. string.lower(slotInfo.Slot),
			Name = tier.Prefix .. " " .. slotInfo.Noun,
			Slot = slotInfo.Slot,
			Rarity = tier.Rarity,
			Description = string.format("%s-grade protection.", tier.Prefix),
			BaseStats = stats,
			LevelRequirement = tier.Level,
			SellValue = SELL_BY_RARITY[tier.Rarity],
			Appearance = { Color = tier.Color, Material = tier.Material, Size = slotInfo.Size },
			AllowModifiers = RarityConfig.GetRank(tier.Rarity) >= RarityConfig.GetRank("Rare"),
		})
	end
end

--========================================================================
-- Accessories and gear
--========================================================================

local function trinket(
	id: string, name: string, slot: string, rarity: string,
	stats: Stats, description: string, color: Color3, level: number
)
	define({
		Id = id,
		Name = name,
		Slot = slot,
		Rarity = rarity,
		Description = description,
		BaseStats = stats,
		LevelRequirement = level,
		SellValue = SELL_BY_RARITY[rarity],
		Appearance = { Color = color, Material = Enum.Material.Neon, Size = Vector3.new(0.8, 0.8, 0.8) },
		AllowModifiers = RarityConfig.GetRank(rarity) >= RarityConfig.GetRank("Rare"),
	})
end

trinket("copper_ring", "Copper Ring", "Accessory", "Common",
	{ Luck = 0.01, CritChance = 1 }, "Turns your finger green. Slightly lucky.",
	Color3.fromRGB(196, 132, 80), 1)

trinket("lucky_charm", "Lucky Charm", "Accessory", "Uncommon",
	{ Luck = 0.05 }, "Statistically, it helps.",
	Color3.fromRGB(120, 220, 140), 5)

trinket("ruby_pendant", "Ruby Pendant", "Accessory", "Rare",
	{ Damage = 8, Health = 30 }, "Warm against the chest.",
	Color3.fromRGB(228, 72, 88), 10)

trinket("band_of_focus", "Band of Focus", "Accessory", "Epic",
	{ CritChance = 8, CritDamage = 15 }, "You notice openings you would have missed.",
	Color3.fromRGB(132, 168, 255), 18)

trinket("fortunes_eye", "Fortune's Eye", "Accessory", "Legendary",
	{ Luck = 0.15, CritChance = 6 }, "It is looking at something you cannot see.",
	Color3.fromRGB(255, 214, 96), 26)

trinket("travelers_pack", "Traveler's Pack", "Gear", "Common",
	{ Health = 10 }, "Room for exactly one more thing.",
	Color3.fromRGB(150, 122, 84), 1)

trinket("warding_totem", "Warding Totem", "Gear", "Rare",
	{ Defense = 15 }, "Hums when something is nearby.",
	Color3.fromRGB(110, 200, 190), 10)

trinket("phoenix_ember", "Phoenix Ember", "Gear", "Epic",
	{ Health = 120, Defense = 10 }, "Still warm. Always still warm.",
	Color3.fromRGB(255, 138, 72), 18)

--========================================================================
-- Lookups
--========================================================================

ItemConfig.Templates = templates

--[[ Items grouped by rarity, built once at require time for the roller. ]]
local byRarity: { [string]: { string } } = {}
for _, rarityId in ipairs(RarityConfig.Order) do
	byRarity[rarityId] = {}
end

for id, template in pairs(templates) do
	table.insert(byRarity[template.Rarity], id)
end

-- Sorted so the roll is reproducible given the same RNG seed. pairs() order is
-- not stable across runs, which would make roll outcomes untestable.
for _, list in pairs(byRarity) do
	table.sort(list)
end

ItemConfig.ByRarity = byRarity

function ItemConfig.Get(itemId: string): ItemTemplate?
	return templates[itemId]
end

--[[ Item ids of a given rarity. Empty table if none — never nil. ]]
function ItemConfig.GetByRarity(rarityId: string): { string }
	return byRarity[rarityId] or {}
end

function ItemConfig.Count(): number
	local count = 0
	for _ in pairs(templates) do
		count += 1
	end
	return count
end

--[[
	Fails at require time if a rarity has no items, because the roller would
	otherwise roll that rarity and have nothing to award.
]]
local function validate()
	for _, rarityId in ipairs(RarityConfig.Order) do
		assert(
			#byRarity[rarityId] > 0,
			string.format("ItemConfig: rarity '%s' has no items — the roller could not award anything", rarityId)
		)
	end

	for id, template in pairs(templates) do
		assert(table.find(ItemConfig.Slots, template.Slot), string.format("ItemConfig: '%s' has unknown slot '%s'", id, template.Slot))
		assert(template.SellValue > 0, string.format("ItemConfig: '%s' has no sell value", id))
	end
end

validate()

return ItemConfig
