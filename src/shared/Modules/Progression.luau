--!strict
--[[
	Progression — the XP curve.

	Shared because the server awards XP and the client draws the bar; both must
	agree exactly or the bar will visibly disagree with reality after a level up.

	Curve: XP to go from level N to N+1 is floor(Base * N^Exponent).
	With the Phase 1 defaults (Base 85, Exponent 1.55):

		1 ->  2      85
		5 ->  6     996
	   10 -> 11   3,022
	   25 -> 26  13,240
	   50 -> 51  38,845

	Early levels arrive quickly; midgame needs real investment. Tune via
	GameConfig.Progression rather than editing anything here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local Progression = {}

--[[ XP required to advance FROM `level` to level + 1. ]]
function Progression.XPForNextLevel(level: number): number
	if level >= GameConfig.Progression.MaxLevel then
		return math.huge
	end

	local settings = GameConfig.Progression
	return math.floor(settings.XPBase * (math.max(level, 1) ^ settings.XPExponent))
end

--[[ 0..1 progress toward the next level. Returns 1 at max level. ]]
function Progression.GetProgress(level: number, xp: number): number
	local required = Progression.XPForNextLevel(level)
	if required == math.huge or required <= 0 then
		return 1
	end
	return math.clamp(xp / required, 0, 1)
end

--[[
	Applies an XP gain, rolling over as many levels as it earns.

	Returns (newLevel, newXP, levelsGained). Pure — it does not mutate the
	profile, so the caller decides when to commit. Loop-capped at MaxLevel so a
	huge award cannot spin forever.
]]
function Progression.AddXP(level: number, xp: number, amount: number): (number, number, number)
	if amount <= 0 then
		return level, xp, 0
	end

	local newLevel = level
	local newXP = xp + amount
	local gained = 0

	while newLevel < GameConfig.Progression.MaxLevel do
		local required = Progression.XPForNextLevel(newLevel)
		if newXP < required then
			break
		end

		newXP -= required
		newLevel += 1
		gained += 1
	end

	if newLevel >= GameConfig.Progression.MaxLevel then
		newXP = 0
	end

	return newLevel, newXP, gained
end

--[[ Compact display form: 1500 -> "1.5K", 2400000 -> "2.4M". ]]
function Progression.FormatNumber(value: number): string
	local absolute = math.abs(value)

	if absolute >= 1_000_000_000 then
		return string.format("%.1fB", value / 1_000_000_000)
	elseif absolute >= 1_000_000 then
		return string.format("%.1fM", value / 1_000_000)
	elseif absolute >= 1_000 then
		return string.format("%.1fK", value / 1_000)
	end

	return tostring(math.floor(value))
end

return Progression
