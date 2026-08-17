--!strict
--[[
	ItemInstance — the owned copy of an item template.

	A template says what "Stormblade" is. An instance is *your* Stormblade: same
	template, but with its own rolled stat variance, possibly a modifier, and a
	unique id. Two players can hold the same template and have measurably
	different weapons.

	Instances are stored verbatim in the profile, so this shape is effectively a
	save format — add fields, never repurpose existing ones, and let
	DataSchema.Reconcile backfill.

	Both the server (authority) and client (display) compute stats through this
	module, so the number in the tooltip is the number combat uses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")
local ItemConfig = require(Config.ItemConfig)
local ModifierConfig = require(Config.ModifierConfig)
local GameConfig = require(Config.GameConfig)

export type Instance_ = {
	Id: string,
	TemplateId: string,
	Rarity: string,
	Modifier: string?,
	-- Per-stat multiplier rolled once at creation and then frozen, so an item's
	-- numbers never drift between sessions.
	Variance: { [string]: number },
	Level: number,
	Favorite: boolean,
	ObtainedAt: number,
}

local ItemInstance = {}

--[[
	Relative worth of each stat when collapsing an item into a single Power
	number. Power is a progression *signal* for the UI — combat always uses the
	individual stats, never this.
]]
ItemInstance.PowerWeights = {
	Damage = 2.0,
	Defense = 1.5,
	Health = 0.3,
	AttackSpeed = 20.0,
	CritChance = 1.5,
	CritDamage = 0.5,
	MoveSpeed = 3.0,
	Luck = 200.0,
}

--[[
	Builds a new instance of `templateId`.

	`random` is injected rather than using math.random so rolls are seedable and
	the RNG service can be tested deterministically.
]]
function ItemInstance.Create(templateId: string, instanceId: string, random: Random): Instance_?
	local template = ItemConfig.Get(templateId)
	if not template then
		return nil
	end

	local variance: { [string]: number } = {}
	local spread = GameConfig.RNG.StatVariance

	for statName, baseValue in pairs(template.BaseStats) do
		if type(baseValue) == "number" then
			variance[statName] = 1 + random:NextNumber(-spread, spread)
		end
	end

	local modifier = if template.AllowModifiers then ModifierConfig.Roll(template.Rarity, random) else nil

	return {
		Id = instanceId,
		TemplateId = templateId,
		Rarity = template.Rarity,
		Modifier = if modifier then modifier.Id else nil,
		Variance = variance,
		Level = 1,
		Favorite = false,
		ObtainedAt = os.time(),
	}
end

--[[
	Final stats: base * variance, then the modifier's multipliers and adds.

	Order matters — multipliers apply to the varied base, adds apply last. Doing
	it the other way would let a flat add get multiplied and inflate cheap
	modifiers on high-tier items.
]]
function ItemInstance.GetStats(instance: Instance_): { [string]: number }
	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return {}
	end

	local stats: { [string]: number } = {}

	for statName, baseValue in pairs(template.BaseStats) do
		if type(baseValue) == "number" then
			stats[statName] = baseValue * (instance.Variance[statName] or 1)
		end
	end

	if instance.Modifier then
		local modifier = ModifierConfig.Get(instance.Modifier)
		if modifier then
			for statName, multiplier in pairs(modifier.Multipliers) do
				if stats[statName] then
					stats[statName] *= multiplier
				end
			end

			for statName, addition in pairs(modifier.Adds) do
				stats[statName] = (stats[statName] or 0) + addition
			end
		end
	end

	-- Round display-facing stats. AttackSpeed and Luck stay fractional because
	-- rounding them to integers would destroy their meaning.
	for statName, value in pairs(stats) do
		if statName ~= "AttackSpeed" and statName ~= "Luck" then
			stats[statName] = math.floor(value * 10 + 0.5) / 10
		end
	end

	return stats
end

--[[ Single scalar for progression display. ]]
function ItemInstance.GetPower(instance: Instance_): number
	local stats = ItemInstance.GetStats(instance)
	local power = 0

	for statName, value in pairs(stats) do
		local weight = ItemInstance.PowerWeights[statName]
		if weight then
			power += value * weight
		end
	end

	return math.floor(power + 0.5)
end

--[[ "Swift Stormblade" — modifier prefixed when present. ]]
function ItemInstance.GetDisplayName(instance: Instance_): string
	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return "Unknown Item"
	end

	if instance.Modifier then
		local modifier = ModifierConfig.Get(instance.Modifier)
		if modifier then
			return modifier.Name .. " " .. template.Name
		end
	end

	return template.Name
end

--[[ Sell value, raised when the item carries a modifier. ]]
function ItemInstance.GetSellValue(instance: Instance_): number
	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return 0
	end

	local value = template.SellValue
	if instance.Modifier then
		value = math.floor(value * 1.25)
	end

	return value
end

--[[
	Structural validation. Used on anything that came from a client or from
	saved data before it is trusted — a hand-edited profile must not be able to
	inject a template id that does not exist.
]]
function ItemInstance.IsValid(instance: any): boolean
	if type(instance) ~= "table" then
		return false
	end

	if type(instance.Id) ~= "string" or instance.Id == "" then
		return false
	end

	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return false
	end

	if instance.Rarity ~= template.Rarity then
		return false
	end

	if instance.Modifier ~= nil and not ModifierConfig.Get(instance.Modifier) then
		return false
	end

	if type(instance.Variance) ~= "table" then
		return false
	end

	return true
end

return ItemInstance
