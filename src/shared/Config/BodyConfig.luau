--!strict
--[[
	BodyConfig — standardised character bodies.

	Why standardise at all: armour is welded to body parts. If every player has
	a different avatar package, a chestplate that sits correctly on one player
	clips through another. Fixing the body geometry makes one set of armour
	models fit everyone.

	What is preserved: the player's Head, Face, hair, hats, and every other
	accessory. Only the torso, arms, legs, and proportions are replaced. Players
	still look like themselves from the neck up, which is where identity
	actually lives on Roblox.

	=========================================================================
	ASSET IDS
	Every body part id below is 0, which Roblox reads as "default R15 part".
	That works and ships — players get the standard blocky R15 body. To use a
	real body package, paste its part ids here; nothing else changes.

	To find them: open the bundle on the Creator Store, take the individual
	body-part asset ids from it. A bundle id will NOT work in these fields —
	they need the per-part ids.
	=========================================================================
]]

export type BodyPreset = {
	Id: string,
	Name: string,
	Description: string,

	-- Body part asset ids. 0 = default R15 part.
	Torso: number,
	LeftArm: number,
	RightArm: number,
	LeftLeg: number,
	RightLeg: number,

	-- Proportions. BodyTypeScale 0 is blocky R15, 1 is fully Rthro.
	BodyTypeScale: number,
	HeightScale: number,
	WidthScale: number,
	HeadScale: number,
	ProportionScale: number,
}

local BodyConfig = {}

--[[
	Whether to strip the player's shirt and pants when applying a body.

	Off by default: clearing clothing makes armour read more clearly, but it
	also overrides a choice the player made about their own avatar. Turn it on
	once real armour meshes cover the body.
]]
BodyConfig.ClearClothing = false

--[[ Body type chosen on first join. Changeable later from settings. ]]
BodyConfig.DefaultPreset = "Masculine"

local presets: { [string]: BodyPreset } = {
	Masculine = {
		Id = "Masculine",
		Name = "Masculine",
		Description = "Broader shoulders, standard height.",
		Torso = 0,
		LeftArm = 0,
		RightArm = 0,
		LeftLeg = 0,
		RightLeg = 0,
		BodyTypeScale = 0.3,
		HeightScale = 1.0,
		WidthScale = 1.0,
		HeadScale = 1.0,
		ProportionScale = 0.4,
	},

	Feminine = {
		Id = "Feminine",
		Name = "Feminine",
		Description = "Narrower frame, slightly taller stance.",
		Torso = 0,
		LeftArm = 0,
		RightArm = 0,
		LeftLeg = 0,
		RightLeg = 0,
		BodyTypeScale = 0.3,
		HeightScale = 1.02,
		WidthScale = 0.9,
		HeadScale = 1.0,
		ProportionScale = 0.7,
	},
}

BodyConfig.Presets = presets

--[[ Presentation order for the chooser UI. ]]
BodyConfig.Order = { "Masculine", "Feminine" }

function BodyConfig.Get(presetId: string): BodyPreset?
	return presets[presetId]
end

--[[ True if the id names a real preset. Used to validate client input. ]]
function BodyConfig.IsValid(presetId: any): boolean
	return type(presetId) == "string" and presets[presetId] ~= nil
end

--[[
	Attachment points for equipment, by slot.

	`Part` is the R15 body part the model welds to, and `Offset` positions the
	model relative to that part's centre. Weapons attach to the right hand;
	armour attaches to the piece it covers.

	These are tuned for default R15. Swapping in a real body package will mean
	revisiting the offsets — which is exactly why they live in config.
]]
BodyConfig.AttachPoints = {
	Weapon = {
		Part = "RightHand",
		Offset = CFrame.new(0, -1.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
	},
	Helmet = {
		Part = "Head",
		Offset = CFrame.new(0, 0.55, 0),
	},
	Chest = {
		Part = "UpperTorso",
		Offset = CFrame.new(0, 0, -0.1),
	},
	Legs = {
		Part = "LowerTorso",
		Offset = CFrame.new(0, -0.6, 0),
	},
	Boots = {
		Part = "LeftFoot",
		Offset = CFrame.new(0, -0.1, 0),
	},
	Accessory = {
		Part = "UpperTorso",
		Offset = CFrame.new(0.9, 0.3, -0.6),
	},
	Gear = {
		Part = "UpperTorso",
		Offset = CFrame.new(0, 0.2, 0.7),
	},
}

--[[
	Slots that mirror onto both sides. Boots are one model per foot, so the
	spawner knows to build two and mirror the offset.
]]
BodyConfig.MirroredSlots = {
	Boots = { "LeftFoot", "RightFoot" },
}

--[[ Body part ids still left at 0, for the startup configuration report. ]]
function BodyConfig.GetUnconfigured(): { string }
	local missing = {}

	for _, presetId in ipairs(BodyConfig.Order) do
		local preset = presets[presetId]
		for _, field in ipairs({ "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }) do
			if (preset :: any)[field] == 0 then
				table.insert(missing, string.format("%s.%s", presetId, field))
			end
		end
	end

	return missing
end

return BodyConfig
