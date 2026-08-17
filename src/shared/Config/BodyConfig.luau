--!strict
--[[
	BodyConfig — the standard character body and equipment attach points.

	Every player gets the same body: default R15 meshes at neutral proportions.
	There is no body type choice and no gender variants.

	Standardising still matters even without variants. Armour is welded to body
	parts, so if players arrive with wildly different avatar packages, a
	chestplate that sits correctly on one clips through another. Pinning the
	body geometry means one set of armour models fits everyone.

	What is preserved: the player's Head, Face, hair, hats, and every other
	accessory. Only the torso, arms, legs, and proportions are normalised, so
	players still look like themselves from the neck up.
]]

local BodyConfig = {}

--[[
	Whether to strip the player's shirt and pants when applying the body.

	Off by default: clearing clothing makes armour read more clearly, but it
	overrides a choice the player made about their own avatar. Worth turning on
	once real armour meshes cover the body.
]]
BodyConfig.ClearClothing = false

--[[
	The one body everyone gets.

	Part ids of 0 mean "default R15 part". Scales are neutral, so the result is
	the standard R15 character — predictable geometry for armour to weld to,
	and identical for every player.
]]
BodyConfig.Standard = {
	Torso = 0,
	LeftArm = 0,
	RightArm = 0,
	LeftLeg = 0,
	RightLeg = 0,

	BodyTypeScale = 0.0,
	HeightScale = 1.0,
	WidthScale = 1.0,
	DepthScale = 1.0,
	HeadScale = 1.0,
	ProportionScale = 0.0,
}

--[[
	Attachment points for equipment, by slot.

	`Part` is the R15 body part the model welds to, and `Offset` positions the
	model relative to that part's centre. Weapons attach to the right hand;
	armour attaches to the piece it covers.

	These are tuned for default R15 at neutral scale — which, now that every
	player uses exactly that, is the only case they need to handle.
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

return BodyConfig
