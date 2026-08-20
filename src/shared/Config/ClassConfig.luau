--!strict
--[[
	ClassConfig — the eight defender classes.

	Classes replaced rolled gear as the source of a player's power. You pick one
	and it decides everything: stats, weapon, reach, and the one ability you
	press. There is no equipment layer any more — a class IS the loadout.

	Tiers are a LABEL, not a gate. There is no levelling: every class is free
	from the first join except the King, which is the one paid class. The tier
	number describes complexity — a Tier 1 Archer is meant to stay viable next
	to a Tier 3 Necromancer; higher tiers trade raw numbers for abilities that
	change what the team can do.

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

local WeaponConfig = require(script.Parent.WeaponConfig)

local ClassConfig = {}

--[[ Abilities belong to weapons now. Re-exported so older type references
     (ClassConfig.Ability) still resolve to the one definition. ]]
export type Ability = WeaponConfig.Ability

export type ClassDefinition = {
	Id: string,
	Name: string,
	Tier: number,
	-- Free text, shown on the select screen: "Ranged", "Melee", "Summoner"...
	Role: string,
	Description: string,

	--[[ What the BODY is, not what it does. Damage, attack speed, reach, crit,
	     the moveset and the ability all live on the weapon now
	     (see WeaponConfig) — so picking up a different item genuinely changes
	     how the class fights. ]]
	Health: number,
	MoveSpeed: number,

	-- The item this class spawns holding. Everything offensive comes from it.
	StartingWeapon: string,

	-- Banner and mannequin outfit colour on the class select screen.
	ThemeColor: Color3,

	-- King only. Everything else is free: there is no levelling and no unlock
	-- ladder — tiers are a label describing complexity, not a gate.
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
		StartingWeapon = "Bow",
		MoveSpeed = 16,
		ThemeColor = Color3.fromRGB(96, 164, 96)
	},

	Swordsman = {
		Id = "Swordsman",
		Name = "Swordsman",
		Tier = 1,
		Role = "Melee",
		Description = "Holds the line. The spin clears everything pressed against you.",
		Health = 145,
		StartingWeapon = "Sword",
		MoveSpeed = 16,
		ThemeColor = Color3.fromRGB(108, 132, 172)
	},

	--------------------------------------------------------------- tier 2
	Berserker = {
		Id = "Berserker",
		Name = "Berserker",
		Tier = 2,
		Role = "Melee",
		Description = "Walks into the middle of it. For ten seconds, nothing can put him down.",
		Health = 170,
		StartingWeapon = "Greataxe",
		MoveSpeed = 17,
		ThemeColor = Color3.fromRGB(178, 84, 64)
	},

	Musketeer = {
		Id = "Musketeer",
		Name = "Musketeer",
		Tier = 2,
		Role = "Ranged",
		Description = "Trades fire rate for reach and a grenade that is almost always ready.",
		Health = 110,
		StartingWeapon = "Musket",
		MoveSpeed = 16,
		ThemeColor = Color3.fromRGB(140, 108, 72)
	},

	Assassin = {
		Id = "Assassin",
		Name = "Assassin",
		Tier = 2,
		Role = "Boss killer",
		Description = "Poor against crowds, brutal against anything large. Vanishes to reposition.",
		Health = 95,
		StartingWeapon = "Dagger",
		MoveSpeed = 19,
		ThemeColor = Color3.fromRGB(84, 88, 108)
	},

	--------------------------------------------------------------- tier 3
	Paladin = {
		Id = "Paladin",
		Name = "Paladin",
		Tier = 3,
		Role = "Spellcaster / Melee",
		Description = "Plants a shield the horde has to break. Allies pass through it freely.",
		Health = 190,
		StartingWeapon = "PaladinBlade",
		MoveSpeed = 15,
		ThemeColor = Color3.fromRGB(214, 184, 100)
	},

	Necromancer = {
		Id = "Necromancer",
		Name = "Necromancer",
		Tier = 3,
		Role = "Summoner",
		Description = "Weak alone. Raises six skeletons to hold a second front.",
		Health = 105,
		StartingWeapon = "NecroStaff",
		MoveSpeed = 15,
		ThemeColor = Color3.fromRGB(122, 86, 168)
	},

	--------------------------------------------------------------- paid
	King = {
		Id = "King",
		Name = "King",
		Tier = 4,
		Role = "Summoner / Melee",
		Description = "Fights, and brings a household guard with him.",
		Health = 175,
		StartingWeapon = "RoyalBlade",
		MoveSpeed = 16,
		ThemeColor = Color3.fromRGB(196, 156, 60),
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
	Whether this class may be played. Only the King has a gate: the gamepass.

	Returns (allowed, reason). The reason is a machine-readable string the UI
	turns into text — the server never writes player-facing copy.
]]
function ClassConfig.IsUnlocked(definition: ClassDefinition, ownsGamepass: boolean?): (boolean, string?)
	if definition.RequiresGamepass and not ownsGamepass then
		return false, "GamepassRequired"
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
