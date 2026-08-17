--!strict
--[[
	EquipmentService — equipping, selling, favouriting, and derived stats.

	Every entry point re-validates against server state. The client sends an
	instance id and nothing else; ownership, slot fit, level requirement, lock
	status, and whether the item is currently equipped are all checked here. A
	forged id simply does not resolve.

	Aggregate stats are computed rather than stored. Storing them would mean a
	second source of truth that could drift from the actual equipment, and
	drift in a combat stat is a duplication bug waiting to happen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local ItemConfig = require(Config.ItemConfig)
local GameConfig = require(Config.GameConfig)
local RarityConfig = require(Config.RarityConfig)
local DataSchema = require(Modules.DataSchema)
local ItemInstance = require(Modules.ItemInstance)
local Logger = require(Modules.Logger)
local Signal = require(Modules.Signal)

local DataService = require(script.Parent.DataService)
local NetGuard = require(script.Parent.NetGuard)
local ReplicationService = require(script.Parent.ReplicationService)
local CharacterService = require(script.Parent.CharacterService)

local log = Logger.new("EquipmentService")

local EquipmentService = {}

--[[ Fires (player) whenever equipment changes, so combat can recompute. ]]
EquipmentService.EquipmentChanged = Signal.new()

--========================================================================
-- Derived stats
--========================================================================

--[[
	Sums every equipped item's stats onto the player's baselines.
	Pure: takes a profile, returns a table, mutates nothing.
]]
function EquipmentService.GetAggregateStats(profile: any): { [string]: number }
	local combat = GameConfig.Combat
	local level = profile.Progression.Level or 1

	local stats = {
		Damage = combat.BaseDamage,
		Defense = 0,
		Health = combat.BaseHealth + (level - 1) * combat.HealthPerLevel,
		AttackSpeed = combat.BaseAttackSpeed,
		CritChance = combat.BaseCritChance,
		CritDamage = combat.BaseCritDamage,
		MoveSpeed = combat.BaseWalkSpeed,
		Luck = 0,
	}

	for _, instanceId in pairs(profile.Equipment) do
		if instanceId ~= "" then
			local instance = profile.Inventory.Items[instanceId]
			if instance then
				for statName, value in pairs(ItemInstance.GetStats(instance)) do
					if statName == "AttackSpeed" then
						-- Weapons define attack speed rather than adding to it;
						-- summing would make a second weapon nonsensical.
						stats.AttackSpeed = value
					else
						stats[statName] = (stats[statName] or 0) + value
					end
				end
			end
		end
	end

	stats.CritChance = math.min(stats.CritChance, combat.MaxCritChance)
	stats.MoveSpeed = math.min(stats.MoveSpeed, combat.MaxWalkSpeed)

	return stats
end

--[[ Total Power across equipped items, plus a small contribution from level. ]]
function EquipmentService.GetPower(profile: any): number
	local power = 0

	for _, instanceId in pairs(profile.Equipment) do
		if instanceId ~= "" then
			local instance = profile.Inventory.Items[instanceId]
			if instance then
				power += ItemInstance.GetPower(instance)
			end
		end
	end

	power += (profile.Progression.Level or 1) * 10

	return math.floor(power)
end

--[[ Pushes derived stats onto the character's humanoid. ]]
function EquipmentService.ApplyToCharacter(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local stats = EquipmentService.GetAggregateStats(profile)

	-- Preserve the damage fraction so a health increase does not heal, and a
	-- health decrease does not instantly kill.
	local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = stats.Health
	humanoid.Health = math.clamp(stats.Health * fraction, 1, stats.Health)
	humanoid.WalkSpeed = stats.MoveSpeed

	local power = EquipmentService.GetPower(profile)
	if power > (profile.Stats.HighestPower or 0) then
		profile.Stats.HighestPower = power
	end
end

local function afterChange(player: Player)
	EquipmentService.ApplyToCharacter(player)
	CharacterService.RefreshEquipmentVisuals(player)
	EquipmentService.EquipmentChanged:Fire(player)
	ReplicationService.Push(player)
end

--========================================================================
-- Actions
--========================================================================

function EquipmentService.Equip(player: Player, instanceId: any): any
	if type(instanceId) ~= "string" then
		return { Success = false, Error = "BadRequest" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	local instance = profile.Inventory.Items[instanceId]
	if not instance then
		return { Success = false, Error = "NotOwned" }
	end

	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return { Success = false, Error = "UnknownItem" }
	end

	if profile.Equipment[template.Slot] == nil then
		return { Success = false, Error = "NoSuchSlot" }
	end

	if (profile.Progression.Level or 1) < template.LevelRequirement then
		return {
			Success = false,
			Error = "LevelTooLow",
			RequiredLevel = template.LevelRequirement,
		}
	end

	profile.Equipment[template.Slot] = instanceId
	afterChange(player)

	return { Success = true, Slot = template.Slot, Power = EquipmentService.GetPower(profile) }
end

function EquipmentService.Unequip(player: Player, slot: any): any
	if type(slot) ~= "string" then
		return { Success = false, Error = "BadRequest" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	if profile.Equipment[slot] == nil then
		return { Success = false, Error = "NoSuchSlot" }
	end

	if profile.Equipment[slot] == "" then
		return { Success = false, Error = "SlotEmpty" }
	end

	profile.Equipment[slot] = ""
	afterChange(player)

	return { Success = true, Slot = slot, Power = EquipmentService.GetPower(profile) }
end

function EquipmentService.SetFavorite(player: Player, instanceId: any, favorite: any)
	if type(instanceId) ~= "string" then
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local instance = profile.Inventory.Items[instanceId]
	if not instance then
		return
	end

	instance.Favorite = favorite == true
	ReplicationService.Push(player)
end

--[[
	Sells one or more owned items.

	Refuses locked items and anything currently equipped, and requires an
	explicit confirm flag above the configured rarity — losing a Legendary to a
	misclick is the kind of thing players quit over.
]]
function EquipmentService.Sell(player: Player, instanceIds: any, confirmed: any): any
	if type(instanceIds) ~= "table" then
		return { Success = false, Error = "BadRequest" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	local equipped = {}
	for _, id in pairs(profile.Equipment) do
		if id ~= "" then
			equipped[id] = true
		end
	end

	local confirmRank = RarityConfig.GetRank(GameConfig.Economy.SellConfirmRarity)
	local toSell = {}
	local needsConfirm = false
	local total = 0

	for _, instanceId in ipairs(instanceIds) do
		if type(instanceId) == "string" then
			local instance = profile.Inventory.Items[instanceId]

			if instance and not instance.Favorite and not equipped[instanceId] then
				if RarityConfig.GetRank(instance.Rarity) >= confirmRank then
					needsConfirm = true
				end
				table.insert(toSell, instanceId)
				total += ItemInstance.GetSellValue(instance)
			end
		end
	end

	if #toSell == 0 then
		return { Success = false, Error = "NothingSellable" }
	end

	if needsConfirm and confirmed ~= true then
		return {
			Success = false,
			Error = "ConfirmationRequired",
			Count = #toSell,
			Value = math.floor(total * GameConfig.Economy.SellRefundRatio),
		}
	end

	local payout = math.floor(total * GameConfig.Economy.SellRefundRatio)

	for _, instanceId in ipairs(toSell) do
		profile.Inventory.Items[instanceId] = nil
	end

	profile.Currency.Coins += payout
	profile.Stats.ItemsSold += #toSell
	profile.Stats.CoinsEarned += payout

	afterChange(player)

	return { Success = true, Sold = #toSell, Payout = payout }
end

--========================================================================
-- Start
--========================================================================

local started = false

function EquipmentService.Start()
	if started then
		return
	end
	started = true

	NetGuard.OnFunction("EquipRequest", function(player, payload)
		if type(payload) ~= "table" then
			return { Success = false, Error = "BadRequest" }
		end

		if payload.Action == "Unequip" then
			return EquipmentService.Unequip(player, payload.Slot)
		end

		return EquipmentService.Equip(player, payload.InstanceId)
	end)

	NetGuard.OnFunction("SellRequest", function(player, payload)
		if type(payload) ~= "table" then
			return { Success = false, Error = "BadRequest" }
		end
		return EquipmentService.Sell(player, payload.InstanceIds, payload.Confirmed)
	end)

	NetGuard.OnEvent("FavoriteRequest", function(player, payload)
		if type(payload) ~= "table" then
			return
		end
		EquipmentService.SetFavorite(player, payload.InstanceId, payload.Favorite)
	end)

	-- Re-apply stats on every spawn; a fresh humanoid starts at defaults.
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAppearanceLoaded:Connect(function()
			task.wait(0.3)
			EquipmentService.ApplyToCharacter(player)
		end)
	end)

	log:Info("started (%d equipment slots)", #DataSchema.EquipmentSlots)
end

return EquipmentService
