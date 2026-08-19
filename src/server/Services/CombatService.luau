--!strict
--[[
	CombatService — player attacks, damage, and kill rewards.

	The client sends "I attacked this thing". It does not send how much damage,
	whether it crit, or whether it hit. All of that is decided here from the
	player's actual equipped stats and their actual position in the world.

	Three validations run on every request, and each blocks a distinct cheat:

	  cooldown   derived from the player's real attack speed, so a client
	             firing every frame gets the same DPS as one firing on time
	  range      measured server-side between the two root parts, so a client
	             cannot hit something across the map
	  target     must be a live enemy the server knows about, so a forged
	             model reference resolves to nothing

	Rewards go through the same profile the rest of the game uses, so XP and
	coins from combat are indistinguishable from any other source and cannot be
	granted twice.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local GameConfig = require(Config.GameConfig)
local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)

local CharacterService = require(script.Parent.CharacterService)
local DataService = require(script.Parent.DataService)
local EnemyService = require(script.Parent.EnemyService)
local ClassService = require(script.Parent.ClassService)
local VFX = require(Modules.VFX)
local AbilityService = require(script.Parent.AbilityService)
local NetGuard = require(script.Parent.NetGuard)
local ReplicationService = require(script.Parent.ReplicationService)

local log = Logger.new("CombatService")

local CombatService = {}

local lastAttackAt: { [Player]: number } = {}
local random = Random.new()

--[[
	Generous margin on the range check. Server and client disagree slightly
	about positions under latency, and rejecting hits that looked good on the
	player's screen feels broken. The margin is small enough that it still
	stops anything resembling a reach exploit.
]]
local RANGE_MARGIN = 8

--========================================================================
-- Damage
--========================================================================

--[[
	The player's reach, straight off their class.

	Ranged classes reach much further, which is the entire point of picking one
	and the reason this is per-class rather than a global constant.
]]
local function attackRange(profile: any): number
	return ClassService.GetStats(profile).AttackRange or 12
end

--[[
	Rolls one attack. Returns (damage, isCrit).

	Crit is rolled per swing rather than averaged into damage so the spikes are
	visible — a crit that never shows as a bigger number is just a smaller
	damage stat with extra steps.
]]
local function rollDamage(stats: { [string]: number }): (number, boolean)
	local damage = stats.Damage or GameConfig.Combat.BaseDamage
	local isCrit = random:NextNumber() * 100 < (stats.CritChance or 0)

	if isCrit then
		damage *= 1 + ((stats.CritDamage or 0) / 100)
	end

	-- Small spread so repeated hits are not identical.
	damage *= random:NextNumber(0.95, 1.05)

	return math.max(1, math.floor(damage + 0.5)), isCrit
end


--========================================================================
-- Attack
--========================================================================

function CombatService.Attack(player: Player, targetModel: any)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not root or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- The weapon is a Tool now, and a stowed weapon cannot attack. Checked
	-- before the cooldown stamp so drawing it again is never punished.
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("ClassWeapon") then
		return
	end

	local stats = ClassService.GetStats(profile)

	-- Cooldown from real attack speed. Checked before anything target-related
	-- so a player swinging at nothing is still rate-limited.
	local now = os.clock()
	-- Rapidfire multiplies attack speed, which is the same thing as dividing
	-- the gap between swings. Asked of AbilityService so this module never
	-- learns what an ability is.
	local attackSpeed = (stats.AttackSpeed or 1) * AbilityService.GetAttackSpeedBonus(player)
	local cooldown = 1 / math.max(attackSpeed, 0.1)
	local last = lastAttackAt[player]
	if last and (now - last) < cooldown * 0.9 then
		return
	end
	lastAttackAt[player] = now

	--[[
		Swing first, unconditionally.

		Everything below can legitimately reject the attack — no target, dead
		target, out of range — but the player still pressed the button, and a
		click that produces no animation reads as an input drop rather than a
		miss. Swinging at empty air is the correct feedback.
	]]
	CharacterService.SwingWeapon(player)

	-- Past this point a real, living enemy is required.
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then
		return
	end

	local record = EnemyService.GetRecord(targetModel)
	if not record or record.Humanoid.Health <= 0 then
		return
	end

	-- Range, measured here rather than trusted.
	local distance = ((root :: BasePart).Position - record.Root.Position).Magnitude
	if distance > attackRange(profile) + RANGE_MARGIN then
		return
	end

	local damage, isCrit = rollDamage(stats)

	local dealt = EnemyService.Damage(targetModel, damage, player)
	if dealt <= 0 then
		return
	end

	--[[
		Hit feedback in the class colour: a tracer for ranged classes so shots
		visibly travel their path, and an impact burst for everyone. Damage is
		already applied above — this is presentation, and it is server-side so
		every player sees the same fight.
	]]
	local theme = ClassService.GetClass(profile).ThemeColor
	local isRanged = attackRange(profile) >= 30

	if isRanged then
		local hand = character and character:FindFirstChild("RightHand") :: BasePart?
		local from = if hand then hand.Position else (root :: BasePart).Position + Vector3.new(0, 1.5, 0)
		VFX.Tracer(from, record.Root.Position, theme)
	end

	VFX.Burst(record.Root.Position, theme, if isCrit then 1.4 else 0.8)

	--[[
		On-hit effects (lifesteal, slow, burn) lived on rolled weapon modifiers
		and went with them. Class abilities are the replacement — see
		AbilityService when it lands. Do not reintroduce per-hit effects here
		without a home for them in ClassConfig.
	]]

	local feedback = Remotes.Get("CombatEvent") :: RemoteEvent
	feedback:FireAllClients({
		Kind = "Damage",
		Position = record.Root.Position,
		Amount = dealt,
		Crit = isCrit,
		Attacker = player.UserId,
	})
end

--========================================================================
-- Rewards
--========================================================================

local function onEnemyKilled(player: Player, definition: any)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	-- Coins only. There is no XP and no levelling — kills pay currency, and
	-- what a player can DO comes entirely from their class.
	local coins = definition.CoinReward

	profile.Currency.Coins += coins
	profile.Stats.CoinsEarned += coins
	profile.Stats.EnemiesKilled += 1

	if definition.IsBoss then
		profile.Stats.BossesDefeated += 1
	end

	ReplicationService.Notify(player, string.format("+%d Coins", coins), "Info")
	ReplicationService.Push(player)

	local feedback = Remotes.Get("CombatEvent") :: RemoteEvent
	feedback:FireClient(player, {
		Kind = "Kill",
		EnemyName = definition.Name,
		Coins = coins,
	})
end

--========================================================================
-- Start
--========================================================================

local started = false

function CombatService.Start()
	if started then
		return
	end
	started = true

	NetGuard.OnEvent("AttackRequest", function(player, target)
		CombatService.Attack(player, target)
	end)

	EnemyService.EnemyKilled:Connect(onEnemyKilled)

	Players.PlayerRemoving:Connect(function(player)
		lastAttackAt[player] = nil
	end)

	log:Info("started")
end

return CombatService
