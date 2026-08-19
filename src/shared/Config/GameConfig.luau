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

GameConfig.Economy = {
	StartingCoins = 100,

}

GameConfig.Progression = {
	MaxLevel = 100,

	-- XP required for level N is Base * (N ^ Exponent). Tuned so early levels
	-- come fast and midgame requires real investment.
	XPBase = 85,
	XPExponent = 1.55,
}

GameConfig.Combat = {
	-- Fallbacks only. A player's real numbers come from ClassConfig; these
	-- cover the window before a profile loads and anything that asks for a
	-- baseline without a class.
	BaseHealth = 100,
	BaseWalkSpeed = 16,
	BaseDamage = 5,
	BaseAttackSpeed = 1.0,
	BaseCritChance = 2,
	BaseCritDamage = 50,

	-- Health gained per character level, on top of the class's base, so
	-- levelling always feels like it did something.
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
