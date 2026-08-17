--!strict
--[[
	DataSchema — the versioned shape of a player profile.

	Two mechanisms keep saved data healthy, and they do different jobs:

	  Reconcile (TableUtil)  Adds newly-introduced fields to an old save using
	                         Default as the template. Handles the common case:
	                         "I added a field." No migration needed.

	  Migrations             Only for changes Reconcile cannot express —
	                         renaming a field, changing a unit, restructuring a
	                         table. Each entry upgrades version N to N+1.

	So: adding a field means editing Default only. Changing the MEANING of an
	existing field means bumping Version and writing a migration.
]]

local TableUtil = require(script.Parent.TableUtil)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local DataSchema = {}

DataSchema.Version = 1

--[[
	Equipment slots. Values are item INSTANCE ids (see Inventory.Items), or ""
	for an empty slot. Empty string rather than nil so the table survives the
	JSON round-trip DataStores perform — nil keys simply vanish.
]]
DataSchema.EquipmentSlots = {
	"Weapon",
	"Helmet",
	"Chest",
	"Legs",
	"Boots",
	"Accessory",
	"Gear",
}

DataSchema.Default = {
	SchemaVersion = DataSchema.Version,

	Meta = {
		CreatedAt = 0,
		LastSeenAt = 0,
		PlayTimeSeconds = 0,
		-- Incremented every successful save; useful for spotting rollbacks.
		SaveCount = 0,
	},

	Currency = {
		Coins = GameConfig.Economy.StartingCoins,
		Gems = 0,
		RollTickets = 0,
	},

	Progression = {
		Level = 1,
		XP = 0,
	},

	Inventory = {
		-- Map of instanceId -> item instance. A map, not an array, so lookups
		-- and deletions are O(1) and item ids stay stable.
		Items = {},
		NextInstanceId = 1,
		BaseCapacity = 200,
	},

	Equipment = {
		Weapon = "",
		Helmet = "",
		Chest = "",
		Legs = "",
		Boots = "",
		Accessory = "",
		Gear = "",
	},

	Luck = {
		-- Permanent additive luck from progression and achievements.
		Permanent = 0,
	},

	-- Active temporary boosts: { [boostId] = { Multiplier, ExpiresAt } }.
	-- ExpiresAt is os.time() on the SERVER, never a client clock.
	Boosts = {},

	--[[
		Rolls since a tier last dropped. RNGService reads these to soften bad
		streaks; it never uses them to guarantee an outcome.
	]]
	Pity = {
		Rare = 0,
		Epic = 0,
		Legendary = 0,
		Mythic = 0,
	},

	Stats = {
		TotalRolls = 0,
		ItemsObtained = 0,
		ItemsSold = 0,
		EnemiesKilled = 0,
		BossesDefeated = 0,
		CoinsEarned = 0,
		-- Rank rather than name, so comparisons stay cheap and ordering is
		-- safe if rarity names are ever reworded.
		BestRarityRank = 0,
		BestItemId = "",
		HighestPower = 0,
	},

	Quests = {
		Active = {},
		Completed = {},
		LastRefreshDay = 0,
	},

	Daily = {
		LastClaimDay = 0,
		Streak = 0,
	},

	Zones = {
		Unlocked = { VerdantFields = true },
		Current = "VerdantFields",
	},

	Titles = {
		Owned = {},
		Equipped = "",
	},

	Cosmetics = {
		Owned = {},
		Equipped = {},
	},

	Achievements = {},

	Settings = {
		MusicVolume = 0.5,
		SFXVolume = 0.7,
		ReducedEffects = false,
		HideOtherPlayerEffects = false,
		DamageNumbers = true,
		CameraShake = true,
		Notifications = true,
		-- "Normal" | "Fast" | "Skip"
		RollSpeed = "Normal",
	},

	Purchases = {
		-- Gamepass ownership is authoritative from MarketplaceService; this is
		-- a cache so we are not querying on every stat recalculation.
		Gamepasses = {},
		-- Receipt ids already granted, newest last. Capped — see
		-- MaxProcessedReceipts — because this list would otherwise grow forever.
		ProcessedReceipts = {},
	},

	Tutorial = {
		Completed = false,
		Step = 0,
	},
}

DataSchema.MaxProcessedReceipts = 100

--[[
	version N -> N+1 upgrades. Empty at v1; the machinery is here so the first
	real schema change is a five-line edit rather than a refactor.

	Example for a future v2:
		[1] = function(data)
			data.Currency.Shards = data.Currency.Gems or 0
			data.Currency.Gems = nil
		end,
]]
DataSchema.Migrations = {} :: { [number]: (data: any) -> () }

--[[ A fresh profile. Always a deep copy — never hand out Default itself. ]]
function DataSchema.CreateDefault(): any
	local profile = TableUtil.DeepCopy(DataSchema.Default)
	profile.Meta.CreatedAt = os.time()
	profile.Meta.LastSeenAt = os.time()
	return profile
end

--[[
	Brings saved data up to the current version, then fills in any new fields.

	Returns (profile, migrated) where `migrated` reports whether a version
	upgrade actually ran, so callers can log it.

	Unknown-but-newer data (a player who somehow loaded a future version) is
	left alone rather than downgraded — corrupting forward-versioned data is
	worse than serving it as-is.
]]
function DataSchema.MigrateAndReconcile(data: any): (any, boolean)
	if type(data) ~= "table" then
		return DataSchema.CreateDefault(), false
	end

	local version = tonumber(data.SchemaVersion) or 0
	local migrated = false

	while version < DataSchema.Version do
		local migration = DataSchema.Migrations[version]
		if migration then
			local ok, err = pcall(migration, data)
			if not ok then
				-- A failed migration must not silently corrupt the save. Bail
				-- and let the caller decide (we treat it as a load failure).
				error(string.format("DataSchema: migration v%d failed: %s", version, tostring(err)))
			end
		end

		version += 1
		migrated = true
	end

	data.SchemaVersion = math.max(version, DataSchema.Version)
	TableUtil.Reconcile(data, DataSchema.Default)

	return data, migrated
end

--[[
	Trims the processed-receipt list to its cap, oldest first. Called after each
	successful purchase grant.
]]
function DataSchema.TrimReceipts(profile: any)
	local receipts = profile.Purchases.ProcessedReceipts
	while #receipts > DataSchema.MaxProcessedReceipts do
		table.remove(receipts, 1)
	end
end

return DataSchema
