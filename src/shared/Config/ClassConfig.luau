--!strict
--[[
	ClassConfig — the eight defender classes.

	Classes replaced rolled gear as the source of a player's power. You pick one
	and it decides everything: stats, weapon, reach, and the one ability you
	press. There is no equipment layer any more — a class IS the loadout.

	Tiers are unlock gates, not power bands in a strict sense. A Tier 1 Archer is
	meant to stay viable next to a Tier 3 Necromancer; the higher tiers trade raw
	numbers for abilities that change what the team can do (an unkillable body, a
	wall enemies must chew through, a second front made of skeletons).

	COOLDOWN INTENT
	---------------
	Cooldowns were given as low/medium/high. Concrete values below, and one
	deliberate departure worth arguing with:

	Berserker's undying was specified as a MEDIUM cooldown. Ten seconds of
	immortality on a medium timer is over 50% uptime — it stops reading as an
	ultimate and becomes the class's resting state, which also removes every
	reason for the team to protect the front line. It is set to 45s here. If you
	want it back on a medium timer, cut the duration to about 4s instead.

	BALANCE IS UNPROVEN. These numbers have never been played. They are a
	starting point chosen to be internally consistent, not a tuned game.
]]

local ClassConfig = {}

export type Ability = {
	Id: string,
	Name: string,
	Description: string,
	Cooldown: number,
	-- Seconds the effect persists. 0 for instant abilities like the grenade.
	Duration: number,
}

export type ClassDefinition = {
	Id: string,
	Name: string,
	Tier: number,
	-- Free text, shown on the select screen: "Ranged", "Melee", "Summoner"...
	Role: string,
	Description: string,

	-- Base stats. These are the whole of a player's power now.
	Health: number,
	Damage: number,
	AttackSpeed: number,
	CritChance: number,
	CritDamage: number,
	MoveSpeed: number,
	-- Reach in studs. Ranged classes are the reason this is per-class.
	AttackRange: number,

	-- Drives WeaponModels and the swing arc.
	WeaponArchetype: string,
	WeaponColor: Color3,
	WeaponMaterial: Enum.Material,

	Ability: Ability,

	--[[
		Unlock gate. Tier 1 is available immediately; higher tiers open on
		account level. King ignores this and checks the gamepass instead.
	]]
	UnlockLevel: number,
	RequiresGamepass: string?,
}

--========================================================================
-- The roster
--========================================================================

local definitions: { [string]: ClassDefinition } = {
	--------------------------------------------------------------- tier 1
	Archer = {
		Id = "Archer",
		Name = "Archer",
		Tier = 1,
		Role = "Ranged",
		Description = "Steady damage from the wall. Rapidfire removes the reload entirely.",
		Health = 100,
		Damage = 14,
		AttackSpeed = 1.25,
		CritChance = 10,
		CritDamage = 60,
		MoveSpeed = 16,
		AttackRange = 90,
		WeaponArchetype = "Bow",
		WeaponColor = Color3.fromRGB(126, 94, 58),
		WeaponMaterial = Enum.Material.Wood,
		Ability = {
			Id = "Rapidfire",
			Name = "Rapidfire",
			Description = "No draw time. Fire continuously for the duration.",
			Cooldown = 18,
			Duration = 6,
		},
		UnlockLevel = 1,
	},

	Swordsman = {
		Id = "Swordsman",
		Name = "Swordsman",
		Tier = 1,
		Role = "Melee",
		Description = "Holds the line. The spin clears everything pressed against you.",
		Health = 145,
		Damage = 18,
		AttackSpeed = 1.0,
		CritChance = 8,
		CritDamage = 55,
		MoveSpeed = 16,
		AttackRange = 12,
		WeaponArchetype = "Sword",
		WeaponColor = Color3.fromRGB(178, 184, 196),
		WeaponMaterial = Enum.Material.Metal,
		Ability = {
			Id = "SpinningSlash",
			Name = "Spinning Slash",
			Description = "Whirl in place, striking every enemy within reach.",
			Cooldown = 14,
			Duration = 3,
		},
		UnlockLevel = 1,
	},

	--------------------------------------------------------------- tier 2
	Berserker = {
		Id = "Berserker",
		Name = "Berserker",
		Tier = 2,
		Role = "Melee",
		Description = "Walks into the middle of it. For ten seconds, nothing can put him down.",
		Health = 170,
		Damage = 22,
		AttackSpeed = 1.1,
		CritChance = 12,
		CritDamage = 70,
		MoveSpeed = 17,
		AttackRange = 13,
		WeaponArchetype = "Greatsword",
		WeaponColor = Color3.fromRGB(148, 84, 68),
		WeaponMaterial = Enum.Material.Metal,
		Ability = {
			Id = "Undying",
			Name = "Undying",
			Description = "Cannot drop below 1 health for the duration.",
			-- See the header: deliberately longer than the brief's "medium".
			Cooldown = 45,
			Duration = 10,
		},
		UnlockLevel = 5,
	},

	Musketeer = {
		Id = "Musketeer",
		Name = "Musketeer",
		Tier = 2,
		Role = "Ranged",
		Description = "Trades fire rate for reach and a grenade that is almost always ready.",
		Health = 110,
		Damage = 26,
		AttackSpeed = 0.7,
		CritChance = 10,
		CritDamage = 65,
		MoveSpeed = 16,
		AttackRange = 85,
		WeaponArchetype = "Staff",
		WeaponColor = Color3.fromRGB(92, 82, 74),
		WeaponMaterial = Enum.Material.Wood,
		Ability = {
			Id = "Grenade",
			Name = "Grenade",
			Description = "Thrown explosive. Damages everything in a radius where it lands.",
			Cooldown = 9,
			Duration = 0,
		},
		UnlockLevel = 8,
	},

	Assassin = {
		Id = "Assassin",
		Name = "Assassin",
		Tier = 2,
		Role = "Boss killer",
		Description = "Poor against crowds, brutal against anything large. Vanishes to reposition.",
		Health = 95,
		Damage = 30,
		AttackSpeed = 1.4,
		CritChance = 25,
		CritDamage = 110,
		MoveSpeed = 19,
		AttackRange = 11,
		WeaponArchetype = "Dagger",
		WeaponColor = Color3.fromRGB(64, 68, 82),
		WeaponMaterial = Enum.Material.Metal,
		Ability = {
			Id = "Vanish",
			Name = "Vanish",
			Description = "Invisible to enemies. Attacking does not break it.",
			Cooldown = 12,
			Duration = 5,
		},
		UnlockLevel = 12,
	},

	--------------------------------------------------------------- tier 3
	Paladin = {
		Id = "Paladin",
		Name = "Paladin",
		Tier = 3,
		Role = "Spellcaster / Melee",
		Description = "Plants a shield the horde has to break. Allies pass through it freely.",
		Health = 190,
		Damage = 19,
		AttackSpeed = 0.95,
		CritChance = 8,
		CritDamage = 55,
		MoveSpeed = 15,
		AttackRange = 13,
		WeaponArchetype = "Sword",
		WeaponColor = Color3.fromRGB(226, 200, 128),
		WeaponMaterial = Enum.Material.Metal,
		Ability = {
			Id = "Aegis",
			Name = "Aegis",
			Description = "A bubble enemies must destroy to enter. Players walk through it.",
			Cooldown = 40,
			Duration = 12,
		},
		UnlockLevel = 18,
	},

	Necromancer = {
		Id = "Necromancer",
		Name = "Necromancer",
		Tier = 3,
		Role = "Summoner",
		Description = "Weak alone. Raises six skeletons to hold a second front.",
		Health = 105,
		Damage = 16,
		AttackSpeed = 0.85,
		CritChance = 10,
		CritDamage = 60,
		MoveSpeed = 15,
		AttackRange = 70,
		WeaponArchetype = "Staff",
		WeaponColor = Color3.fromRGB(108, 76, 148),
		WeaponMaterial = Enum.Material.Neon,
		Ability = {
			Id = "RaiseSkeletons",
			Name = "Skeleton Army",
			Description = "Six skeletons fight for you until they fall or the duration ends.",
			Cooldown = 75,
			Duration = 30,
		},
		UnlockLevel = 22,
	},

	--------------------------------------------------------------- paid
	King = {
		Id = "King",
		Name = "King",
		Tier = 4,
		Role = "Summoner / Melee",
		Description = "Fights, and brings a household guard with him.",
		Health = 175,
		Damage = 21,
		AttackSpeed = 1.0,
		CritChance = 12,
		CritDamage = 70,
		MoveSpeed = 16,
		AttackRange = 13,
		WeaponArchetype = "Sword",
		WeaponColor = Color3.fromRGB(244, 214, 96),
		WeaponMaterial = Enum.Material.Metal,
		Ability = {
			Id = "RoyalGuard",
			Name = "Royal Guard",
			Description = "Six knights and three archers answer the call.",
			Cooldown = 90,
			Duration = 45,
		},
		-- Ignored: the gamepass is the gate. Kept at 1 so a future decision to
		-- also require a level is a one-line change.
		UnlockLevel = 1,
		RequiresGamepass = "King",
	},
}

--========================================================================
-- Lookups
--========================================================================

ClassConfig.Definitions = definitions

--[[ Display order on the select screen: by tier, then by name. ]]
ClassConfig.Order = {
	"Archer",
	"Swordsman",
	"Berserker",
	"Musketeer",
	"Assassin",
	"Paladin",
	"Necromancer",
	"King",
}

--[[ What a player starts as, and what they fall back to if a save is broken. ]]
ClassConfig.Default = "Swordsman"

function ClassConfig.Get(classId: any): ClassDefinition?
	if type(classId) ~= "string" then
		return nil
	end
	return definitions[classId]
end

--[[
	Whether `profile` may play `classId`.

	Returns (allowed, reason). The reason is a machine-readable string the UI
	turns into text, not a sentence — the server never writes player-facing
	copy.
]]
function ClassConfig.IsUnlocked(definition: ClassDefinition, profile: any, ownsGamepass: boolean?): (boolean, string?)
	if definition.RequiresGamepass then
		if ownsGamepass then
			return true, nil
		end
		return false, "GamepassRequired"
	end

	local level = (profile and profile.Progression and profile.Progression.Level) or 1
	if level < definition.UnlockLevel then
		return false, "LevelTooLow"
	end

	return true, nil
end

function ClassConfig.Count(): number
	local count = 0
	for _ in pairs(definitions) do
		count += 1
	end
	return count
end

return ClassConfig
