--!strict
--[[
	EnemyRigs — articulated enemy bodies.

	The original enemies were parts WELDED RIGIDLY to the root, so nothing could
	move. These are jointed with Motor6D chains instead, which means an animator
	can pose them by writing joint C0s. No Roblox animation assets are involved
	and nothing needs uploading.

	EVERY JOINT STORES ITS REST C0 as a `RestC0` attribute. Animation is applied
	as an OFFSET from that:

		joint.C0 = joint:GetAttribute("RestC0") * CFrame.Angles(x, y, z)

	Never accumulate onto the live C0 — it drifts within a few seconds.

	SKELETON ORDER MATTERS. Legs hang off the PELVIS, not the chest:

		root -> Pelvis -> Hip -> Knee -> Ankle          (legs)
		        Pelvis -> Waist -> Spine -> Neck -> Head
		                           Spine -> Shoulder -> Elbow -> Wrist -> Grip

	The first version hung the legs off the chest. Leaning the torso forward
	then dragged the pelvis and feet forward with it, and the body reclined to
	compensate — the feet ended up 1.7 studs in front of the head. If a new rig
	ever looks like it is sitting in a deck chair, this is why.

	SIGN CONVENTION, established by measurement and got wrong twice:
	  * Spine / Waist / Head X POSITIVE leans BACK, NEGATIVE leans FORWARD.
	  * ShoulderR POSITIVE swings the arm forward and up IN FRONT; negative
	    takes it up behind the head. See EnemyAnimation for the measured map.
]]

local EnemyRigs = {}

export type Palette = {
	Skin: Color3,
	SkinDark: Color3,
	SkinLight: Color3,
	Cloth: Color3,
	Nail: Color3,
	Eye: Color3,
}

--[[
	Rest pose, in degrees, per joint. Solved by measurement in a live preview,
	not by eye: at these angles the feet land exactly on the ground and the head
	sits ~0.3 studs IN FRONT of the feet, which is the hunch that reads as a
	goblin rather than a person.
]]
local GOBLIN_REST: { [string]: { number } } = {
	Pelvis    = {   0, 0,   0 },
	Waist     = {  -4, 0,   0 },
	Spine     = {  -2, 0,   0 },
	Neck      = {  -5, 0,   0 },
	Head      = {  16, 0,   0 },
	ShoulderL = { -12, 0, -13 },
	ShoulderR = { -12, 0,  13 },
	ElbowL    = { -30, 0,   0 },
	ElbowR    = { -44, 0,   0 },
	WristL    = { -10, 0,   0 },
	WristR    = { -10, 0,   0 },
	HipL      = {  -4, 0,  -6 },
	HipR      = {  -4, 0,   6 },
	KneeL     = {  14, 0,   0 },
	KneeR     = {  14, 0,   0 },
	AnkleL    = {  -8, 0,   0 },
	AnkleR    = {  -8, 0,   0 },
	Grip      = {  90, 0,   0 },
}

-- Distance from the ground to the root's centre, minus half the root's height.
-- The Humanoid uses this to float the rig at the right height; get it wrong and
-- the goblin either sinks into the floor or hovers.
EnemyRigs.GoblinHipHeight = 2.579

local function palette(body: Color3, accent: Color3): Palette
	local h, s, v = body:ToHSV()
	return {
		Skin = body,
		SkinDark = Color3.fromHSV(h, math.min(1, s * 1.08), math.max(0, v * 0.78)),
		SkinLight = Color3.fromHSV(h, math.max(0, s * 0.86), math.min(1, v * 1.20)),
		Cloth = accent,
		Nail = Color3.fromRGB(232, 224, 198),
		Eye = Color3.fromRGB(255, 206, 74),
	}
end

--[[
	Builds the goblin. `scale` multiplies every dimension and offset, so the
	same body serves a small goblin and a large one.

	Returns the model, its Motor6D map, and the scaled hip height.
]]
function EnemyRigs.BuildGoblin(
	bodyColor: Color3,
	accentColor: Color3,
	material: Enum.Material,
	scale: number
): (Model, { [string]: Motor6D }, number)
	local P = palette(bodyColor, accentColor)
	local model = Instance.new("Model")
	local joints: { [string]: Motor6D } = {}

	local function part(name: string, size: Vector3, colour: Color3, mat: Enum.Material?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.Color = colour
		p.Material = mat or material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = model
		return p
	end
	local function joint(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame?)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		-- Position offsets scale with the body; rotations do not.
		local pos = c0.Position * scale
		m.C0 = CFrame.new(pos) * (c0 - c0.Position)
		if c1 then
			m.C1 = CFrame.new(c1.Position * scale) * (c1 - c1.Position)
		end
		m.Parent = p0
		joints[name] = m
	end

	local root = part("HumanoidRootPart", Vector3.new(1.6, 1.6, 1.0), P.Skin)
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	model.PrimaryPart = root

	local pelvis = part("Loincloth", Vector3.new(1.98, 0.9, 1.6), P.Cloth)
	joint("Pelvis", root, pelvis, CFrame.new(0, -1.05, 0))
	local belly = part("Belly", Vector3.new(1.92, 1.1, 1.5), P.Skin)
	joint("Waist", pelvis, belly, CFrame.new(0, 0.4, 0), CFrame.new(0, -0.5, 0))
	local chest = part("Torso", Vector3.new(1.6, 1.15, 1.0), P.Skin)
	joint("Spine", belly, chest, CFrame.new(0, 0.5, -0.1), CFrame.new(0, -0.55, 0))
	local pecs = part("Chest", Vector3.new(1.78, 0.5, 1.06), P.SkinLight)
	joint("Pecs", chest, pecs, CFrame.new(0, 0.36, -0.02))

	local neck = part("Neck", Vector3.new(0.5, 0.62, 0.5), P.SkinDark)
	joint("Neck", chest, neck, CFrame.new(0, 0.68, 0.06), CFrame.new(0, -0.26, 0))
	local head = part("Head", Vector3.new(1.44, 1.2, 1.3), P.Skin)
	joint("Head", neck, head, CFrame.new(0, 0.36, -0.12), CFrame.new(0, -0.46, 0.12))
	local brow = part("Brow", Vector3.new(1.4, 0.3, 0.6), P.SkinDark)
	joint("Brow", head, brow, CFrame.new(0, 0.32, -0.46))
	local snout = part("Snout", Vector3.new(0.68, 0.46, 0.72), P.SkinLight)
	joint("Snout", head, snout, CFrame.new(0, -0.16, -0.7))
	local jaw = part("Jaw", Vector3.new(0.84, 0.3, 0.66), P.SkinDark)
	joint("Jaw", head, jaw, CFrame.new(0, -0.48, -0.4), CFrame.new(0, 0.1, 0))

	for i, sx in ipairs({ -1, 1 }) do
		-- Ears sweep out and back so both read in silhouette from the front.
		local ear = part("Ear" .. i, Vector3.new(1.05, 0.34, 0.16), P.SkinDark)
		joint("Ear" .. i, head, ear,
			CFrame.new(sx * 0.68, 0.24, 0.1)
				* CFrame.Angles(math.rad(-8), math.rad(sx * -34), math.rad(sx * 34)),
			CFrame.new(-sx * 0.5, 0, 0))
		local eye = part("Eye" .. i, Vector3.new(0.26, 0.26, 0.14), P.Eye, Enum.Material.Neon)
		joint("Eye" .. i, head, eye, CFrame.new(sx * 0.31, 0.04, -0.63))
		local tusk = part("Tusk" .. i, Vector3.new(0.14, 0.34, 0.14), P.Nail)
		joint("Tusk" .. i, jaw, tusk, CFrame.new(sx * 0.24, 0.22, -0.26) * CFrame.Angles(math.rad(-14), 0, 0))
	end

	local handR: BasePart
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local s = side[1] :: string
		local sx = side[2] :: number
		-- Shoulders sit OUTSIDE the belly's half-width so the arms never vanish
		-- into the torso, and limbs are a shade darker so they read against it.
		local upper = part("UpperArm" .. s, Vector3.new(0.5, 1.15, 0.5), P.SkinDark)
		joint("Shoulder" .. s, chest, upper, CFrame.new(sx * 1.12, 0.34, 0), CFrame.new(0, 0.55, 0))
		local lower = part("LowerArm" .. s, Vector3.new(0.44, 1.1, 0.44), P.SkinDark)
		joint("Elbow" .. s, upper, lower, CFrame.new(0, -0.58, 0), CFrame.new(0, 0.53, 0))
		local hand = part("Hand" .. s, Vector3.new(0.5, 0.5, 0.66), P.SkinLight)
		joint("Wrist" .. s, lower, hand, CFrame.new(0, -0.55, -0.04), CFrame.new(0, 0.22, 0))
		for k = -1, 1 do
			local claw = part("Claw" .. s .. k, Vector3.new(0.1, 0.1, 0.24), P.Nail)
			joint("Claw" .. s .. k, hand, claw, CFrame.new(k * 0.15, -0.1, -0.4))
		end
		if s == "R" then
			handR = hand
		end
	end

	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local s = side[1] :: string
		local sx = side[2] :: number
		local upper = part("UpperLeg" .. s, Vector3.new(0.66, 0.9, 0.7), P.SkinDark)
		joint("Hip" .. s, pelvis, upper, CFrame.new(sx * 0.52, -0.42, 0), CFrame.new(0, 0.44, 0))
		local lower = part("LowerLeg" .. s, Vector3.new(0.58, 0.86, 0.6), P.SkinDark)
		joint("Knee" .. s, upper, lower, CFrame.new(0, -0.46, 0.02), CFrame.new(0, 0.42, 0))
		local foot = part("Foot" .. s, Vector3.new(0.66, 0.32, 1.12), P.SkinLight)
		joint("Ankle" .. s, lower, foot, CFrame.new(0, -0.44, -0.22))
		for k = -1, 1 do
			local toe = part("Toe" .. s .. k, Vector3.new(0.12, 0.12, 0.2), P.Nail)
			joint("Toe" .. s .. k, foot, toe, CFrame.new(k * 0.2, -0.06, -0.62))
		end
	end

	-- The club. Grip X=90 hangs it DOWN from the fist; without that rotation it
	-- lies back along the forearm and the swing starts 2 studs behind the body.
	local WOOD = Color3.fromRGB(104, 76, 48)
	local WOOD_DARK = Color3.fromRGB(78, 56, 36)
	local handle = part("ClubHandle", Vector3.new(0.26, 2.0, 0.26), WOOD)
	joint("Grip", handR, handle, CFrame.new(0, -0.16, -0.12), CFrame.new(0, 0.55, 0))
	local knob = part("ClubHead", Vector3.new(0.62, 1.0, 0.62), WOOD_DARK)
	joint("ClubHead", handle, knob, CFrame.new(0, -1.15, 0))
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		local stud = part("ClubStud" .. i, Vector3.new(0.2, 0.2, 0.2), P.Nail)
		joint("ClubStud" .. i, knob, stud,
			CFrame.new(math.sin(a) * 0.32, if i % 2 == 0 then 0.2 else -0.16, math.cos(a) * 0.32))
	end
	local band = part("ClubBand", Vector3.new(0.32, 0.16, 0.32), P.Cloth)
	joint("ClubBand", handle, band, CFrame.new(0, 0.62, 0))

	-- Apply the rest pose, then record it. Everything downstream poses relative
	-- to these, so they must be written before anything animates.
	for name, r in pairs(GOBLIN_REST) do
		local m = joints[name]
		if m then
			m.C0 = m.C0 * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		end
	end
	for _, m in pairs(joints) do
		m:SetAttribute("RestC0", m.C0)
	end

	return model, joints, EnemyRigs.GoblinHipHeight * scale
end

--[[
	Rest pose for the skeleton. Solved by measurement in a live preview, like
	the goblin's, and the arms are the part that took the work.

	ARMS BEND IN FRONT, NOT BEHIND. On this rig POSITIVE shoulder and elbow X
	swings the limb FORWARD; the first pass used negatives and tucked both
	forearms behind the ribcage. But driving the shoulder forward as well as the
	elbow stacks the two angles and the whole limb reaches out ahead of the
	chest, which reads as offering the weapon rather than carrying it. So the
	shoulder stays near-neutral and the ELBOW supplies the bend.
]]
local SKELETON_REST: { [string]: { number } } = {
	Waist     = { -3, 0,   0 },
	Spine     = { -3, 0,   0 },
	Neck      = { -4, 0,   0 },
	Head      = { 12, 0,   0 },
	ShoulderL = {  6, 0, -14 },
	ShoulderR = {  3, 0,   9 },
	ElbowL    = { 44, 0,   0 },
	ElbowR    = { 30, 0,   0 },
	WristL    = { -6, 0,   0 },
	WristR    = { -6, 0,   0 },
	HipL      = { -3, 0,  -4 },
	HipR      = { -3, 0,   4 },
	KneeL     = { 10, 0,   0 },
	KneeR     = { 10, 0,   0 },
	AnkleL    = { -6, 0,   0 },
	AnkleR    = { -6, 0,   0 },
}

EnemyRigs.SkeletonHipHeight = 2.785

--[[
	How the sword sits in the fist. Three separate faults were fixed here and
	each one is easy to reintroduce by "tidying" these numbers:

	  * THE 180 DEGREE FLIP STANDS THE BLADE UP. The sword is built hanging DOWN
	    the grip's local -Y; the 159 degrees of X is what points it at the sky.
	    A consequence worth remembering: a POSITIVE local Y offset from the grip
	    therefore travels DOWNWARD in the world, which is why the pommel below
	    is positive and the guard above it is negative.

	  * THE TRAILING 90 IS THE BLADE'S ROLL. Without it the blade is edge-on to
	    the viewer — the flats face fore and aft instead of left and right, and
	    the sword reads as sideways in the hand. Measured: alignment of the
	    blade's wide axis with fore/aft was 0.00 before the roll and 1.00 after.
	    Rolling about the grip's own Y leaves the blade axis untouched, so the
	    finger wrap below is unaffected by it.

	  * THE HILT SITS ON THE FIST. The grip carries NO translation, so its
	    centre lands exactly on the palm, and guard and pommel are placed from
	    the hand's own half-height. An earlier hand-tuned offset left 0.16 studs
	    of bare leather between fist and guard — over half a hand's height — and
	    the sword read as floating alongside the hand rather than held in it.
]]
local SKELETON_GRIP_ROT = CFrame.Angles(math.rad(159), math.rad(0.5), math.rad(15))
	* CFrame.Angles(0, math.rad(90), 0)

--[[
	Builds the skeleton: sword held upright in the right fist, small broken
	shield on the left arm.

	Joint names are deliberately IDENTICAL to the goblin's, so the animator
	drives this rig without knowing it is a different creature. The POSES are
	not shared — see EnemyAnimation.Sets.Skeleton, because a sword held point-up
	swings nothing like a club held point-down.
]]
function EnemyRigs.BuildSkeleton(
	bodyColor: Color3,
	accentColor: Color3,
	material: Enum.Material,
	scale: number
): (Model, { [string]: Motor6D }, number)
	local model = Instance.new("Model")
	local joints: { [string]: Motor6D } = {}

	local BONE = bodyColor
	local h, s, v = bodyColor:ToHSV()
	local BONE_D = Color3.fromHSV(h, math.min(1, s * 1.1), math.max(0, v * 0.84))
	local BONE_L = Color3.fromHSV(h, math.max(0, s * 0.7), math.min(1, v * 1.07))
	local SOCKET = Color3.fromRGB(24, 22, 20)
	local RAG, RAG_D = Color3.fromRGB(118, 108, 94), accentColor
	local IRON = Color3.fromRGB(94, 92, 88)
	local STEEL, FULLER = Color3.fromRGB(104, 108, 114), Color3.fromRGB(74, 76, 80)
	local RUST = Color3.fromRGB(128, 84, 56)
	local WOOD_A, WOOD_B = Color3.fromRGB(146, 114, 76), Color3.fromRGB(168, 136, 96)
	local WOOD_BACK, WOOD_SPLINT = Color3.fromRGB(92, 71, 48), Color3.fromRGB(190, 160, 120)
	local LEATHER = Color3.fromRGB(74, 56, 42)

	local function part(name: string, size: Vector3, colour: Color3, mat: Enum.Material?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * scale
		p.Color = colour
		p.Material = mat or material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.Massless = true
		p.Parent = model
		return p
	end
	local function joint(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame?)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		-- Position offsets scale with the body; rotations do not.
		m.C0 = CFrame.new(c0.Position * scale) * (c0 - c0.Position)
		if c1 then
			m.C1 = CFrame.new(c1.Position * scale) * (c1 - c1.Position)
		end
		m.Parent = p0
		joints[name] = m
	end

	local root = part("HumanoidRootPart", Vector3.new(1.3, 1.4, 0.85), BONE)
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	model.PrimaryPart = root

	local pelvis = part("Pelvis", Vector3.new(1.2, 0.62, 0.78), BONE_D)
	joint("Pelvis", root, pelvis, CFrame.new(0, -0.95, 0))
	for i, sx in ipairs({ -1, 1 }) do
		local hipBlade = part("Ilium" .. i, Vector3.new(0.34, 0.62, 0.6), BONE)
		joint("Ilium" .. i, pelvis, hipBlade,
			CFrame.new(sx * 0.62, 0.16, -0.02) * CFrame.Angles(0, 0, math.rad(sx * 14)))
	end
	-- Torn strips rather than one dark block: a solid skirt read as a slab.
	for i = 1, 7 do
		local a = (i - 4) * 0.24
		local len = 1.0 + ((i % 3) * 0.22)
		local strip = part("Rag" .. i, Vector3.new(0.34, len, 0.1),
			if i % 2 == 0 then RAG else RAG_D, Enum.Material.Fabric)
		joint("Rag" .. i, pelvis, strip,
			CFrame.new(math.sin(a) * 0.72, -0.34 - len / 2 + 0.2, math.cos(a) * 0.5 - 0.1)
				* CFrame.Angles(0, -a, 0))
	end

	--[[ The ribcage TAPERS as it descends. Equal-width slabs read as a stack of
	     plates, which is exactly what the first attempt looked like. ]]
	local lumbar = part("Lumbar", Vector3.new(0.34, 0.8, 0.34), BONE_D)
	joint("Waist", pelvis, lumbar, CFrame.new(0, 0.3, 0), CFrame.new(0, -0.38, 0))
	local sternum = part("Ribcage", Vector3.new(0.4, 1.3, 0.36), BONE_D)
	joint("Spine", lumbar, sternum, CFrame.new(0, 0.4, 0), CFrame.new(0, -0.6, 0))
	for i = 1, 5 do
		local t = (i - 1) / 4
		local rib = part("Rib" .. i, Vector3.new(1.32 - t * 0.5, 0.13, 0.98 - t * 0.28), BONE_L)
		joint("Rib" .. i, sternum, rib, CFrame.new(0, 0.5 - (i - 1) * 0.26, -0.02))
	end
	local collar = part("Collar", Vector3.new(1.38, 0.15, 0.22), BONE_L)
	joint("Collar", sternum, collar, CFrame.new(0, 0.7, -0.3))

	local neck = part("Neck", Vector3.new(0.28, 0.44, 0.28), BONE_D)
	joint("Neck", sternum, neck, CFrame.new(0, 0.76, 0.02), CFrame.new(0, -0.2, 0))
	local skull = part("Head", Vector3.new(0.92, 0.88, 1.02), BONE)
	joint("Head", neck, skull, CFrame.new(0, 0.26, -0.04), CFrame.new(0, -0.36, 0.06))
	local cranium = part("Cranium", Vector3.new(0.86, 0.3, 0.9), BONE_L)
	joint("Cranium", skull, cranium, CFrame.new(0, 0.4, 0.04))
	local jaw = part("Jaw", Vector3.new(0.66, 0.24, 0.62), BONE_D)
	joint("Jaw", skull, jaw, CFrame.new(0, -0.38, -0.16), CFrame.new(0, 0.1, 0))
	local brow = part("Brow", Vector3.new(0.88, 0.16, 0.42), BONE_L)
	joint("Brow", skull, brow, CFrame.new(0, 0.26, -0.32))
	for i, sx in ipairs({ -1, 1 }) do
		local socket = part("Socket" .. i, Vector3.new(0.27, 0.29, 0.2), SOCKET)
		joint("Socket" .. i, skull, socket, CFrame.new(sx * 0.22, 0.02, -0.46))
		local tooth = part("Tooth" .. i, Vector3.new(0.28, 0.1, 0.09), BONE_L)
		joint("Tooth" .. i, jaw, tooth, CFrame.new(sx * 0.14, 0.11, -0.26))
		-- Cheek matches the skull tone. A darker one read as a grey patch stuck
		-- on the side of the head rather than as bone structure.
		local cheek = part("Cheek" .. i, Vector3.new(0.1, 0.26, 0.3), BONE)
		joint("Cheek" .. i, skull, cheek, CFrame.new(sx * 0.42, -0.06, -0.2))
	end
	local nasal = part("Nasal", Vector3.new(0.13, 0.19, 0.14), SOCKET)
	joint("Nasal", skull, nasal, CFrame.new(0, -0.15, -0.5))

	local handR: BasePart
	local handL: BasePart
	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local sd = side[1] :: string
		local sx = side[2] :: number
		local upper = part("Humerus" .. sd, Vector3.new(0.28, 1.0, 0.28), BONE)
		joint("Shoulder" .. sd, sternum, upper, CFrame.new(sx * 0.76, 0.52, 0), CFrame.new(0, 0.48, 0))
		local lower = part("Radius" .. sd, Vector3.new(0.24, 0.95, 0.24), BONE)
		joint("Elbow" .. sd, upper, lower, CFrame.new(0, -0.5, 0), CFrame.new(0, 0.46, 0))
		local hand = part("Hand" .. sd, Vector3.new(0.3, 0.32, 0.44), BONE_L)
		joint("Wrist" .. sd, lower, hand, CFrame.new(0, -0.48, -0.02), CFrame.new(0, 0.14, 0))
		if sd == "R" then handR = hand else handL = hand end
	end
	-- The empty hand keeps simple forward fingers; only the sword hand wraps.
	for k = -1, 1 do
		local finger = part("FingerL" .. k, Vector3.new(0.07, 0.07, 0.26), BONE_L)
		joint("FingerL" .. k, handL, finger, CFrame.new(k * 0.1, -0.05, -0.3))
	end

	for _, side in ipairs({ { "L", -1 }, { "R", 1 } }) do
		local sd = side[1] :: string
		local sx = side[2] :: number
		local upper = part("Femur" .. sd, Vector3.new(0.32, 1.1, 0.32), BONE)
		joint("Hip" .. sd, pelvis, upper, CFrame.new(sx * 0.38, -0.3, 0), CFrame.new(0, 0.54, 0))
		local lower = part("Tibia" .. sd, Vector3.new(0.28, 1.05, 0.28), BONE)
		joint("Knee" .. sd, upper, lower, CFrame.new(0, -0.55, 0.02), CFrame.new(0, 0.52, 0))
		local foot = part("Foot" .. sd, Vector3.new(0.38, 0.2, 0.8), BONE_L)
		joint("Ankle" .. sd, lower, foot, CFrame.new(0, -0.54, -0.16))
	end

	-- See SKELETON_GRIP_ROT above for why this rotation looks the way it does.
	local HALF_FIST = 0.32 / 2
	local GUARD_H, POMMEL_H, BLADE_H = 0.11, 0.16, 1.5
	-- Short on purpose: a fist covers a hilt, so a longer grip only shows as
	-- bare leather sticking out above or below the hand.
	local grip = part("SwordGrip", Vector3.new(0.17, 0.4, 0.17), LEATHER, Enum.Material.Fabric)
	joint("Grip", handR, grip, SKELETON_GRIP_ROT)
	local pommel = part("SwordPommel", Vector3.new(0.19, POMMEL_H, 0.19), IRON, Enum.Material.Metal)
	joint("Pommel", grip, pommel, CFrame.new(0, HALF_FIST + 0.02 + POMMEL_H / 2, 0))
	-- Guard is kept close to the fist's own width. At 0.58 across a 0.30 fist
	-- its quillons overhung the hand and the crossguard read as detached.
	local guard = part("SwordGuard", Vector3.new(0.44, GUARD_H, 0.15), IRON, Enum.Material.Metal)
	joint("Guard", grip, guard, CFrame.new(0, -(HALF_FIST + 0.02 + GUARD_H / 2), 0))
	for i, sx in ipairs({ -1, 1 }) do
		local quillon = part("Quillon" .. i, Vector3.new(0.1, 0.15, 0.13), IRON, Enum.Material.Metal)
		joint("Quillon" .. i, guard, quillon,
			CFrame.new(sx * 0.2, -0.055, 0) * CFrame.Angles(0, 0, math.rad(sx * 16)))
	end
	-- Blade steel is deliberately far from bone. At 158 grey it sat within a few
	-- values of the ribs and read as another bone at any distance.
	local blade = part("SwordBlade", Vector3.new(0.24, BLADE_H, 0.08), STEEL, Enum.Material.Metal)
	-- Sits flush on the guard, so moving the guard moves the blade with it.
	joint("Blade", guard, blade, CFrame.new(0, -(GUARD_H / 2 + BLADE_H / 2), 0))
	local fuller = part("SwordFuller", Vector3.new(0.08, 1.3, 0.1), FULLER, Enum.Material.Metal)
	joint("Fuller", blade, fuller, CFrame.new(0, 0.02, 0))
	local point = part("SwordTip", Vector3.new(0.24, 0.3, 0.08), STEEL, Enum.Material.Metal)
	joint("Tip", blade, point, CFrame.new(0, -(BLADE_H / 2 + 0.15), 0))
	for i = 1, 2 do
		local chip = part("SwordChip" .. i, Vector3.new(0.1, 0.13, 0.11), RUST, Enum.Material.Metal)
		joint("Chip" .. i, blade, chip, CFrame.new(0.15, 0.42 - i * 0.55, 0))
	end

	--[[ The sword hand WRAPS the hilt. Straight forward-pointing fingers left the
	     grip passing through an unbroken block, so nothing appeared to hold it.
	     These directions are derived from the grip's own axis rather than typed
	     in: the hand is rotated by the whole arm chain, so world-axis guesses
	     are meaningless here — the same trap as measuring a rotated building's
	     footprint on world axes. ]]
	local gripAxis = SKELETON_GRIP_ROT.UpVector
	local across = Vector3.new(0, 0, -1):Cross(gripAxis)
	if across.Magnitude < 0.05 then
		across = Vector3.new(1, 0, 0):Cross(gripAxis)
	end
	across = across.Unit
	local outward = gripAxis:Cross(across).Unit
	-- Point `outward` away from the wrist, i.e. away from the hand's own +Y.
	if outward.Y > 0 then
		outward = -outward
		across = -across
	end
	local function wrap(name: string, size: Vector3, offset: Vector3, dir: Vector3)
		local p = part(name, size, BONE_L)
		joint(name, handR, p, CFrame.fromMatrix(offset, dir, dir:Cross(gripAxis).Unit))
		return p
	end
	for i, t in ipairs({ 0.10, 0.005, -0.09 }) do
		wrap("FingerR" .. i, Vector3.new(0.20, 0.075, 0.075), gripAxis * t + outward * 0.115, across)
	end
	-- The thumb crosses from the other side and overlaps the top finger; that
	-- overlap is what actually reads as a closed grip.
	wrap("ThumbR", Vector3.new(0.17, 0.08, 0.08),
		gripAxis * 0.055 + outward * 0.055 - across * 0.075,
		(across * 0.55 + gripAxis * 0.83).Unit)

	--[[ A small, well-used shield. Three things this went through, and should
	     not go through again:
	       * It must be ROUND. A board taller than it is wide stays oblong
	         however the planks are cut, and reads as a coffin lid.
	       * The root board is INVISIBLE. A square backing behind a circular run
	         of planks shows its corners as a dark slab bolted on behind.
	       * The break is a real hole. A transparent "mask" part subtracts
	         nothing, and a disc backer quietly fills the damage back in — so the
	         back is boarded with the SAME cuts as the front. A roundness test
	         once passed precisely BECAUSE the damage had been filled in;
	         measure the hole, not the circle. ]]
	local board = part("ShieldBoard", Vector3.new(0.3, 0.3, 0.06), WOOD_BACK)
	board.Transparency = 1
	joint("ShieldGrip", handL, board,
		CFrame.new(-0.051, -0.023, -0.16)
			* CFrame.Angles(math.rad(-45.8), math.rad(14.6), math.rad(19.4)))

	local R, NP = 0.78, 7
	local W = (R * 2) / NP
	-- Fraction smashed off each plank, rising into the lower-right corner.
	local CUT = { 0, 0, 0, 0, 0.40, 0.70, 0.94 }
	for i = 1, NP do
		local x = -R + W * (i - 0.5)
		local hh = 2 * math.sqrt(math.max(0.02, R * R - x * x))
		local top, bottom = hh / 2, -hh / 2 + hh * CUT[i]
		if top - bottom > 0.14 then
			local face = part("ShieldPlank" .. i, Vector3.new(W - 0.015, top - bottom, 0.1),
				if i % 2 == 0 then WOOD_A else WOOD_B, Enum.Material.Wood)
			joint("Plank" .. i, board, face, CFrame.new(x, (top + bottom) / 2, -0.08))
			local back = part("ShieldBack" .. i, Vector3.new(W - 0.01, top - bottom, 0.07),
				WOOD_BACK, Enum.Material.Wood)
			joint("Back" .. i, board, back, CFrame.new(x, (top + bottom) / 2, 0.02))
			if CUT[i] > 0 then
				local splint = part("ShieldSplinter" .. i, Vector3.new(W - 0.06, 0.15, 0.12),
					WOOD_SPLINT, Enum.Material.Wood)
				joint("Splinter" .. i, board, splint,
					CFrame.new(x + 0.015, bottom - 0.04, -0.04)
						* CFrame.Angles(0, 0, math.rad(if i == 7 then 30 else -20)))
			end
		end
	end
	for i, y in ipairs({ 0.34, -0.30 }) do
		local batten = part("ShieldBatten" .. i, Vector3.new(1.3, 0.14, 0.08), WOOD_BACK, Enum.Material.Wood)
		joint("Batten" .. i, board, batten, CFrame.new(0, y, 0.07))
	end
	--[[ Rim segments lie ALONG the edge — the long axis is the chord and the
	     thin one is radial. Sized the other way up, every one sticks outward and
	     the rim reads as a spiked fringe. It runs the whole circle EXCEPT over
	     the break, so its absence reads as damage rather than as missing work. ]]
	local STEP = 12
	local chord = 2 * R * math.sin(math.rad(STEP) / 2) + 0.045
	for deg = 0, 359, STEP do
		if not (deg > 250 and deg < 350) then
			local a = math.rad(deg)
			local seg = part(string.format("ShieldRim_%d", deg), Vector3.new(chord, 0.1, 0.19),
				if deg % 48 == 0 then RUST else IRON, Enum.Material.Metal)
			joint(string.format("Rim_%d", deg), board, seg,
				CFrame.new(math.cos(a) * R, math.sin(a) * R, -0.045)
					* CFrame.Angles(0, 0, a + math.pi / 2))
		end
	end
	-- A Cylinder's axis is local X, so a 90-degree turn about Y faces it forward.
	local bossRing = part("ShieldBossRim", Vector3.new(0.09, 0.58, 0.58), RUST, Enum.Material.Metal)
	bossRing.Shape = Enum.PartType.Cylinder
	joint("BossRing", board, bossRing, CFrame.new(0, 0.04, -0.11) * CFrame.Angles(0, math.rad(90), 0))
	local boss = part("ShieldBoss", Vector3.new(0.44, 0.44, 0.44), IRON, Enum.Material.Metal)
	boss.Shape = Enum.PartType.Ball
	joint("Boss", board, boss, CFrame.new(0, 0.04, -0.2))
	local strap = part("ShieldStrap", Vector3.new(0.62, 0.12, 0.08), LEATHER, Enum.Material.Fabric)
	joint("Strap", board, strap, CFrame.new(0, 0.02, 0.1))

	-- Apply the rest pose, then record it. Everything downstream poses relative
	-- to these, so they must be written before anything animates.
	for name, r in pairs(SKELETON_REST) do
		local m = joints[name]
		if m then
			m.C0 = m.C0 * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		end
	end
	for _, m in pairs(joints) do
		m:SetAttribute("RestC0", m.C0)
	end

	return model, joints, EnemyRigs.SkeletonHipHeight * scale
end

return EnemyRigs
