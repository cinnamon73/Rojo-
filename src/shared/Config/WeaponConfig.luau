--!strict
--[[
	WeaponConfig — the items, and everything an item carries.

	THE ITEM HOLDS THE MOVESET, NOT THE CLASS. A class is a body and an
	identity: how much health it has, how fast it walks, what its banner looks
	like. Everything about HOW IT FIGHTS travels with the weapon in its hands —
	the combo animations, the special ability, reach, damage, crit.

	That split is what makes weapons real items rather than class decoration.
	Hand the Berserker a bow and he shoots; hand the Archer a greataxe and she
	swings the two-hit cleave. Nothing about the class has to know.

	WHERE THINGS LIVE NOW
	  Weapon : Combo (moveset), Ability, Damage, AttackSpeed, AttackRange,
	           Crit, Appearance, Grip, Offhand
	  Class  : Health, MoveSpeed, name/role/description, ThemeColor,
	           StartingWeapon

	Combo is the moveset: one animation id per step, and the LENGTH of the list
	is the combo length. A two-entry list is a two-hit weapon. Nothing anywhere
	hardcodes "3".

	MeshId 0 means "no mesh uploaded yet" and WeaponModels falls back to the
	part-built model, so a missing upload degrades to the old look rather than
	an invisible weapon. Meshes are authored by tools/blender_weapons.py.
]]

local WeaponConfig = {}

export type Ability = {
	Id: string,
	Name: string,
	Description: string,
	Cooldown: number,
	-- Seconds the effect persists. 0 for instant abilities like the grenade.
	Duration: number,
}

export type Appearance = {
	-- 0 until the Blender mesh is uploaded; falls back to built parts.
	MeshId: number,
	Color: Color3,
	Material: Enum.Material,
}

export type WeaponDefinition = {
	Id: string,
	Name: string,
	Description: string,

	-- Drives the part-built fallback model, the grip offset, and whether this
	-- thing swings or shoots.
	Archetype: string,
	Appearance: Appearance,

	--[[ THE MOVESET. One uploaded animation id per combo step; #Combo is the
	     combo length. 0 in a slot means "fall back to procedural" for that
	     step, which is how ranged weapons keep their recoil. ]]
	Combo: { number },
	-- Playback speed per step. Missing or short falls back to SwingSpeed.
	StepSpeeds: { number }?,
	SwingSpeed: number,

	Ability: Ability,

	-- Offence travels with the weapon.
	Damage: number,
	AttackSpeed: number,
	AttackRange: number,
	CritChance: number,
	CritDamage: number,

	-- Optional second item welded to the left arm: "Dagger" or "Shield".
	Offhand: string?,
}

local WOOD = Enum.Material.Wood
local METAL = Enum.Material.Metal

local definitions: { [string]: WeaponDefinition } = {
	Sword = {
		Id = "Sword",
		Name = "Arming Sword",
		Description = "Balanced reach and speed. Forgiving to swing.",
		Archetype = "Sword",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(178, 184, 196), Material = METAL },
		Combo = { 522635514, 522635514, 522638767 },
		SwingSpeed = 1.0,
		Ability = {
			Id = "SpinningSlash",
			Name = "Spinning Slash",
			Description = "Whirl, striking everything in reach.",
			Cooldown = 14,
			Duration = 3,
		},
		Damage = 18,
		AttackSpeed = 1.0,
		AttackRange = 12,
		CritChance = 8,
		CritDamage = 55,
	},

	Greataxe = {
		Id = "Greataxe",
		Name = "Greataxe",
		Description = "Two-handed. A cleave into an overhead crash.",
		Archetype = "Greataxe",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(148, 84, 68), Material = METAL },
		--[[ Our own animations, authored in Blender against a default R15
		     (tools/blender_rig.py). Two entries, so this is a TWO-hit combo:
		     horizontal cleave, then the overhead crash. ]]
		Combo = { 95534608969579, 98764921362960 },
		StepSpeeds = { 1.0, 1.0 },
		SwingSpeed = 1.0,
		Ability = {
			Id = "Undying",
			Name = "Undying",
			Description = "Cannot drop below one health.",
			Cooldown = 45,
			Duration = 10,
		},
		Damage = 22,
		AttackSpeed = 1.1,
		AttackRange = 13,
		CritChance = 12,
		CritDamage = 70,
	},

	Dagger = {
		Id = "Dagger",
		Name = "Twin Daggers",
		Description = "Short reach, brutal crits, paired.",
		Archetype = "Dagger",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(64, 68, 82), Material = METAL },
		Combo = { 522635514, 522635514, 522638767 },
		SwingSpeed = 1.35,
		Ability = {
			Id = "Vanish",
			Name = "Vanish",
			Description = "Disappear; enemies lose track of you.",
			Cooldown = 12,
			Duration = 5,
		},
		Damage = 30,
		AttackSpeed = 1.4,
		AttackRange = 11,
		CritChance = 25,
		CritDamage = 110,
		Offhand = "Dagger",
	},

	PaladinBlade = {
		Id = "PaladinBlade",
		Name = "Consecrated Blade",
		Description = "Sword and shield. Slow, immovable.",
		Archetype = "PaladinBlade",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(226, 200, 128), Material = METAL },
		Combo = { 522635514, 522635514, 522638767 },
		SwingSpeed = 0.95,
		Ability = {
			Id = "Aegis",
			Name = "Aegis",
			Description = "A barrier that shields nearby allies.",
			Cooldown = 40,
			Duration = 12,
		},
		Damage = 19,
		AttackSpeed = 0.95,
		AttackRange = 13,
		CritChance = 8,
		CritDamage = 55,
		Offhand = "Shield",
	},

	RoyalBlade = {
		Id = "RoyalBlade",
		Name = "Royal Blade",
		Description = "The crown's own steel.",
		Archetype = "RoyalBlade",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(244, 214, 96), Material = METAL },
		Combo = { 522635514, 522635514, 522638767 },
		SwingSpeed = 0.95,
		Ability = {
			Id = "RoyalGuard",
			Name = "Royal Guard",
			Description = "Summon knights and archers to your banner.",
			Cooldown = 90,
			Duration = 45,
		},
		Damage = 21,
		AttackSpeed = 1.0,
		AttackRange = 13,
		CritChance = 12,
		CritDamage = 70,
	},

	Bow = {
		Id = "Bow",
		Name = "Longbow",
		Description = "Ranged. Zooms when drawn.",
		Archetype = "Bow",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(126, 94, 58), Material = WOOD },
		-- Ranged keeps the procedural draw/recoil; a slash animation on a bow
		-- reads as nonsense.
		Combo = { 0 },
		SwingSpeed = 1.0,
		Ability = {
			Id = "Rapidfire",
			Name = "Rapidfire",
			Description = "Draw and loose far faster for a few seconds.",
			Cooldown = 18,
			Duration = 6,
		},
		Damage = 14,
		AttackSpeed = 1.25,
		AttackRange = 90,
		CritChance = 10,
		CritDamage = 60,
	},

	Musket = {
		Id = "Musket",
		Name = "Musket",
		Description = "Slow, heavy, hits like a cannon.",
		Archetype = "Musket",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(92, 82, 74), Material = WOOD },
		Combo = { 0 },
		SwingSpeed = 1.0,
		Ability = {
			Id = "Grenade",
			Name = "Grenade",
			Description = "Lob an explosive that detonates where it lands.",
			Cooldown = 9,
			Duration = 0,
		},
		Damage = 26,
		AttackSpeed = 0.7,
		AttackRange = 85,
		CritChance = 10,
		CritDamage = 65,
	},

	NecroStaff = {
		Id = "NecroStaff",
		Name = "Bone Staff",
		Description = "Commands the dead.",
		Archetype = "NecroStaff",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(108, 76, 148), Material = WOOD },
		Combo = { 0 },
		SwingSpeed = 1.0,
		Ability = {
			Id = "RaiseSkeletons",
			Name = "Skeleton Army",
			Description = "Raise six skeletons to fight beside you.",
			Cooldown = 75,
			Duration = 30,
		},
		Damage = 16,
		AttackSpeed = 0.85,
		AttackRange = 70,
		CritChance = 10,
		CritDamage = 60,
	},

	--[[ No class starts with these two. They exist so the item system has
	     somewhere to grow: drops, shop stock, or a second weapon slot. ]]
	Greatsword = {
		Id = "Greatsword",
		Name = "Greatsword",
		Description = "Enormous reach, punishing recovery.",
		Archetype = "Greatsword",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(196, 200, 210), Material = METAL },
		Combo = { 522635514, 522635514, 522638767 },
		SwingSpeed = 0.72,
		Ability = {
			Id = "SpinningSlash",
			Name = "Spinning Slash",
			Description = "Whirl, striking everything in reach.",
			Cooldown = 16,
			Duration = 3,
		},
		Damage = 26,
		AttackSpeed = 0.75,
		AttackRange = 15,
		CritChance = 10,
		CritDamage = 70,
	},

	Staff = {
		Id = "Staff",
		Name = "Staff",
		Description = "A plain caster's staff.",
		Archetype = "Staff",
		Appearance = { MeshId = 0, Color = Color3.fromRGB(150, 120, 200), Material = WOOD },
		Combo = { 0 },
		SwingSpeed = 1.0,
		Ability = {
			Id = "Rapidfire",
			Name = "Focus",
			Description = "Cast faster for a few seconds.",
			Cooldown = 18,
			Duration = 6,
		},
		Damage = 15,
		AttackSpeed = 0.9,
		AttackRange = 70,
		CritChance = 10,
		CritDamage = 60,
	},
}

--[[ Seconds the blade trail stays on from the start of an uploaded swing,
     before speed scaling. ]]
WeaponConfig.TrailSeconds = 0.5

WeaponConfig.Definitions = definitions
WeaponConfig.Default = "Sword"

function WeaponConfig.Get(weaponId: string?): WeaponDefinition?
	return definitions[weaponId or ""]
end

--[[
	The weapon a profile is currently fighting with.

	Today that is simply the class's starting weapon, but every consumer asks
	THIS rather than reading the class — so giving players a real inventory
	later is a change to this one function, not to combat, animation and
	ability code scattered across the server.
]]
function WeaponConfig.GetEquipped(profile: any): WeaponDefinition
	local id = profile and profile.Weapon
	local found = definitions[id or ""]
	if found then
		return found
	end

	-- Fall back to whatever the class starts with.
	local ClassConfig = require(script.Parent.ClassConfig)
	local class = ClassConfig.Get(profile and profile.Class)
	return definitions[(class and class.StartingWeapon) or ""] or definitions[WeaponConfig.Default]
end

--[[ How many swings this weapon's combo cycles through. ]]
function WeaponConfig.GetComboLength(weaponId: string?): number
	local def = definitions[weaponId or ""]
	return if def and #def.Combo > 0 then #def.Combo else 3
end

--[[ Animation id for a combo step, or 0 to use the procedural swing. ]]
function WeaponConfig.GetSwingId(weaponId: string?, step: number): number
	local def = definitions[weaponId or ""]
	if not def or #def.Combo == 0 then
		return 0
	end
	return def.Combo[((step - 1) % #def.Combo) + 1] or 0
end

--[[ Playback speed for a combo step. ]]
function WeaponConfig.GetSpeed(weaponId: string?, step: number?): number
	local def = definitions[weaponId or ""]
	if not def then
		return 1
	end
	local per = def.StepSpeeds
	if per and step and #per > 0 then
		local v = per[((step - 1) % #per) + 1]
		if v then
			return v
		end
	end
	return def.SwingSpeed
end

return WeaponConfig
