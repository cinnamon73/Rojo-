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
	BODY MESHES

	Both presets currently have BundleId = 0, so they use the default R15
	meshes and are told apart purely by proportion: Masculine sits at the
	blocky end (broad, stocky, short-limbed) and Feminine at the Rthro end
	(narrow, tall, long-limbed). Measured, that is ~29% narrower and ~27%
	longer-limbed — clearly two different builds, but still the same meshes.

	For real anatomy, set BundleId on each preset to a body bundle from the
	Creator Store. The number is in the bundle's URL:

	    roblox.com/bundles/<THIS NUMBER>/Some-Body

	CharacterService resolves it at runtime and pulls the real part meshes out
	of the bundle's outfit. The scale values below then shape those meshes
	instead of the default ones, so they stay useful either way.
	=========================================================================
]]

export type BodyPreset = {
	Id: string,
	Name: string,
	Description: string,

	--[[
		Catalog bundle id for this body. THIS IS THE FIELD TO FILL IN.

		At runtime CharacterService resolves it via GetBundleDetailsAsync, finds
		the bundle's outfit, and pulls the real body-part mesh ids out of it. One
		number per body instead of five, and it cannot drift out of sync with
		the actual bundle.

		To find it: open the body bundle on the Creator Store and read the
		number out of the URL — /bundles/<THIS NUMBER>/Name.

		0 means unresolved: the preset falls back to the scale values below.
	]]
	BundleId: number,

	-- Explicit per-part overrides. Only needed if you deliberately want to mix
	-- parts from different bundles; BundleId covers the normal case.
	Torso: number,
	LeftArm: number,
	RightArm: number,
	LeftLeg: number,
	RightLeg: number,

	--[[
		Proportions, applied on top of whatever parts are in use.

		BodyTypeScale is the important one: 0 is the blocky default R15
		silhouette, 1 is fully Rthro — taller, slimmer, longer-limbed. Driving
		the two presets to opposite ends of that range is what makes them read
		as different bodies even with no bundle configured.
	]]
	BodyTypeScale: number,
	HeightScale: number,
	WidthScale: number,
	DepthScale: number,
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
	--[[
		Masculine sits at the blocky end: broad, square-shouldered, shorter
		limbs relative to torso.
	]]
	Masculine = {
		Id = "Masculine",
		Name = "Masculine",
		Description = "Broad shoulders, heavy build.",
		BundleId = 0,
		Torso = 0,
		LeftArm = 0,
		RightArm = 0,
		LeftLeg = 0,
		RightLeg = 0,
		BodyTypeScale = 0.0,
		HeightScale = 1.0,
		WidthScale = 1.05,
		DepthScale = 1.05,
		HeadScale = 1.0,
		ProportionScale = 0.0,
	},

	--[[
		Feminine sits at the Rthro end: taller, noticeably narrower and
		shallower, with longer limbs. Opposite corner of the scale space from
		Masculine so the two are distinguishable at a glance without meshes.

		This is a silhouette difference, not a real female body mesh. Set
		BundleId to a proper body bundle for that — the scale values below then
		shape the bundle's parts rather than the default R15 ones.
	]]
	Feminine = {
		Id = "Feminine",
		Name = "Feminine",
		Description = "Slimmer frame, taller stance, longer limbs.",
		BundleId = 0,
		Torso = 0,
		LeftArm = 0,
		RightArm = 0,
		LeftLeg = 0,
		RightLeg = 0,
		BodyTypeScale = 1.0,
		HeightScale = 1.05,
		WidthScale = 0.82,
		DepthScale = 0.88,
		HeadScale = 1.0,
		ProportionScale = 1.0,
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

--[[
	Presets with no bundle and no explicit parts — those fall back to default
	R15 meshes shaped only by the scale values.
]]
function BodyConfig.GetUnconfigured(): { string }
	local missing = {}

	for _, presetId in ipairs(BodyConfig.Order) do
		local preset = presets[presetId]
		local hasParts = preset.Torso ~= 0 or preset.LeftArm ~= 0 or preset.RightArm ~= 0
		if preset.BundleId == 0 and not hasParts then
			table.insert(missing, presetId)
		end
	end

	return missing
end

return BodyConfig
