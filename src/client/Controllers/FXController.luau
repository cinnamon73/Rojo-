--!strict
--[[
	FXController — every client renders combat presentation locally.

	The server announces tiny events on the FXEvent bus ({Kind, UserId, ...});
	this file turns them into motion and light. The reason it exists is painful
	experience: a 0.07s strike tweened on the server arrives as one or two
	network snapshots and reads as teleporting. Rendered here, every machine
	gets full-framerate animation for every player on screen.

	THE SWING GRAMMAR (Monster Hunter rules)
	----------------------------------------
	Three acts with wildly asymmetric timing — anticipation (weapon rises,
	torso winds), a near-instant strike, and a long recovery. The strike is
	deliberately too fast to track; the blade Trail (built into every melee
	weapon, enabled only during strike frames) paints the arc so the eye reads
	a ribbon instead of a blur. Weight comes from the timing ratio, not from
	slowing anything down.

	Poses are RELATIVE offsets applied to cached joint C0s (shoulder, waist)
	plus the grip weld C1. Offsets rather than absolute poses because the
	Animator owns Transform, not C0 — so these layer over the walk animation
	instead of fighting it, and restoring is just writing the cached original
	back.

	Every animation is cancellable: a new swing on the same character bumps a
	token and the previous acts stop touching the joints. Without that, three
	fast attacks queue three recoveries and the arm rubber-bands.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local VFX = require(Modules.VFX)

local log = Logger.new("FXController")
local localPlayer = Players.LocalPlayer

local FXController = {}

--========================================================================
-- Timing profiles
--========================================================================

type Profile = {
	Anticipation: number,
	Strike: number,
	Recovery: number,
	-- How long the trail keeps painting after the strike lands.
	TrailLinger: number,
	-- Scales the pose angles: heavies swing bigger.
	Reach: number,
}

local PROFILES: { [string]: Profile } = {
	Greataxe = { Anticipation = 0.30, Strike = 0.07, Recovery = 0.45, TrailLinger = 0.25, Reach = 1.25 },
	Greatsword = { Anticipation = 0.30, Strike = 0.07, Recovery = 0.45, TrailLinger = 0.25, Reach = 1.25 },
	Sword = { Anticipation = 0.12, Strike = 0.08, Recovery = 0.22, TrailLinger = 0.15, Reach = 1.0 },
	PaladinBlade = { Anticipation = 0.12, Strike = 0.08, Recovery = 0.22, TrailLinger = 0.15, Reach = 1.0 },
	RoyalBlade = { Anticipation = 0.12, Strike = 0.08, Recovery = 0.22, TrailLinger = 0.15, Reach = 1.0 },
	Dagger = { Anticipation = 0.03, Strike = 0.05, Recovery = 0.10, TrailLinger = 0.10, Reach = 0.8 },
}

-- Ranged weapons get a recoil action, not an arc.
local RANGED_PROFILE: Profile =
	{ Anticipation = 0.04, Strike = 0.07, Recovery = 0.18, TrailLinger = 0, Reach = 1.0 }

--[[
	Combo poses as (shoulder, waist, grip) angle triples, per act.

	Step 1: horizontal slash right-to-left. Step 2: rising backhand the other
	way. Step 3: full overhead crash. Distinct silhouettes are the point — a
	combo whose steps look alike is one attack with extra bookkeeping.
]]
type Pose = { Shoulder: CFrame, Waist: CFrame, Grip: CFrame }
type StepPoses = { Wind: Pose, Hit: Pose }

local function pose(sx: number, sy: number, sz: number, w: number, gx: number, gz: number): Pose
	return {
		Shoulder = CFrame.Angles(math.rad(sx), math.rad(sy), math.rad(sz)),
		Waist = CFrame.Angles(0, math.rad(w), 0),
		Grip = CFrame.Angles(math.rad(gx), 0, math.rad(gz)),
	}
end

local MELEE_STEPS: { StepPoses } = {
	-- 1: wind right and high, sweep hard left.
	{ Wind = pose(-60, 0, -35, 18, -30, -20), Hit = pose(70, 0, 45, -16, -70, 40) },
	-- 2: wind left and low, rising backhand right.
	{ Wind = pose(-40, 0, 40, -16, -20, 25), Hit = pose(55, 0, -50, 14, -55, -45) },
	-- 3: wind straight up behind the head, crash down.
	{ Wind = pose(-95, 0, 0, 0, -50, 0), Hit = pose(85, 0, 10, 0, -110, 5) },
}

local RANGED_STEP: StepPoses =
	{ Wind = pose(-8, 0, 0, 4, -6, 0), Hit = pose(14, 0, 4, -6, 12, 0) }

--========================================================================
-- Rig plumbing
--========================================================================

type Rig = {
	Shoulder: Motor6D?,
	Waist: Motor6D?,
	Grip: Weld?,
	ShoulderC0: CFrame,
	WaistC0: CFrame,
	GripC1: CFrame,
	Token: number,
}

local rigs: { [Model]: Rig } = {}

--[[
	Finds and caches the joints for a character. Cached ORIGINAL C0s are the
	restore point for every animation; re-resolved whenever the instances have
	died (respawn, weapon swap).
]]
local function getRig(character: Model): Rig?
	local cached = rigs[character]
	if cached and cached.Grip and cached.Grip.Parent then
		return cached
	end

	local upperArm = character:FindFirstChild("RightUpperArm")
	local upperTorso = character:FindFirstChild("UpperTorso")
	local hand = character:FindFirstChild("RightHand")

	local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	local grip = hand and hand:FindFirstChild("RightGrip")

	if not grip or not grip:IsA("Weld") then
		return nil
	end

	local rig: Rig = {
		Shoulder = if shoulder and shoulder:IsA("Motor6D") then shoulder else nil,
		Waist = if waist and waist:IsA("Motor6D") then waist else nil,
		Grip = grip,
		ShoulderC0 = if shoulder and shoulder:IsA("Motor6D") then shoulder.C0 else CFrame.new(),
		WaistC0 = if waist and waist:IsA("Motor6D") then waist.C0 else CFrame.new(),
		GripC1 = grip.C1,
		Token = (cached and cached.Token or 0),
	}

	rigs[character] = rig
	return rig
end

local function applyPose(rig: Rig, p: Pose, reach: number, info: TweenInfo)
	--[[
		Reach < 1 shrinks the pose toward identity (dagger jabs are compact).
		Reach >= 1 uses the pose as authored: extrapolating a CFrame lerp past
		1 is undefined enough not to trust, so heavies get their weight from
		TIMING (long anticipation, long recovery), not from bigger angles.
	]]
	local function scale(offset: CFrame): CFrame
		if reach >= 1 then
			return offset
		end
		return CFrame.identity:Lerp(offset, reach)
	end

	if rig.Shoulder then
		TweenService:Create(rig.Shoulder, info, { C0 = rig.ShoulderC0 * scale(p.Shoulder) }):Play()
	end
	if rig.Waist then
		TweenService:Create(rig.Waist, info, { C0 = rig.WaistC0 * scale(p.Waist) }):Play()
	end
	if rig.Grip then
		-- Weld maths: rest C1 is gripPose⁻¹, and (C1⁻¹ · offset)⁻¹ = offset⁻¹ · C1
		-- puts the weapon at rest-pose-then-offset. Verified live once already;
		-- do not "simplify" without re-deriving.
		TweenService:Create(rig.Grip, info, { C1 = (rig.GripC1:Inverse() * scale(p.Grip)):Inverse() }):Play()
	end
end

local function restore(rig: Rig, info: TweenInfo)
	if rig.Shoulder then
		TweenService:Create(rig.Shoulder, info, { C0 = rig.ShoulderC0 }):Play()
	end
	if rig.Waist then
		TweenService:Create(rig.Waist, info, { C0 = rig.WaistC0 }):Play()
	end
	if rig.Grip then
		TweenService:Create(rig.Grip, info, { C1 = rig.GripC1 }):Play()
	end
end

--========================================================================
-- The swing
--========================================================================

local function setTrail(character: Model, enabled: boolean)
	local tool = character:FindFirstChildOfClass("Tool")
	local trail = tool and tool:FindFirstChild("SwingTrail", true)
	if trail and trail:IsA("Trail") then
		trail.Enabled = enabled
	end
end

local function animateSwing(character: Model, archetype: string, step: number)
	local rig = getRig(character)
	if not rig then
		return
	end

	local profile = PROFILES[archetype] or RANGED_PROFILE
	local steps = if PROFILES[archetype] then MELEE_STEPS else { RANGED_STEP }
	local acts = steps[((step - 1) % #steps) + 1]

	rig.Token += 1
	local token = rig.Token

	-- TEMP diagnostic: one line per swing saying whether the body joints were
	-- found. shoulder=false is the difference between swordplay and a wrist
	-- flick, and it fails silently otherwise. Remove once poses are approved.
	log:Info("swing %s step %d shoulder=%s waist=%s",
		archetype, step, tostring(rig.Shoulder ~= nil), tostring(rig.Waist ~= nil))

	-- Act 1: anticipation. Ease out so the weapon decelerates into the wound
	-- pose — a linear rise reads as a robot arm.
	applyPose(rig, acts.Wind, profile.Reach,
		TweenInfo.new(profile.Anticipation, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))

	task.delay(profile.Anticipation, function()
		if rig.Token ~= token then
			return
		end

		-- Act 2: the strike. Back easing overshoots past the end pose and
		-- settles — the overshoot IS the follow-through.
		setTrail(character, true)
		applyPose(rig, acts.Hit, profile.Reach,
			TweenInfo.new(profile.Strike, Enum.EasingStyle.Back, Enum.EasingDirection.Out))

		task.delay(profile.Strike + profile.TrailLinger, function()
			if rig.Token == token then
				setTrail(character, false)
			end
		end)

		-- Act 3: recovery, slow settle home.
		task.delay(profile.Strike + 0.04, function()
			if rig.Token ~= token then
				return
			end
			restore(rig, TweenInfo.new(profile.Recovery, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end)
	end)
end

--========================================================================
-- Impacts
--========================================================================

local DEFAULT_FOV = 70

--[[
	Camera punch for the local attacker's own hits: a quick FOV kick that
	springs back. Relative to the current FOV so it composes with aim-zoom
	instead of fighting it.
]]
local function cameraPunch(strength: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local from = camera.FieldOfView
	camera.FieldOfView = from - strength
	TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = from,
	}):Play()
end

local function onImpact(payload: any)
	if typeof(payload.Pos) ~= "Vector3" then
		return
	end

	local theme = if typeof(payload.Theme) == "Color3" then payload.Theme else Color3.new(1, 1, 1)

	if payload.Ranged and typeof(payload.From) == "Vector3" then
		VFX.Tracer(payload.From, payload.Pos, theme)
	end

	VFX.Burst(payload.Pos, theme, if payload.Crit then 1.5 else 0.9)

	if payload.UserId == localPlayer.UserId then
		cameraPunch(if payload.Crit then 4 else 2)
	end
end

--========================================================================
-- Routing
--========================================================================

local handlers: { [string]: (any) -> () } = {}

handlers.Swing = function(payload)
	local player = Players:GetPlayerByUserId(tonumber(payload.UserId) or 0)
	local character = player and player.Character
	if character then
		animateSwing(character, tostring(payload.Archetype), tonumber(payload.Step) or 1)
	end
end

handlers.Impact = onImpact

function FXController.Start(_client: any)
	local fx = Remotes.Get("FXEvent") :: RemoteEvent

	fx.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or type(payload.Kind) ~= "string" then
			return
		end

		local handler = handlers[payload.Kind]
		if handler then
			-- One bad payload must not kill the bus for the session.
			local ok, err = pcall(handler, payload)
			if not ok then
				log:Warn("%s handler failed: %s", payload.Kind, tostring(err))
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			rigs[player.Character] = nil
		end
	end)

	log:Info("ready (%d handlers)", (function()
		local n = 0
		for _ in pairs(handlers) do
			n += 1
		end
		return n
	end)())
end

return FXController
