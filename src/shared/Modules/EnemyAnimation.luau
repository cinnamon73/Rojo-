--!strict
--[[
	EnemyAnimation — pose tables for the articulated enemy rigs.

	Every number here is an OFFSET IN DEGREES from the joint's rest pose, which
	`EnemyRigs` stored as a `RestC0` attribute. Applying a pose is always:

		joint.C0 = restC0 * CFrame.Angles(...)

	never a compounding multiply onto the live C0.

	THE SHOULDER MAP, MEASURED, NOT GUESSED.
	Sweeping ShoulderR and recording where the club head ended up relative to
	the root gave this, and it is the whole reason the attack works:

		  0 deg  ->  hanging at the side   (height -1.8, forward -1.7)
		 40 deg  ->  swung forward         (height -2.6, forward +0.7)
		 70 deg  ->  DOWN AND FORWARD      (height -2.4, forward +1.9)  <- impact
		120 deg  ->  up and forward        (height +0.4, forward +4.1)
		190 deg  ->  HIGH IN FRONT         (height +4.4, forward +1.6)  <- raised

	Negative angles are the far half of the circle: they take the club up BEHIND
	the head, and swinging back down from there drags it through the goblin's
	body. The first attack did exactly that and looked broken. Raise through
	POSITIVE angles and the club stays in front for the whole swing.

	The elbow and wrist are not decoration. With the elbow near-static the club
	is held far from the body and the shoulder has to wrap ~200 degrees to
	compensate; and because `Grip` holds the club at a fixed angle to the hand,
	the club TRAILS unless the wrist uncocks. Both are animated here.
]]

local EnemyAnimation = {}

export type Joints = { [string]: Motor6D }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end
-- Eased both ends: for poses that settle.
local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end
-- Slow start, fast finish: for the chop, so it hangs at the top then drops.
local function accel(t: number): number
	return t * t
end

--[[
	Applies one joint. `rest` comes from the attribute; if it is missing the
	joint is skipped rather than posed from a wrong origin.
]]
local function set(joints: Joints, name: string, rx: number?, ry: number?, rz: number?, dy: number?)
	local m = joints[name]
	if not m then
		return
	end
	local rest = m:GetAttribute("RestC0")
	if typeof(rest) ~= "CFrame" then
		return
	end
	local base = rest :: CFrame
	if dy and dy ~= 0 then
		base = base * CFrame.new(0, dy, 0)
	end
	m.C0 = base * CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

function EnemyAnimation.Idle(joints: Joints, t: number, drop: number)
	local breath = math.sin(t * 2.0)
	local sway = math.sin(t * 0.85)
	set(joints, "Pelvis", 0, sway * 2, sway * 1.5, drop)
	set(joints, "Waist", breath * 2, sway * 2, 0)
	set(joints, "Spine", breath * 1.5, 0, 0)
	set(joints, "Neck", -breath * 2, -sway * 3, 0)
	set(joints, "Head", breath * 1.2, -sway * 3, 0)
	set(joints, "ShoulderL", breath * 2.5, 0, 0)
	set(joints, "ShoulderR", breath * 2, 0, 0)
	set(joints, "ElbowL", -breath * 3, 0, 0)
	set(joints, "ElbowR", -breath * 2, 0, 0)
	set(joints, "WristR", 0, 0, 0)
	for _, s in ipairs({ "L", "R" }) do
		set(joints, "Hip" .. s, 0, 0, 0)
		set(joints, "Knee" .. s, 0, 0, 0)
		set(joints, "Ankle" .. s, 0, 0, 0)
	end
	set(joints, "Ear1", breath * 5, 0, 0)
	set(joints, "Ear2", -breath * 5, 0, 0)
	set(joints, "Jaw", 0, 0, 0)
end

--[[
	Walk. The knee bends only on the leg that is LIFTING; bending both throws
	the planted foot off the ground and the whole body appears to float.
]]
function EnemyAnimation.Walk(joints: Joints, t: number, drop: number)
	local p = t * 6.4
	local s, c = math.sin(p), math.cos(p)
	set(joints, "Pelvis", 0, s * 5, c * 3, drop)
	set(joints, "Waist", -math.abs(c) * 3, -s * 3, 0)
	set(joints, "Spine", -math.abs(c) * 2, 0, 0)
	set(joints, "Neck", math.abs(c) * 2, -s * 4, 0)
	set(joints, "Head", 0, -s * 4, 0)
	set(joints, "HipL", -s * 24, 0, 0)
	set(joints, "HipR", s * 24, 0, 0)
	set(joints, "KneeL", math.max(0, s) * 44, 0, 0)
	set(joints, "KneeR", math.max(0, -s) * 44, 0, 0)
	set(joints, "AnkleL", s * 10, 0, 0)
	set(joints, "AnkleR", -s * 10, 0, 0)
	-- Arms counter-swing; the club arm swings less because it is carrying weight.
	set(joints, "ShoulderL", s * 24, 0, 0)
	set(joints, "ShoulderR", -s * 13, 0, 0)
	set(joints, "ElbowL", -math.max(0, -s) * 20, 0, 0)
	set(joints, "ElbowR", -math.abs(s) * 6, 0, 0)
	set(joints, "WristR", 0, 0, 0)
	set(joints, "Ear1", -s * 9, 0, 0)
	set(joints, "Ear2", s * 9, 0, 0)
	set(joints, "Jaw", 0, 0, 0)
end

-- Shoulder angles for the two ends of the swing. See the map in the header.
local RAISE = 190
local IMPACT = 70

--[[
	Attack: raise the club IN FRONT, then chop down fast.
	`u` runs 0..1 over one swing. The impact lands at u = 0.50.
]]
EnemyAnimation.AttackImpactPhase = 0.50

function EnemyAnimation.Attack(joints: Joints, u: number, drop: number)
	local sh, el, wr, spine, hip, head, jaw
	if u < 0.36 then
		-- Lift, deliberate. A small positive spine rocks back to load the blow.
		local k = smooth(u / 0.36)
		sh, el, wr = lerp(0, RAISE, k), lerp(0, -26, k), lerp(0, -22, k)
		spine, hip, head, jaw = lerp(0, 7, k), lerp(0, -5, k), lerp(0, 6, k), lerp(0, 6, k)
	elseif u < 0.50 then
		-- The chop. Accelerating, elbow extends, wrist snaps so the club leads.
		local k = accel((u - 0.36) / 0.14)
		sh, el, wr = lerp(RAISE, IMPACT, k), lerp(-26, 10, k), lerp(-22, 34, k)
		spine, hip, head, jaw = lerp(7, -24, k), lerp(-5, 13, k), lerp(6, -15, k), lerp(6, 16, k)
	elseif u < 0.72 then
		local k = smooth((u - 0.50) / 0.22)
		sh, el, wr = lerp(IMPACT, IMPACT - 16, k), lerp(10, 2, k), lerp(34, 16, k)
		spine, hip, head, jaw = lerp(-24, -15, k), lerp(13, 8, k), lerp(-15, -5, k), lerp(16, 4, k)
	else
		local k = smooth((u - 0.72) / 0.28)
		sh, el, wr = lerp(IMPACT - 16, 0, k), lerp(2, 0, k), lerp(16, 0, k)
		spine, hip, head, jaw = lerp(-15, 0, k), lerp(8, 0, k), lerp(-5, 0, k), lerp(4, 0, k)
	end
	set(joints, "Pelvis", 0, -5, 0, drop)
	set(joints, "Waist", spine * 0.55, 0, 0)
	set(joints, "Spine", spine, 0, 0)
	set(joints, "Neck", -head * 0.4, 0, 0)
	set(joints, "Head", head, 0, 0)
	set(joints, "ShoulderR", sh, 0, 0)
	set(joints, "ElbowR", el, 0, 0)
	set(joints, "WristR", wr, 0, 0)
	set(joints, "ShoulderL", -sh * 0.10, 0, -8)
	set(joints, "ElbowL", 0, 0, 0)
	set(joints, "HipL", -hip, 0, 0)
	set(joints, "HipR", hip, 0, 0)
	set(joints, "KneeL", math.abs(hip) * 1.4, 0, 0)
	set(joints, "KneeR", math.abs(hip), 0, 0)
	set(joints, "AnkleL", 0, 0, 0)
	set(joints, "AnkleR", 0, 0, 0)
	set(joints, "Jaw", jaw, 0, 0)
end

--[[
	Hit reaction: a short recoil. `u` runs 0..1 and it does not loop.
]]
function EnemyAnimation.Flinch(joints: Joints, u: number, drop: number)
	local k = if u < 0.3 then u / 0.3 else 1 - (u - 0.3) / 0.7
	k = math.clamp(k, 0, 1)
	set(joints, "Pelvis", 0, 0, 0, drop)
	set(joints, "Waist", k * 14, 0, k * 6)
	set(joints, "Spine", k * 10, 0, 0)
	set(joints, "Neck", k * 8, 0, 0)
	set(joints, "Head", k * 12, 0, 0)
	set(joints, "ShoulderL", -k * 20, 0, -k * 10)
	set(joints, "ShoulderR", -k * 16, 0, k * 10)
	set(joints, "ElbowL", -k * 24, 0, 0)
	set(joints, "ElbowR", -k * 20, 0, 0)
	set(joints, "HipL", k * 6, 0, 0)
	set(joints, "HipR", k * 6, 0, 0)
	set(joints, "KneeL", k * 16, 0, 0)
	set(joints, "KneeR", k * 16, 0, 0)
	set(joints, "Jaw", k * 18, 0, 0)
end

return EnemyAnimation
