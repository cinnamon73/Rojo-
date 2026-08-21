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
	`u` runs 0..1 over one swing.

	These two are shared with BOTH sides deliberately. The client uses the
	duration to pace the animation; the server multiplies them together to work
	out when the club actually connects, so damage lands on the blow rather
	than the moment the swing starts. If they ever live in two places they will
	drift and the hit will stop matching the picture.
]]
EnemyAnimation.AttackDuration = 1.05
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


--========================================================================
-- Skeleton
--========================================================================

--[[
	THE SKELETON CANNOT SHARE THE GOBLIN'S SWING, and this is the reason to
	keep the two sets apart rather than adding a flag.

	The goblin's club hangs POINT-DOWN from its fist. The skeleton's sword is
	held POINT-UP. That inverts the weapon relative to the hand, so the very
	same shoulder arc that raised the club in front of the goblin throws the
	sword back over the skeleton's shoulder. Measured at the top of the goblin
	raise, driving this rig: the blade ended up 1.06 studs BEHIND the skull and
	143 degrees from vertical. It is the same bug that made the goblin's first
	attack look broken, arriving by a completely different route.

	THE SLASH MAP, MEASURED, NOT GUESSED. Sweeping each axis and recording where
	the sword TIP landed relative to the root gave this:

		ShoulderR Y  ->  swings the arm ACROSS the body. This is the slash axis.
		                 -60 = cocked out right (side +1.32, forward -0.05)
		                 +60 = swept to the front (side +0.60, forward +0.77)
		ShoulderR Z  ->  raises the arm and starts laying the blade over.
		WristR    Z  ->  ROLLS the blade flat. -90 takes it to 89 degrees from
		                 vertical. Pitching the wrist (X) does NOT do this — a
		                 whole pass was lost trying, and never got the blade past
		                 57 degrees.
		Waist+Spine Y -> the torso turn, which supplies most of the reach:
		                 +40 of yaw moves the tip from 0.57 to 1.24 forward.

	Independent sweeps DO NOT COMPOSE — rotations multiply — so the impact frame
	below was grid-searched as whole poses (108 of them) rather than assembled
	from the numbers above. It lands the blade 77 degrees from vertical with the
	tip 2.79 studs in front at chest height, crossing the centre line to within
	0.01.
]]

local Skeleton = {}

-- The impact frame, and the two poses either side of it.
local S_IMPACT = { shX = -50, shY = 45, shZ = 75, wrZ = -80, torso = 24 }
local S_WIND = { shX = -20, shY = -55, shZ = 55, wrZ = -60, torso = -18 }
local S_FOLLOW = { shX = -55, shY = 88, shZ = 62, wrZ = -85, torso = 12 }

--[[
	Shared with the server, which times the damage off the same numbers so the
	blow lands when the blade actually sweeps through rather than when the
	wind-up starts. If these ever live in two places they will drift and the hit
	will stop matching the picture.
]]
Skeleton.AttackDuration = 1.15
Skeleton.AttackImpactPhase = 0.46

--[[
	Idle: a sword-and-board ready stance, not the goblin's loose amble. A
	skeleton has no lungs, so there is no breathing rise and fall — just weight
	shifting, a little drift, and an occasional jaw twitch.

	The shield joint barely rotates because the arm is braced, but note the
	BOARD still travels further than the head does: it hangs far out on the arm
	and leverage amplifies small shoulder angles. If the shield ever looks like
	it is drifting, damp the shoulder, not the shield.
]]
function Skeleton.Idle(joints: Joints, t: number, drop: number)
	local br = math.sin(t * 1.5)
	local sway = math.sin(t * 0.6)
	set(joints, "Pelvis", 0, sway * 1.8, sway * 1.2, drop)
	set(joints, "Waist", br * 1.2, sway * 2.5, 0)
	set(joints, "Spine", br * 1.0, sway * 1.5, 0)
	set(joints, "Neck", -br * 1.2, -sway * 3, 0)
	set(joints, "Head", br * 0.8, -sway * 4, 0)
	set(joints, "ShoulderR", br * 2.0, sway * 2.5, 0)
	set(joints, "ElbowR", -br * 2.5, 0, 0)
	set(joints, "WristR", 0, 0, 0)
	set(joints, "ShoulderL", -6 + br * 1.0, 0, -4)
	set(joints, "ElbowL", 8 - br * 1.5, 0, 0)
	for _, s in ipairs({ "L", "R" }) do
		set(joints, "Hip" .. s, 0, 0, 0)
		set(joints, "Knee" .. s, 0, 0, 0)
		set(joints, "Ankle" .. s, 0, 0, 0)
	end
	set(joints, "Jaw", if math.sin(t * 0.45) > 0.97 then 12 else 0, 0, 0)
end

--[[
	Walk: stiff and bony. The knee bends only on the leg that is LIFTING —
	bending both throws the planted foot off the ground and the whole body
	appears to float. The shield arm is braced forward rather than swinging, and
	the sword arm swings little because it is holding a blade upright.
]]
function Skeleton.Walk(joints: Joints, t: number, drop: number)
	local p = t * 5.8
	local s, c = math.sin(p), math.cos(p)
	set(joints, "Pelvis", 0, s * 4, c * 2.5, drop)
	set(joints, "Waist", -math.abs(c) * 2.5, -s * 4, 0)
	set(joints, "Spine", -math.abs(c) * 1.5, -s * 2, 0)
	set(joints, "Neck", math.abs(c) * 2, -s * 3, 0)
	set(joints, "Head", 0, -s * 3, 0)
	set(joints, "HipL", -s * 26, 0, 0)
	set(joints, "HipR", s * 26, 0, 0)
	set(joints, "KneeL", math.max(0, s) * 40, 0, 0)
	set(joints, "KneeR", math.max(0, -s) * 40, 0, 0)
	set(joints, "AnkleL", s * 8, 0, 0)
	set(joints, "AnkleR", -s * 8, 0, 0)
	set(joints, "ShoulderL", -14 + s * 4, 0, -10)
	set(joints, "ElbowL", 14, 0, 0)
	set(joints, "ShoulderR", -s * 9, s * 5, 0)
	set(joints, "ElbowR", -math.abs(s) * 5, 0, 0)
	set(joints, "WristR", 0, 0, 0)
	set(joints, "Jaw", 0, 0, 0)
end

--[[
	Attack: a horizontal SLASH, not an overhead chop. `u` runs 0..1 over one
	swing. The torso turn is doing most of the work — the arm alone cannot
	reach — and the wrist roll is what keeps the edge leading through the sweep.
]]
function Skeleton.Attack(joints: Joints, u: number, drop: number)
	local shX, shY, shZ, wrZ, torso, el
	if u < 0.30 then
		-- Wind up: cock back over the right shoulder, turning away from the target.
		local k = smooth(u / 0.30)
		shX, shY, shZ = lerp(0, S_WIND.shX, k), lerp(0, S_WIND.shY, k), lerp(0, S_WIND.shZ, k)
		wrZ, torso, el = lerp(0, S_WIND.wrZ, k), lerp(0, S_WIND.torso, k), lerp(0, -12, k)
	elseif u < Skeleton.AttackImpactPhase then
		-- The sweep. Accelerating, torso turning INTO the blow.
		local k = accel((u - 0.30) / (Skeleton.AttackImpactPhase - 0.30))
		shX, shY, shZ = lerp(S_WIND.shX, S_IMPACT.shX, k), lerp(S_WIND.shY, S_IMPACT.shY, k), lerp(S_WIND.shZ, S_IMPACT.shZ, k)
		wrZ, torso, el = lerp(S_WIND.wrZ, S_IMPACT.wrZ, k), lerp(S_WIND.torso, S_IMPACT.torso, k), lerp(-12, 0, k)
	elseif u < 0.64 then
		-- Follow through past the target before recovering.
		local k = smooth((u - Skeleton.AttackImpactPhase) / (0.64 - Skeleton.AttackImpactPhase))
		shX, shY, shZ = lerp(S_IMPACT.shX, S_FOLLOW.shX, k), lerp(S_IMPACT.shY, S_FOLLOW.shY, k), lerp(S_IMPACT.shZ, S_FOLLOW.shZ, k)
		wrZ, torso, el = lerp(S_IMPACT.wrZ, S_FOLLOW.wrZ, k), lerp(S_IMPACT.torso, S_FOLLOW.torso, k), lerp(0, 8, k)
	else
		local k = smooth((u - 0.64) / 0.36)
		shX, shY, shZ = lerp(S_FOLLOW.shX, 0, k), lerp(S_FOLLOW.shY, 0, k), lerp(S_FOLLOW.shZ, 0, k)
		wrZ, torso, el = lerp(S_FOLLOW.wrZ, 0, k), lerp(S_FOLLOW.torso, 0, k), lerp(8, 0, k)
	end
	set(joints, "Pelvis", 0, torso * 0.35, 0, drop)
	set(joints, "Waist", 0, torso * 0.5, 0)
	set(joints, "Spine", 0, torso * 0.5, 0)
	set(joints, "Neck", 0, -torso * 0.25, 0)
	set(joints, "Head", 0, -torso * 0.30, 0)
	set(joints, "ShoulderR", shX, shY, shZ)
	set(joints, "ElbowR", el, 0, 0)
	set(joints, "WristR", 0, 0, wrZ)
	-- Shield sweeps across to cover as the sword arm goes back, then braces.
	set(joints, "ShoulderL", -8 - torso * 0.4, 0, -6 - torso * 0.25)
	set(joints, "ElbowL", 12 + torso * 0.3, 0, 0)
	-- Plant and pivot: the leading leg takes the turn.
	set(joints, "HipL", -torso * 0.30, 0, 0)
	set(joints, "HipR", torso * 0.30, 0, 0)
	set(joints, "KneeL", math.abs(torso) * 0.5, 0, 0)
	set(joints, "KneeR", math.abs(torso) * 0.35, 0, 0)
	set(joints, "Jaw", math.max(0, torso) * 0.6, 0, 0)
end

-- The recoil is body-wide and weapon-agnostic, so it is genuinely shared.
Skeleton.Flinch = EnemyAnimation.Flinch

--========================================================================
-- Dispatch
--========================================================================

export type Set = {
	Idle: (Joints, number, number) -> (),
	Walk: (Joints, number, number) -> (),
	Attack: (Joints, number, number) -> (),
	Flinch: (Joints, number, number) -> (),
	AttackDuration: number,
	AttackImpactPhase: number,
}

--[[
	One entry per articulated rig, keyed by the `Rig` name in EnemyConfig. The
	top-level EnemyAnimation.Idle/Walk/Attack above remain the goblin's, so
	anything that has not been taught about sets still behaves exactly as before.
]]
-- Declared as locals first: Luau will not parse a `::` cast applied to a table
-- constructor that is itself a field of another table.
local GoblinSet: Set = {
	Idle = EnemyAnimation.Idle,
	Walk = EnemyAnimation.Walk,
	Attack = EnemyAnimation.Attack,
	Flinch = EnemyAnimation.Flinch,
	AttackDuration = EnemyAnimation.AttackDuration,
	AttackImpactPhase = EnemyAnimation.AttackImpactPhase,
}
local SkeletonSet: Set = {
	Idle = Skeleton.Idle,
	Walk = Skeleton.Walk,
	Attack = Skeleton.Attack,
	Flinch = Skeleton.Flinch,
	AttackDuration = Skeleton.AttackDuration,
	AttackImpactPhase = Skeleton.AttackImpactPhase,
}

EnemyAnimation.Sets = {
	Goblin = GoblinSet,
	Skeleton = SkeletonSet,
}

--[[
	Returns the pose set for a rig name. An unknown or missing name falls back
	to the goblin's rather than erroring — a typo in a config should make an
	enemy animate oddly, not stop the client's animation loop for every enemy
	on screen.
]]
function EnemyAnimation.Get(rigName: string?): Set
	if rigName then
		local found = EnemyAnimation.Sets[rigName]
		if found then
			return found
		end
	end
	return EnemyAnimation.Sets.Goblin
end

return EnemyAnimation
