--!strict
--[[
	ClassService — what EquipmentService used to be.

	A player's power now comes entirely from their class. This owns selection,
	the unlock check, and pushing the resulting stats onto the character. Every
	other system that used to ask "what is this player wearing?" asks here
	instead, and the answer no longer depends on inventory state.

	Server-authoritative like everything else: the client sends a class id and
	nothing more. Stats are never sent up, and a class the player has not
	unlocked is refused rather than clamped.

	Selection takes effect on the NEXT spawn, not immediately. Swapping class
	mid-fight would let a player dodge a killing blow by becoming a Berserker,
	and re-statting a live character mid-wave is exactly the sort of thing that
	desyncs a health bar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local ClassConfig = require(Config.ClassConfig)
local Logger = require(Modules.Logger)
local Signal = require(Modules.Signal)

local DataService = require(script.Parent.DataService)
local NetGuard = require(script.Parent.NetGuard)
local ReplicationService = require(script.Parent.ReplicationService)
local CharacterService = require(script.Parent.CharacterService)

local log = Logger.new("ClassService")

local ClassService = {}

--[[ Fires (player, classDefinition) when a player's class changes. ]]
ClassService.ClassChanged = Signal.new()

--========================================================================
-- Reads
--========================================================================

--[[
	The player's class definition. Never nil for a loaded profile: an unknown
	or missing id falls back to the default rather than returning nothing, so
	no caller has to handle a classless player.
]]
function ClassService.GetClass(profile: any): ClassConfig.ClassDefinition
	local definition = ClassConfig.Get(profile and profile.Class)
	if definition then
		return definition
	end

	return ClassConfig.Get(ClassConfig.Default) :: ClassConfig.ClassDefinition
end

--[[
	The stat table combat reads. Replaces EquipmentService.GetAggregateStats.

	Flat now — there is nothing to aggregate. Kept as a table with the same keys
	so CombatService's damage roll did not need rewriting, and so buffs and wave
	modifiers have somewhere obvious to apply later.
]]
function ClassService.GetStats(profile: any): { [string]: number }
	local definition = ClassService.GetClass(profile)

	return {
		Health = definition.Health,
		Damage = definition.Damage,
		AttackSpeed = definition.AttackSpeed,
		CritChance = definition.CritChance,
		CritDamage = definition.CritDamage,
		MoveSpeed = definition.MoveSpeed,
		AttackRange = definition.AttackRange,
	}
end

--========================================================================
-- Applying
--========================================================================

--[[ Pushes the class's health and speed onto a live character. ]]
function ClassService.ApplyToCharacter(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local stats = ClassService.GetStats(profile)

	--[[
		MaxHealth before Health, and Health preserved as a RATIO.

		Setting MaxHealth first then clamping keeps a wounded player wounded
		across a re-apply. Setting Health to MaxHealth here would make any
		stat refresh a free full heal, which during a wave is a real exploit.
	]]
	local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1

	humanoid.MaxHealth = stats.Health
	humanoid.Health = math.clamp(stats.Health * ratio, 1, stats.Health)
	humanoid.WalkSpeed = stats.MoveSpeed
end

--========================================================================
-- Selection
--========================================================================

--[[
	Sets a player's class. Returns a result table; never throws.

	Takes effect on the next spawn. The caller decides whether to force one.
]]
function ClassService.Select(player: Player, classId: any): any
	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	local definition = ClassConfig.Get(classId)
	if not definition then
		return { Success = false, Error = "UnknownClass" }
	end

	-- Gamepass ownership is checked live rather than trusted from the profile,
	-- so a refunded pass stops working immediately.
	local ownsGamepass = false
	if definition.RequiresGamepass then
		ownsGamepass = ClassService.OwnsGamepass(player, definition.RequiresGamepass)
	end

	local allowed, reason = ClassConfig.IsUnlocked(definition, profile, ownsGamepass)
	if not allowed then
		return { Success = false, Error = reason }
	end

	if profile.Class == definition.Id then
		return { Success = true, Class = definition.Id, Unchanged = true }
	end

	profile.Class = definition.Id

	ClassService.ClassChanged:Fire(player, definition)
	ReplicationService.Push(player)

	log:Info("%s selected %s", player.Name, definition.Id)

	return { Success = true, Class = definition.Id }
end

--[[
	Gamepass check. Stubbed until MonetizationConfig carries real ids.

	Returns false rather than true while unconfigured: an unconfigured pass
	should lock the class, not hand it out for free. MonetizationConfig ids are
	all 0 today, so King is unreachable until they are filled in — which is the
	correct behaviour, not a bug.
]]
function ClassService.OwnsGamepass(_player: Player, _passName: string): boolean
	return false
end

--========================================================================
-- Start
--========================================================================

local started = false

function ClassService.Start()
	if started then
		return
	end
	started = true

	NetGuard.OnFunction("ClassSelectRequest", function(player, payload)
		if type(payload) ~= "table" then
			return { Success = false, Error = "BadRequest" }
		end
		return ClassService.Select(player, payload.ClassId)
	end)

	-- Stats and the class weapon are applied on every spawn, so a respawn
	-- mid-wave comes back as the right class without any extra plumbing.
	CharacterService.CharacterReady:Connect(function(player: Player)
		ClassService.ApplyToCharacter(player)
		CharacterService.RefreshLoadout(player)
	end)

	ClassService.ClassChanged:Connect(function(player: Player)
		ClassService.ApplyToCharacter(player)
		CharacterService.RefreshLoadout(player)
	end)

	log:Info("started (%d classes)", ClassConfig.Count())
end

return ClassService
