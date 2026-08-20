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

return EnemyRigs
