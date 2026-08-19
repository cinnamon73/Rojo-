--!strict
--[[
	AtmosphereController — drives fog and air from the player's position.

	Lighting is not in the Rojo tree, so this is the only way to own atmosphere
	in version control rather than in the place file. It runs entirely on the
	client: fog is presentation, nothing here is authoritative, and a player
	with it broken sees ugly weather rather than a broken game.

	Idempotent by construction, per the repo's bootstrap rule. It reuses an
	existing Atmosphere instance if one is already in Lighting rather than
	stacking a second one — two Atmosphere objects do not blend, they fight,
	and the result is a flicker that is very hard to trace back to here.

	Position is read from the character, so before one spawns the profile sits
	wherever the last update left it. That is intentional: snapping to Village
	on every respawn would flash the screen each time you die in the wilds.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local Logger = require(Modules.Logger)
local AtmosphereConfig = require(Config.AtmosphereConfig)

local log = Logger.new("AtmosphereController")
local player = Players.LocalPlayer

local AtmosphereController = {}

local ATMOSPHERE_NAME = "RNGA_Atmosphere"

local client: any = nil
local atmosphere: Atmosphere? = nil
local started = false

-- Current on-screen values, eased toward the target each step.
local current: { [string]: any } = {}

--========================================================================
-- Helpers
--========================================================================

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--[[
	Reuses an Atmosphere already in Lighting whatever its name, so a hand-placed
	one from Studio is adopted instead of duplicated.
]]
local function ensureAtmosphere(): Atmosphere
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		existing.Name = ATMOSPHERE_NAME
		return existing
	end

	local created = Instance.new("Atmosphere")
	created.Name = ATMOSPHERE_NAME
	created.Parent = Lighting
	return created
end

local function reducedEffects(): boolean
	local profile = client and client.Profile
	return profile ~= nil
		and profile.Settings ~= nil
		and profile.Settings.ReducedEffects == true
end

--[[ The blended target for a given depth into the zone. ]]
local function targetFor(z: number): { [string]: any }
	local village = AtmosphereConfig.Profiles.Village
	local wilds = AtmosphereConfig.Profiles.Wilds
	local t = AtmosphereConfig.GetBlend(z)

	local densityScale = if reducedEffects() then AtmosphereConfig.ReducedEffectsScale else 1

	return {
		FogColor = village.FogColor:Lerp(wilds.FogColor, t),
		FogStart = lerp(village.FogStart, wilds.FogStart, t),
		FogEnd = lerp(village.FogEnd, wilds.FogEnd, t),
		Density = lerp(village.Density, wilds.Density, t) * densityScale,
		Offset = lerp(village.Offset, wilds.Offset, t),
		Color = village.Color:Lerp(wilds.Color, t),
		Decay = village.Decay:Lerp(wilds.Decay, t),
		Glare = lerp(village.Glare, wilds.Glare, t),
		Haze = lerp(village.Haze, wilds.Haze, t) * densityScale,
		OutdoorAmbient = village.OutdoorAmbient:Lerp(wilds.OutdoorAmbient, t),
	}
end

local function applyImmediate(values: { [string]: any })
	current = values

	Lighting.FogColor = values.FogColor
	Lighting.FogStart = values.FogStart
	Lighting.FogEnd = values.FogEnd
	Lighting.OutdoorAmbient = values.OutdoorAmbient

	local air = atmosphere
	if air then
		air.Density = values.Density
		air.Offset = values.Offset
		air.Color = values.Color
		air.Decay = values.Decay
		air.Glare = values.Glare
		air.Haze = values.Haze
	end
end

--[[ Eases current toward target. `alpha` is this step's share of the ease. ]]
local function applyEased(target: { [string]: any }, alpha: number)
	if not next(current) then
		applyImmediate(target)
		return
	end

	applyImmediate({
		FogColor = current.FogColor:Lerp(target.FogColor, alpha),
		FogStart = lerp(current.FogStart, target.FogStart, alpha),
		FogEnd = lerp(current.FogEnd, target.FogEnd, alpha),
		Density = lerp(current.Density, target.Density, alpha),
		Offset = lerp(current.Offset, target.Offset, alpha),
		Color = current.Color:Lerp(target.Color, alpha),
		Decay = current.Decay:Lerp(target.Decay, alpha),
		Glare = lerp(current.Glare, target.Glare, alpha),
		Haze = lerp(current.Haze, target.Haze, alpha),
		OutdoorAmbient = current.OutdoorAmbient:Lerp(target.OutdoorAmbient, alpha),
	})
end

--========================================================================
-- Public
--========================================================================

--[[ Forces the profile for a position immediately, skipping the ease. ]]
function AtmosphereController.SnapTo(z: number)
	atmosphere = ensureAtmosphere()
	applyImmediate(targetFor(z))
end

function AtmosphereController.Start(clientState: any)
	if started then
		return
	end
	started = true

	client = clientState
	atmosphere = ensureAtmosphere()

	-- Start from wherever the character already is, so joining inside the
	-- wilds does not begin with a village sky that fades in.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	AtmosphereController.SnapTo(if root then (root :: BasePart).Position.Z else 200)

	task.spawn(function()
		while true do
			task.wait(AtmosphereConfig.UpdateInterval)

			local ok, err = pcall(function()
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp then
					return
				end

				local target = targetFor((hrp :: BasePart).Position.Z)

				-- Share of the remaining distance to cover this tick. Framed
				-- as a fraction of EaseSeconds so the ease feels the same
				-- regardless of UpdateInterval.
				local alpha = math.clamp(
					AtmosphereConfig.UpdateInterval / math.max(AtmosphereConfig.EaseSeconds, 0.01),
					0,
					1
				)

				applyEased(target, alpha)
			end)

			if not ok then
				log:Warn("update failed: %s", tostring(err))
			end
		end
	end)

	log:Info("ready (fog driven by position, boundary z=%d)", AtmosphereConfig.BoundaryZ)
end

return AtmosphereController
