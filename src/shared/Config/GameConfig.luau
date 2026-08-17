--!strict
--[[
	GameConfig — global tunables.

	Anything a designer might want to change without reading gameplay code
	belongs here or in a sibling config module. No magic numbers in services.
]]

local GameConfig = {}

GameConfig.Debug = {
	-- Info is the normal signal; Verbose is per-roll / per-hit spam.
	LogInfo = true,
	LogVerbose = false,
}

GameConfig.Data = {
	-- Bump this to start every player on a fresh save. Never reuse an old name
	-- after a destructive schema change.
	StoreName = "PlayerData_v1",

	-- Autosave cadence. Roblox throttles writes per key, so keep this well
	-- above the 6s minimum interval.
	AutosaveInterval = 120,

	-- Retry policy for load/save. Delay is multiplied each attempt.
	MaxRetries = 4,
	RetryBaseDelay = 1,
	RetryBackoff = 2,

	-- A session lock older than this is treated as abandoned (server crashed
	-- without releasing). Must exceed the longest plausible autosave gap.
	SessionLockTimeout = 900,

	-- If a profile cannot be loaded after all retries, kick rather than let the
	-- player build progress on an empty profile that would overwrite their real
	-- save. This is the single most important data-safety rule in the game.
	KickOnLoadFailure = true,
	LoadFailureMessage = "Could not load your save data. Please rejoin in a moment — your progress is safe.",
}

GameConfig.Roll = {
	-- Rolling is free. The cooldown is the only gate, so boosts and gamepasses
	-- reduce it rather than granting currency.
	CooldownSeconds = 1.5,
	MinCooldownSeconds = 0.25,

	-- Reveal animation lengths, by player preference. "Skip" still runs the
	-- server roll; it only shortens presentation.
	RevealDuration = {
		Normal = 1.6,
		Fast = 0.7,
		Skip = 0,
	},

	-- Auto-roll is driven server-side on this interval, never by a client loop.
	AutoRollEnabled = true,
	MaxAutoRollDuration = 3600,
}

GameConfig.RNG = {
	-- Luck is clamped before it touches the weights. Without a ceiling, stacked
	-- boosts would make Celestial routine and collapse the whole rarity ladder.
	MaxLuck = 10,

	-- Luck only boosts tiers at this rank or above (3 = Rare). Boosting
	-- Uncommon would be pointless and would eat the budget that should be
	-- shifting players toward genuinely rare drops.
	LuckMinRank = 3,

	-- Common can never be squeezed below this share of total weight, no matter
	-- how much luck is stacked. Guarantees the distribution stays valid and
	-- keeps a floor under the "you can still get junk" promise.
	MinCommonWeightRatio = 0.04,

	-- Pity ramps a tier's weight up to this multiple once the player is past
	-- its threshold. Capped so pity nudges the odds, never guarantees a drop.
	PityMaxMultiplier = 5,

	-- Rolled stat variance, +/- this fraction of the template's base values.
	StatVariance = 0.08,

	-- Rarity at or above which a roll is announced server-wide is driven by
	-- RarityConfig.AnnounceGlobal, not a number here.
}

GameConfig.Economy = {
	StartingCoins = 100,

	-- Fraction of an item's sell value refunded. Below 1 so selling is a
	-- cleanup tool, not an exploit loop.
	SellRefundRatio = 1.0,

	-- Selling anything at or above this rarity requires a confirmation step.
	SellConfirmRarity = "Epic",
}

GameConfig.Progression = {
	MaxLevel = 100,

	-- XP required for level N is Base * (N ^ Exponent). Tuned so early levels
	-- come fast and midgame requires real investment.
	XPBase = 85,
	XPExponent = 1.55,
}

GameConfig.Combat = {
	-- Player baselines before equipment. Gear adds on top of these.
	BaseHealth = 100,
	BaseWalkSpeed = 16,
	BaseDamage = 5,
	BaseAttackSpeed = 1.0,
	BaseCritChance = 2,
	BaseCritDamage = 50,

	-- Health gained per character level, independent of gear, so levelling
	-- always feels like it did something even on a dry run of drops.
	HealthPerLevel = 8,

	-- Ceilings on stats that break the game if unbounded.
	MaxCritChance = 75,
	MaxWalkSpeed = 34,
}

GameConfig.Network = {
	-- Token-bucket rate limits per remote, per player. Requests over budget are
	-- dropped silently rather than erroring, so a laggy client is not punished.
	DefaultBurst = 12,
	DefaultRefillPerSecond = 6,

	-- Logged if a single player trips the limiter this many times in a session.
	SuspiciousStrikeThreshold = 25,
}

GameConfig.UI = {
	-- Minimum touch target on mobile, in pixels.
	MinTouchTargetPx = 44,
	DefaultTweenTime = 0.18,
}

return GameConfig
