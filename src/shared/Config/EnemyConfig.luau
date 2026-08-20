--!strict
--[[
	EnemyConfig — every enemy in the game, as data.

	Adding an enemy means adding an entry here and placing a spawn marker with
	a matching EnemyId attribute. No new scripts, no new models required — the
	Build field describes a placeholder rig that EnemyService assembles, and
	swapping in a real model later means setting ModelId instead.

	Balance intent for Verdant Fields: a level-1 player in starter gear kills a
	Slime in a handful of hits, loses to a Goblin Warrior, and needs real
	equipment before the Goblin King is survivable. Numbers below are tuned
	against GameConfig.Combat baselines (5 base damage, 100 base health).
]]

export type EnemyAppearance = {
	-- "Blob" | "Biped" | "Quadruped" — which placeholder rig to assemble.
	Build: string,
	BodyColor: Color3,
	AccentColor: Color3,
	Material: Enum.Material,
	-- Overall scale multiplier applied to the rig.
	Scale: number,
	-- Set to use a real model from ServerStorage instead of a placeholder.
	ModelId: string?,
	--[[
		Name of an articulated rig in `Modules/EnemyRigs`. When set, that rig is
		built INSTEAD of the `Build` placeholder above — jointed with Motor6Ds
		so it can be animated, rather than welded rigid.

		`Build` is still read as the fallback, so an enemy without a Rig keeps
		its old body exactly as it was.
	]]
	Rig: string?,
}

export type EnemyDefinition = {
	Id: string,
	Name: string,
	Level: number,

	Health: number,
	Damage: number,
	Defense: number,

	WalkSpeed: number,
	AggroRange: number,
	-- Stops chasing beyond this; prevents a train of enemies across the map.
	LeashRange: number,
	AttackRange: number,
	AttackCooldown: number,

	XPReward: number,
	CoinReward: number,
	-- Chance this enemy drops an item roll on death, 0-1.
	LootChance: number,

	RespawnSeconds: number,
	Appearance: EnemyAppearance,
	IsBoss: boolean,
}

local EnemyConfig = {}

local definitions: { [string]: EnemyDefinition } = {}

local function define(definition: EnemyDefinition)
	assert(not definitions[definition.Id], "EnemyConfig: duplicate enemy id " .. definition.Id)
	definitions[definition.Id] = definition
end

--========================================================================
-- Verdant Fields
--========================================================================

define({
	Id = "Slime",
	Name = "Slime",
	Level = 1,
	Health = 40,
	Damage = 4,
	Defense = 0,
	WalkSpeed = 7,
	AggroRange = 26,
	LeashRange = 70,
	AttackRange = 6,
	AttackCooldown = 2.0,
	XPReward = 12,
	CoinReward = 8,
	LootChance = 0.05,
	RespawnSeconds = 8,
	Appearance = {
		Build = "Blob",
		BodyColor = Color3.fromRGB(120, 210, 140),
		AccentColor = Color3.fromRGB(168, 240, 184),
		Material = Enum.Material.SmoothPlastic,
		Scale = 1.0,
	},
	IsBoss = false,
})

define({
	Id = "Goblin",
	Name = "Goblin",
	Level = 3,
	Health = 85,
	Damage = 9,
	Defense = 2,
	WalkSpeed = 12,
	AggroRange = 34,
	LeashRange = 90,
	AttackRange = 6.5,
	AttackCooldown = 1.6,
	XPReward = 26,
	CoinReward = 18,
	LootChance = 0.10,
	RespawnSeconds = 12,
	Appearance = {
		-- Articulated: jointed body, club, and a walk/attack/idle set.
		-- `Build` is kept only as the fallback if the rig ever fails to load.
		Rig = "Goblin",
		Build = "Biped",
		BodyColor = Color3.fromRGB(118, 158, 92),
		AccentColor = Color3.fromRGB(84, 66, 48),
		Material = Enum.Material.SmoothPlastic,
		Scale = 0.85,
	},
	IsBoss = false,
})

define({
	Id = "Wolf",
	Name = "Wolf",
	Level = 5,
	Health = 120,
	Damage = 14,
	Defense = 3,
	-- Faster than the player's base 16 so it closes distance, but slow enough
	-- that movement speed gear is a real answer to it.
	WalkSpeed = 18,
	AggroRange = 42,
	LeashRange = 110,
	AttackRange = 7,
	AttackCooldown = 1.2,
	XPReward = 44,
	CoinReward = 30,
	LootChance = 0.14,
	RespawnSeconds = 16,
	Appearance = {
		Build = "Quadruped",
		BodyColor = Color3.fromRGB(112, 112, 122),
		AccentColor = Color3.fromRGB(72, 72, 82),
		Material = Enum.Material.SmoothPlastic,
		Scale = 1.0,
	},
	IsBoss = false,
})

--[[
	Skeleton — the barrow camp in the south-west of Zone 1.

	Slots between Wolf (5) and GoblinWarrior (8). Slower than a wolf and it
	hits harder, but it has almost no defense: the trade is that you can kite
	it, and it punishes you for standing still in a camp full of them.
]]
define({
	Id = "Skeleton",
	Name = "Skeleton",
	Level = 6,
	Health = 150,
	Damage = 18,
	Defense = 1,
	WalkSpeed = 11,
	AggroRange = 36,
	LeashRange = 95,
	AttackRange = 7,
	AttackCooldown = 1.5,
	XPReward = 58,
	CoinReward = 40,
	LootChance = 0.16,
	RespawnSeconds = 18,
	Appearance = {
		Build = "Biped",
		BodyColor = Color3.fromRGB(226, 222, 206),
		AccentColor = Color3.fromRGB(84, 80, 74),
		Material = Enum.Material.SmoothPlastic,
		Scale = 0.95,
	},
	IsBoss = false,
})

define({
	Id = "GoblinWarrior",
	Name = "Goblin Warrior",
	Level = 8,
	Health = 240,
	Damage = 22,
	Defense = 8,
	WalkSpeed = 13,
	AggroRange = 38,
	LeashRange = 100,
	AttackRange = 7.5,
	AttackCooldown = 1.8,
	XPReward = 90,
	CoinReward = 65,
	LootChance = 0.22,
	RespawnSeconds = 25,
	Appearance = {
		Build = "Biped",
		BodyColor = Color3.fromRGB(96, 134, 78),
		AccentColor = Color3.fromRGB(158, 120, 60),
		Material = Enum.Material.Metal,
		Scale = 1.05,
	},
	IsBoss = false,
})

define({
	Id = "EliteGoblin",
	Name = "Elite Goblin",
	Level = 12,
	Health = 480,
	Damage = 34,
	Defense = 14,
	WalkSpeed = 14,
	AggroRange = 44,
	LeashRange = 120,
	AttackRange = 8,
	AttackCooldown = 1.5,
	XPReward = 180,
	CoinReward = 140,
	LootChance = 0.35,
	RespawnSeconds = 45,
	Appearance = {
		Build = "Biped",
		BodyColor = Color3.fromRGB(78, 112, 64),
		AccentColor = Color3.fromRGB(212, 168, 76),
		Material = Enum.Material.Metal,
		Scale = 1.25,
	},
	IsBoss = false,
})

--========================================================================
-- Zone 1 boss
--========================================================================

define({
	Id = "GoblinKing",
	Name = "Goblin King",
	Level = 15,
	Health = 3200,
	Damage = 48,
	Defense = 22,
	WalkSpeed = 12,
	AggroRange = 60,
	LeashRange = 200,
	AttackRange = 10,
	AttackCooldown = 2.2,
	XPReward = 1400,
	CoinReward = 1200,
	LootChance = 1.0,
	RespawnSeconds = 120,
	Appearance = {
		Build = "Biped",
		BodyColor = Color3.fromRGB(64, 104, 56),
		AccentColor = Color3.fromRGB(226, 184, 84),
		Material = Enum.Material.Metal,
		Scale = 2.2,
	},
	IsBoss = true,
})

--========================================================================
-- Lookups
--========================================================================

EnemyConfig.Definitions = definitions

function EnemyConfig.Get(enemyId: string): EnemyDefinition?
	return definitions[enemyId]
end

function EnemyConfig.Count(): number
	local count = 0
	for _ in pairs(definitions) do
		count += 1
	end
	return count
end

--[[
	Damage an attack of `rawDamage` deals to this enemy.

	Defense is a flat reduction with a floor, rather than a percentage: flat
	reduction makes low-damage weapons feel genuinely bad against armoured
	enemies, which is the point of upgrading. The floor keeps a badly
	under-geared player from dealing literally nothing and being unable to
	learn that they are under-geared.
]]
function EnemyConfig.ApplyDefense(rawDamage: number, defense: number): number
	return math.max(rawDamage - defense, math.max(1, rawDamage * 0.1))
end

return EnemyConfig
