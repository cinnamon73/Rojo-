--!strict
--[[
	AbilityService — the one button each class presses.

	Server-authoritative: the client sends "I pressed my ability" and, for the
	grenade, where it aimed. Everything else — whether the cooldown is up, what
	the ability does, how long it lasts — is decided here. A client cannot pick
	which ability it gets; that comes from its class.

	HOW EFFECTS ARE EXPOSED
	-----------------------
	Three abilities change how OTHER systems behave rather than doing something
	themselves. Rather than have those systems know about abilities, this module
	holds the state and answers questions:

	    AbilityService.GetAttackSpeedBonus(player)  -- CombatService
	    AbilityService.IsHidden(player)             -- EnemyService targeting
	    AbilityService.IsUndying(player)            -- handled internally

	That keeps the dependency pointing one way. CombatService and EnemyService
	ask a question; they never learn what an ability is.

	WHAT IS APPROXIMATED, AND WHY
	-----------------------------
	Paladin's Aegis is specified as a bubble enemies must BREAK to enter. A true
	version needs enemy AI that can target and attack a structure, which
	EnemyService cannot do — it only ever targets players. Implemented here as a
	bubble with its own health that drains while enemies press against it, so it
	still falls to sustained pressure and still has to be earned through. The
	behaviour is right; the mechanism is cheaper. Replacing it means teaching
	enemies to attack non-player targets, which is a wave-system job.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local ClassConfig = require(Config.ClassConfig)
local VFX = require(Modules.VFX)
local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local Signal = require(Modules.Signal)

local DataService = require(script.Parent.DataService)
local NetGuard = require(script.Parent.NetGuard)
local ClassService = require(script.Parent.ClassService)
local WeaponConfig = require(ReplicatedStorage.Config.WeaponConfig)
local EnemyService = require(script.Parent.EnemyService)
local MinionService = require(script.Parent.MinionService)
local ReplicationService = require(script.Parent.ReplicationService)

local log = Logger.new("AbilityService")

local AbilityService = {}

--[[ Fires (player, abilityId, duration) when an ability successfully starts. ]]
AbilityService.AbilityUsed = Signal.new()

--========================================================================
-- State
--========================================================================

type Active = {
	AbilityId: string,
	ExpiresAt: number,
}

local cooldownUntil: { [Player]: { [string]: number } } = {}
local active: { [Player]: Active } = {}

-- Grenade tuning. Here rather than ClassConfig because they describe this
-- implementation, not the class's identity.
local GRENADE_RADIUS = 18
local GRENADE_DAMAGE_MULTIPLIER = 2.6
-- How far from the player a thrown grenade may land. The client picks the
-- point, so this is the check that stops it being thrown across the map.
local GRENADE_MAX_RANGE = 90
-- Throw flight time. Damage lands when the bomb does.
local GRENADE_FLIGHT_SECONDS = 0.5

local SPIN_TICKS = 6
local SPIN_RADIUS = 16
local SPIN_DAMAGE_MULTIPLIER = 0.55

local AEGIS_RADIUS = 22
local AEGIS_HEALTH = 900
-- Damage the bubble takes per second, per enemy pressing on it.
local AEGIS_DRAIN_PER_ENEMY = 26

--========================================================================
-- Queries used by other services
--========================================================================

local function isActive(player: Player, abilityId: string): boolean
	local state = active[player]
	return state ~= nil and state.AbilityId == abilityId and os.clock() < state.ExpiresAt
end

--[[ Multiplier on attack speed. 1 when nothing is running. ]]
function AbilityService.GetAttackSpeedBonus(player: Player): number
	return if isActive(player, "Rapidfire") then 3.0 else 1.0
end

--[[ True while the player should be ignored by enemy targeting. ]]
function AbilityService.IsHidden(player: Player): boolean
	return isActive(player, "Vanish")
end

function AbilityService.IsUndying(player: Player): boolean
	return isActive(player, "Undying")
end

--========================================================================
-- Helpers
--========================================================================

local function enemiesWithin(position: Vector3, radius: number): { Model }
	local found = {}
	local folder = Workspace:FindFirstChild("Enemies")
	if not folder then
		return found
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = model:FindFirstChildOfClass("Humanoid")

			if root and humanoid and humanoid.Health > 0 then
				if (root.Position - position).Magnitude <= radius then
					table.insert(found, model)
				end
			end
		end
	end

	return found
end

--[[ The caster's class colour, so every effect reads as theirs. ]]
local function themeOf(player: Player): Color3
	return ClassService.GetClass(DataService.Get(player)).ThemeColor
end

local function setActive(player: Player, abilityId: string, duration: number)
	if duration > 0 then
		active[player] = { AbilityId = abilityId, ExpiresAt = os.clock() + duration }
	end
end

--========================================================================
-- The abilities
--========================================================================

local handlers: { [string]: (Player, any, any) -> boolean } = {}

--[[ Archer: no draw time. CombatService reads the multiplier. ]]
handlers.Rapidfire = function(player, definition, _payload)
	setActive(player, "Rapidfire", definition.Ability.Duration)

	if player.Character then
		VFX.Aura(player.Character, themeOf(player), definition.Ability.Duration)
	end

	return true
end

--[[ Swordsman: repeated sweeps around the player over the duration. ]]
handlers.SpinningSlash = function(player, definition, _payload)
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local damage = math.floor(ClassService.GetStats(profile).Damage * SPIN_DAMAGE_MULTIPLIER)
	local interval = definition.Ability.Duration / SPIN_TICKS

	setActive(player, "SpinningSlash", definition.Ability.Duration)

	task.spawn(function()
		for _ = 1, SPIN_TICKS do
			task.wait(interval)

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				return
			end

			VFX.GroundRing(root.Position, themeOf(player), SPIN_RADIUS, 0.7)

			for _, model in ipairs(enemiesWithin(root.Position, SPIN_RADIUS)) do
				EnemyService.Damage(model, damage, player)
			end
		end
	end)

	return true
end

--[[ Berserker: health is clamped in the HealthChanged hook while this runs. ]]
handlers.Undying = function(player, definition, _payload)
	setActive(player, "Undying", definition.Ability.Duration)

	-- Deliberately blood-red rather than the class colour: enemies and allies
	-- alike need to read "cannot die right now" at a glance.
	if player.Character then
		VFX.Aura(player.Character, Color3.fromRGB(255, 60, 48), definition.Ability.Duration)
	end

	return true
end

--[[
	Musketeer: a thrown bomb that ARCS to the aim point, then explodes.

	The projectile is real: damage happens at landing, about half a second
	after the press, and anything that walked out of the blast radius in that
	time is missed. That is the cost of a visible throw, and it is the right
	trade — an instant invisible explosion reads as a bug, not an ability.

	The aim point is hostile input: anything malformed or beyond throw range
	is clamped to the thrower's feet, so a bad payload wastes the cooldown
	rather than being an error path worth probing.
]]
handlers.Grenade = function(player, definition, payload)
	local profile = DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not profile or not root then
		return false
	end

	local origin = root.Position
	local target = if typeof(payload) == "table" and typeof(payload.Position) == "Vector3"
		then payload.Position
		else origin

	if (target - origin).Magnitude > GRENADE_MAX_RANGE then
		target = origin
	end

	local damage = math.floor(ClassService.GetStats(profile).Damage * GRENADE_DAMAGE_MULTIPLIER)
	local theme = themeOf(player)

	task.spawn(function()
		local bomb = Instance.new("Part")
		bomb.Shape = Enum.PartType.Ball
		bomb.Size = Vector3.new(0.7, 0.7, 0.7)
		bomb.Color = Color3.fromRGB(40, 40, 44)
		bomb.Material = Enum.Material.Metal
		bomb.Anchored = true
		bomb.CanCollide = false
		bomb.CanQuery = false
		bomb.CanTouch = false
		bomb.Parent = Workspace

		-- Quadratic arc: lerp the ground path, add a parabola for height.
		local flight = GRENADE_FLIGHT_SECONDS
		local steps = 14
		local apex = math.clamp((target - origin).Magnitude * 0.35, 4, 14)

		for step = 1, steps do
			local alpha = step / steps
			local along = origin:Lerp(target, alpha)
			local height = apex * 4 * alpha * (1 - alpha)
			bomb.Position = along + Vector3.new(0, height, 0)
			task.wait(flight / steps)
		end

		bomb:Destroy()

		VFX.Burst(target, Color3.fromRGB(255, 172, 88), 2.4)
		VFX.GroundRing(target, theme, GRENADE_RADIUS, 0.5)

		for _, model in ipairs(enemiesWithin(target, GRENADE_RADIUS)) do
			EnemyService.Damage(model, damage, player)
		end
	end)

	return true
end

--[[ Assassin: invisible to enemy targeting, and visually faded for everyone. ]]
handlers.Vanish = function(player, definition, _payload)
	setActive(player, "Vanish", definition.Ability.Duration)

	local character = player.Character
	if not character then
		return true
	end

	local smoke = Color3.fromRGB(120, 120, 128)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		VFX.Burst(root.Position, smoke, 1.6)
		task.delay(definition.Ability.Duration, function()
			local nowRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if nowRoot then
				VFX.Burst(nowRoot.Position, smoke, 1.2)
			end
		end)
	end

	local restore: { [BasePart]: number } = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			restore[part] = part.Transparency
			part.Transparency = 0.8
		end
	end

	task.delay(definition.Ability.Duration, function()
		for part, transparency in pairs(restore) do
			if part.Parent then
				part.Transparency = transparency
			end
		end
	end)

	return true
end

--[[
	Paladin: a bubble that drains while enemies press on it.

	Anchored and CanCollide so enemies physically cannot walk through it. It is
	not in a collision group, so player characters collide with it too — a
	limitation, and the reason the radius is generous enough to fight inside.
]]
handlers.Aegis = function(player, definition, _payload)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	setActive(player, "Aegis", definition.Ability.Duration)

	local bubble = Instance.new("Part")
	bubble.Name = "AegisBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(AEGIS_RADIUS * 2, AEGIS_RADIUS * 2, AEGIS_RADIUS * 2)
	bubble.Position = root.Position
	bubble.Anchored = true
	bubble.CanCollide = true
	bubble.CanQuery = false
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(226, 200, 128)
	bubble.Transparency = 0.6
	bubble.Parent = Workspace

	VFX.GroundRing(root.Position, Color3.fromRGB(255, 226, 140), AEGIS_RADIUS, 0.7)

	task.spawn(function()
		local health = AEGIS_HEALTH
		local expiresAt = os.clock() + definition.Ability.Duration

		while os.clock() < expiresAt and health > 0 and bubble.Parent do
			task.wait(0.25)

			local pressing = #enemiesWithin(bubble.Position, AEGIS_RADIUS + 4)
			health -= pressing * AEGIS_DRAIN_PER_ENEMY * 0.25

			-- Fades as it weakens, so players can read how long it has left
			-- without a health bar.
			bubble.Transparency = 0.6 + 0.35 * (1 - math.clamp(health / AEGIS_HEALTH, 0, 1))
		end

		bubble:Destroy()
	end)

	return true
end

handlers.RaiseSkeletons = function(player, definition, _payload)
	setActive(player, "RaiseSkeletons", definition.Ability.Duration)
	return MinionService.SummonSquad(player, "RaiseSkeletons", definition.Ability.Duration, themeOf(player)) > 0
end

handlers.RoyalGuard = function(player, definition, _payload)
	setActive(player, "RoyalGuard", definition.Ability.Duration)
	return MinionService.SummonSquad(player, "RoyalGuard", definition.Ability.Duration, themeOf(player)) > 0
end

--========================================================================
-- Entry point
--========================================================================

--[[ Attempts to use the player's class ability. Returns a result table. ]]
function AbilityService.Use(player: Player, payload: any): any
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return { Success = false, Error = "Dead" }
	end

	--[[ The ability belongs to the item, not the class. Handlers only ever
	     read `.Ability`, so handing them the weapon definition needs no
	     change inside any of them. ]]
	local definition = WeaponConfig.GetEquipped(profile)
	local ability = definition.Ability

	local now = os.clock()
	local timers = cooldownUntil[player]
	if not timers then
		timers = {}
		cooldownUntil[player] = timers
	end

	local readyAt = timers[ability.Id] or 0
	if now < readyAt then
		return { Success = false, Error = "Cooldown", RetryAfter = readyAt - now }
	end

	local handler = handlers[ability.Id]
	if not handler then
		log:Warn("no handler for ability '%s'", ability.Id)
		return { Success = false, Error = "NotImplemented" }
	end

	local ok, started = pcall(handler, player, definition, payload)
	if not ok then
		log:Warn("ability %s errored for %s: %s", ability.Id, player.Name, tostring(started))
		return { Success = false, Error = "Failed" }
	end

	if not started then
		-- The handler refused (no character, nothing summoned). No cooldown is
		-- burned: the player pressed the button and got nothing.
		return { Success = false, Error = "Unavailable" }
	end

	timers[ability.Id] = now + ability.Cooldown

	AbilityService.AbilityUsed:Fire(player, ability.Id, ability.Duration)
	ReplicationService.Notify(player, ability.Name .. "!", "Success")

	return {
		Success = true,
		AbilityId = ability.Id,
		Cooldown = ability.Cooldown,
		Duration = ability.Duration,
	}
end

--========================================================================
-- Start
--========================================================================

local started = false

function AbilityService.Start()
	if started then
		return
	end
	started = true

	NetGuard.OnEvent("AbilityRequest", function(player, payload)
		AbilityService.Use(player, payload)
	end)

	-- Assassins mid-Vanish drop out of enemy targeting. Registered rather than
	-- required, so EnemyService never depends on this module.
	EnemyService.SetHiddenCheck(function(player: Player): boolean
		return AbilityService.IsHidden(player)
	end)

	--[[
		Swapping class refills the skill. The design is that a swap is a fresh
		start — and it is not free: a mid-session swap only takes effect through
		a respawn, so this cannot be pumped for cooldown resets mid-fight.
	]]
	ClassService.ClassChanged:Connect(function(player: Player)
		cooldownUntil[player] = nil
		active[player] = nil
	end)

	--[[
		Undying, enforced where damage actually lands.

		Watching HealthChanged rather than intercepting every damage source:
		enemies call TakeDamage directly on the humanoid, and there is no single
		chokepoint to guard. Clamping back to 1 is blunt but cannot be bypassed
		by a damage path nobody remembered to update.
	]]
	local function guard(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end

		humanoid.HealthChanged:Connect(function(health)
			if health <= 0 and AbilityService.IsUndying(player) then
				humanoid.Health = 1
			end
		end)
	end

	local function watch(player: Player)
		if player.Character then
			task.spawn(guard, player, player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			task.spawn(guard, player, character)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)

	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player] = nil
		active[player] = nil
	end)

	log:Info("started (%d abilities)", (function()
		local count = 0
		for _ in pairs(handlers) do
			count += 1
		end
		return count
	end)())
end

return AbilityService
