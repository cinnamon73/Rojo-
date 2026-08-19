--!strict
--[[
	MinionConfig — the friendly units Necromancer and King summon.

	Shaped like EnemyConfig.EnemyDefinition on purpose, so EnemyService.BuildRig
	can construct them. A summoned skeleton is the same welded-primitive problem
	as a goblin; giving minions their own rig builder would mean two of them
	drifting apart the first time either is touched.

	The reward and respawn fields are inert here — nothing pays out for a minion
	and they never respawn — but they are kept so the shape stays compatible. If
	a definition here stops matching EnemyDefinition, BuildRig breaks silently.

	Minions are DELIBERATELY weaker than they look. Six skeletons that each hit
	as hard as the summoner would make the Necromancer the only class worth
	playing; they are a second front and a damage sponge, not a damage upgrade.
]]

local MinionConfig = {}

local definitions = {
	Skeleton = {
		Id = "Skeleton",
		Name = "Skeleton",
		Level = 1,
		Health = 70,
		Damage = 9,
		Defense = 2,
		WalkSpeed = 15,
		-- How far it will look for something to fight.
		AggroRange = 70,
		-- How far it will stray from the summoner before returning.
		LeashRange = 90,
		AttackRange = 9,
		AttackCooldown = 1.1,
		XPReward = 0,
		CoinReward = 0,
		LootChance = 0,
		RespawnSeconds = 0,
		Appearance = {
			Build = "Biped",
			BodyColor = Color3.fromRGB(226, 226, 214),
			AccentColor = Color3.fromRGB(150, 120, 200),
			Material = Enum.Material.Slate,
			Scale = 0.95,
		},
	},

	Knight = {
		Id = "Knight",
		Name = "Royal Knight",
		Level = 1,
		Health = 130,
		Damage = 13,
		Defense = 6,
		WalkSpeed = 15,
		AggroRange = 70,
		LeashRange = 90,
		AttackRange = 10,
		AttackCooldown = 1.2,
		XPReward = 0,
		CoinReward = 0,
		LootChance = 0,
		RespawnSeconds = 0,
		Appearance = {
			Build = "Biped",
			BodyColor = Color3.fromRGB(176, 182, 196),
			AccentColor = Color3.fromRGB(244, 214, 96),
			Material = Enum.Material.Metal,
			Scale = 1.05,
		},
	},

	RoyalArcher = {
		Id = "RoyalArcher",
		Name = "Royal Archer",
		Level = 1,
		Health = 85,
		Damage = 11,
		Defense = 2,
		WalkSpeed = 16,
		-- Longer reach is the whole point of the archers in the King's guard;
		-- they hold behind the knights rather than joining the line.
		AggroRange = 95,
		LeashRange = 110,
		AttackRange = 70,
		AttackCooldown = 1.5,
		XPReward = 0,
		CoinReward = 0,
		LootChance = 0,
		RespawnSeconds = 0,
		Appearance = {
			Build = "Biped",
			BodyColor = Color3.fromRGB(126, 140, 168),
			AccentColor = Color3.fromRGB(244, 214, 96),
			Material = Enum.Material.Fabric,
			Scale = 1.0,
		},
	},
}

MinionConfig.Definitions = definitions

--[[
	What each summoning ability produces.

	A list rather than a count-per-type so composition is explicit and ordering
	is stable: the King's knights spawn before his archers, which puts the
	melee ring outside the ranged ones.
]]
MinionConfig.Squads = {
	RaiseSkeletons = {
		"Skeleton", "Skeleton", "Skeleton", "Skeleton", "Skeleton", "Skeleton",
	},
	RoyalGuard = {
		"Knight", "Knight", "Knight", "Knight", "Knight", "Knight",
		"RoyalArcher", "RoyalArcher", "RoyalArcher",
	},
}

--[[ Radius around the summoner that units are placed in. ]]
MinionConfig.SpawnRadius = 9

function MinionConfig.Get(minionId: string): any?
	return definitions[minionId]
end

function MinionConfig.GetSquad(abilityId: string): { string }?
	return MinionConfig.Squads[abilityId]
end

return MinionConfig
