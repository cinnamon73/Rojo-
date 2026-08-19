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

local Config = ReplicatedStorage:WaitForChild("Config")
local AnimationConfig = require(Config.AnimationConfig)

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
	-- Joint refs: {Target, Prop, Original}. Motor6D poses through its own C0;
	-- AnimationConstraint through its Attachment0's CFrame (C0 is read-only).
	Shoulder: any,
	Waist: any,
	Grip: Weld?,
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

	--[[
	    Recursive search, not a hard-coded path. The first version looked in
	    character.RightUpperArm/UpperTorso and came back nil on live rigs —
	    every swing logged shoulder=false and the body half of the animation
	    was silently absent, which read as "the same boring wrist flick". The
	    motors are found wherever the rig actually keeps them.
	]]
	local shoulder = character:FindFirstChild("RightShoulder", true)
	local waist = character:FindFirstChild("Waist", true)
	local hand = character:FindFirstChild("RightHand", true)
	local grip = hand and hand:FindFirstChild("RightGrip")

	--[[
		THE CLASS CHECK THAT COST A NIGHT. Live rigs here have ZERO Motor6Ds:
		the joints are AnimationConstraint instances (Roblox's newer joint
		system) with the same names, in the same parts, exposing the same
		C0/C1/Transform CFrames — measured live, not assumed. The original
		IsA("Motor6D") silently discarded them, the search "succeeded", the
		missing-joints warning stayed quiet, and the body half of every swing
		never ran. Accept both classes; never tighten this back to Motor6D.
	]]
	--[[
		A joint we can pose, reduced to (target instance, property, original).

		Motor6D: tween its own C0. AnimationConstraint: C0 is READ-ONLY —
		measured live, TweenService refuses it — because the constraint derives
		its frames from attachments. The writable equivalent is Attachment0's
		CFrame, which the Animator never touches (it writes Transform), so
		posing it layers over walk animations exactly like Motor6D C0 did.
	]]
	local function jointRef(x: Instance?): any
		if not x then
			return nil
		end
		if x:IsA("Motor6D") then
			return { Target = x, Prop = "C0", Original = x.C0 }
		end
		if x.ClassName == "AnimationConstraint" then
			local a0 = (x :: any).Attachment0
			if a0 then
				return { Target = a0, Prop = "CFrame", Original = a0.CFrame }
			end
		end
		return nil
	end

	-- If the joints are STILL missing, say what the rig actually contains —
	-- one paste of this line ends the guessing for good.
	if not shoulder or not waist then
		local names = {}
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("Motor6D") then
				table.insert(names, (d.Parent and d.Parent.Name or "?") .. "." .. d.Name)
			end
		end
		log:Warn("joints missing — Motor6Ds present: %s", table.concat(names, ", "))
	end

	if not grip or not grip:IsA("Weld") then
		return nil
	end

	local rig: Rig = {
		Shoulder = jointRef(shoulder),
		Waist = jointRef(waist),
		Grip = grip,
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
		TweenService:Create(rig.Shoulder.Target, info,
			{ [rig.Shoulder.Prop] = rig.Shoulder.Original * scale(p.Shoulder) }):Play()
	end
	if rig.Waist then
		TweenService:Create(rig.Waist.Target, info,
			{ [rig.Waist.Prop] = rig.Waist.Original * scale(p.Waist) }):Play()
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
		TweenService:Create(rig.Shoulder.Target, info,
			{ [rig.Shoulder.Prop] = rig.Shoulder.Original }):Play()
	end
	if rig.Waist then
		TweenService:Create(rig.Waist.Target, info,
			{ [rig.Waist.Prop] = rig.Waist.Original }):Play()
	end
	if rig.Grip then
		TweenService:Create(rig.Grip, info, { C1 = rig.GripC1 }):Play()
	end
end

--========================================================================
-- The swing
--========================================================================

--[[
	Uploaded keyframed swings.

	Animation INSTANCES are cached per id (they are just pointers), and loaded
	TRACKS per character+id, because LoadAnimation is not free and swings are
	the hottest path in the game. The previous track is stopped before the
	next plays — same-priority tracks blend otherwise and fast combos smear.
]]
local animationInstances: { [number]: Animation } = {}
local characterTracks: { [Model]: { [number]: AnimationTrack } } = {}
local currentTrack: { [Model]: AnimationTrack } = {}

local function getAnimation(id: number): Animation
	local cached = animationInstances[id]
	if cached then
		return cached
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = "rbxassetid://" .. tostring(id)
	animationInstances[id] = animation
	return animation
end

local function playUploaded(character: Model, id: number, speed: number): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end

	local tracks = characterTracks[character]
	if not tracks then
		tracks = {}
		characterTracks[character] = tracks
	end

	local track = tracks[id]
	if not track then
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(getAnimation(id))
		end)
		if not ok or not loaded then
			return false
		end
		loaded.Priority = Enum.AnimationPriority.Action
		tracks[id] = loaded
		track = loaded
	end

	local previous = currentTrack[character]
	if previous and previous.IsPlaying then
		previous:Stop(0.05)
	end

	track:Play(0.05, 1, speed)
	currentTrack[character] = track
	return true
end

local function setTrail(character: Model, enabled: boolean)
	local tool = character:FindFirstChildOfClass("Tool")
	local trail = tool and tool:FindFirstChild("SwingTrail", true)
	if trail and trail:IsA("Trail") then
		trail.Enabled = enabled
	end
end

local function animateSwing(character: Model, archetype: string, step: number)
	--[[
		Uploaded animation first: real keyframes always beat procedural poses.
		The id slot (AnimationConfig) is where GIF-quality swings get plugged
		in; the pose system below is the permanent fallback so a missing or
		moderation-eaten id degrades to motion, never to stillness.
	]]
	local uploadedId = AnimationConfig.GetSwingId(archetype, step)
	if uploadedId > 0 then
		local speed = AnimationConfig.GetSpeed(archetype, step)
		if playUploaded(character, uploadedId, speed) then
			log:Info("swing %s step %d anim=uploaded(%d) speed=%.2f", archetype, step, uploadedId, speed)
			setTrail(character, true)
			task.delay(AnimationConfig.TrailSeconds / speed, function()
				setTrail(character, false)
			end)
			return
		end
	end

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
	log:Info("swing %s step %d anim=procedural shoulder=%s waist=%s",
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
		local character = player.Character
		if character then
			rigs[character] = nil
			characterTracks[character] = nil
			currentTrack[character] = nil
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
