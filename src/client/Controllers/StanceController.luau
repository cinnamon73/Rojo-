--!strict
--[[
	StanceController — how a body carries the thing in its hands.

	Every class used to stand and walk identically: the stock R15 idle with a
	weapon stapled to one hand. The weapon changed what a swing looked like and
	nothing else. This plays the ITEM's stance and locomotion so you can tell
	what someone is holding before they ever attack.

	WHY THIS NEEDS NO COOPERATION FROM THE SWING CODE
	Roblox resolves overlapping tracks by AnimationPriority:

	    Core (stock idle/walk)  <  Idle  <  Movement  <  Action (swings)

	Stances play at Idle and locomotion at Movement, so they sit above Roblox's
	default Animate script and below our attacks. A swing interrupts the stance
	for exactly as long as it plays and then the stance returns, without either
	system knowing the other exists.

	Client-side by design, like the rest of the FX layer: a stance is pure
	presentation and the server has no opinion about it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = ReplicatedStorage:WaitForChild("Config")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local WeaponConfig = require(Config.WeaponConfig)
local Logger = require(Modules.Logger)

local log = Logger.new("StanceController")
local localPlayer = Players.LocalPlayer

local StanceController = {}

-- Above this speed the walk cycle plays instead of the stance.
local MOVING_SPEED = 0.6
local FADE = 0.25

local client: any = nil

type Loaded = {
	Stance: AnimationTrack?,
	Walk: AnimationTrack?,
	Run: AnimationTrack?,
	WeaponId: string,
}

local loaded: { [Model]: Loaded } = {}
local animCache: { [number]: Animation } = {}


local function animation(id: number): Animation
	local cached = animCache[id]
	if cached then
		return cached
	end
	local a = Instance.new("Animation")
	a.AnimationId = "rbxassetid://" .. tostring(id)
	animCache[id] = a
	return a
end


local function load(animator: Animator, id: number, priority: Enum.AnimationPriority): AnimationTrack?
	if id <= 0 then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation(id))
	end)
	if not ok or not track then
		return nil
	end
	track.Priority = priority
	track.Looped = true
	return track
end


--[[
	Resolves the tracks for the character's currently equipped item, reloading
	only when the item actually changed. Swapping class mid-fight has to swap
	the stance with it, but re-loading every frame would thrash the animator.
]]
local function tracksFor(character: Model): Loaded?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local weapon = WeaponConfig.GetEquipped(client and client.Profile)
	local existing = loaded[character]
	if existing and existing.WeaponId == weapon.Id then
		return existing
	end

	if existing then
		for _, t in pairs({ existing.Stance, existing.Walk, existing.Run }) do
			if t then
				t:Stop(FADE)
			end
		end
	end

	local entry: Loaded = {
		Stance = load(animator, weapon.Stance, Enum.AnimationPriority.Idle),
		Walk = load(animator, weapon.Walk, Enum.AnimationPriority.Movement),
		Run = load(animator, weapon.Run or 0, Enum.AnimationPriority.Movement),
		WeaponId = weapon.Id,
	}
	loaded[character] = entry

	if entry.Stance or entry.Walk then
		log:Info("stance set for %s (carry=%s)", weapon.Id, weapon.Carry)
	end
	return entry
end


local function play(track: AnimationTrack?)
	if track and not track.IsPlaying then
		track:Play(FADE)
	end
end


local function stop(track: AnimationTrack?)
	if track and track.IsPlaying then
		track:Stop(FADE)
	end
end


local function update()
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local entry = tracksFor(character)
	if not entry then
		return
	end

	--[[ Velocity lives on the root PART, not on the Humanoid - reading
	     humanoid.Velocity throws, and because this runs inside a pcall it
	     failed silently sixty times a second while no stance ever played.

	     STATE plus speed, not MoveDirection. MoveDirection is only populated
	     by player INPUT: a humanoid walking under MoveTo or pathfinding
	     reports exactly zero while travelling at full speed, so keying off it
	     meant the walk never played for anything the player was not steering
	     by hand. Measured: md=0.00 speed=17.00 state=Running.

	     Testing the grounded states also gets the case MoveDirection was
	     there to cover for free - falling and being knocked back are not
	     Running, so they correctly keep the stance rather than the walk. ]]
	local root = humanoid.RootPart
	local speed = if root then root.AssemblyLinearVelocity.Magnitude else 0
	local state = humanoid:GetState()
	local grounded = state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.RunningNoPhysics
	local moving = grounded and speed > MOVING_SPEED

	if moving then
		stop(entry.Stance)
		local running = entry.Run and speed > humanoid.WalkSpeed * 0.85
		if running then
			stop(entry.Walk)
			play(entry.Run)
		else
			stop(entry.Run)
			play(entry.Walk)
		end
	else
		stop(entry.Walk)
		stop(entry.Run)
		play(entry.Stance)
	end
end


local started = false

function StanceController.Start(clientRef: any)
	if started then
		return
	end
	started = true
	client = clientRef

	localPlayer.CharacterRemoving:Connect(function(character)
		loaded[character] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(update)
		if not ok then
			log:Warn("update failed: %s", tostring(err))
		end
	end)

	log:Info("ready")
end

return StanceController
