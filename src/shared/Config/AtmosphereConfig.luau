--!strict
--[[
	AtmosphereConfig — fog and air, per region.

	Lighting is not managed by Rojo (default.project.json only claims
	ReplicatedStorage, ServerScriptService and StarterPlayerScripts), so the
	only mergeable way to own atmosphere is to drive it from a script at
	runtime. That is also what ROADMAP Phase 5b asks for: a client script that
	blends fog by player position rather than one global setting.

	Two profiles, blended by depth into the zone:

	  - **Village** — inside the walls. Air is clear enough to read the market
	    and the castle from across the square. Fog exists mostly to soften the
	    skyline, not to hide anything.
	  - **Wilds** — beyond the gate. Genuinely thick: the brief is mist you
	    push through, so draw distance drops hard and the far treeline
	    disappears into it.

	Geometry these numbers depend on, from CLAUDE.md:
	  - the gate faces south at z = 66, road running out to z ~= 24
	  - Ground_Pasture (village ground) ends at about z = -31
	  - Zone 1 runs from there south to roughly z = -470

	So the blend is centred just past the gate and spread wide enough that
	walking out is a gradual thickening rather than a visible line.

	WHICH PROPERTIES ACTUALLY DO ANYTHING
	-------------------------------------
	**An Atmosphere object overrides legacy fog.** While one is parented to
	Lighting, FogStart / FogEnd / FogColor are ignored entirely, and all the
	visible thickness comes from Density, Offset and Haze. The legacy values
	are still set below, but only as a fallback for the case where something
	removes the Atmosphere — do NOT tune them expecting to see a change.

	Tuning notes, because "heavy fog" and "playable" pull against each other:
	  - Density is the main dial. ~0.3 is a light haze, ~0.5 reads as weather,
	    0.7+ is genuinely heavy. Past ~0.85 it whites out and the HUD stops
	    reading against it.
	  - Offset pushes the fog toward the camera. It is what makes air feel
	    close and oppressive rather than merely distant.
	  - Haze and Glare are what sell it as weather instead of a distance fade.
	  - Whatever you do, enemies must stay visible at engagement range.
	    CombatController targets out to 95 studs and bows reach 90, so the
	    effective view distance has to stay comfortably above that or players
	    get hit by things they cannot see.
]]

local AtmosphereConfig = {}

export type Profile = {
	Name: string,
	-- Classic Lighting fog. Still does the heavy lifting for draw distance.
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	-- Atmosphere object. This is what makes it look like air rather than a
	-- distance fade.
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
	-- Ambient bounce, so the ground does not stay black under thick air.
	OutdoorAmbient: Color3,
}

AtmosphereConfig.Profiles = {
	--[[
		Inside the walls. Still clearly foggy — the brief is heavy everywhere,
		not just outside — but held back enough that the castle and the far
		side of the market stay readable.
	]]
	Village = {
		Name = "Village",
		FogColor = Color3.fromRGB(150, 168, 186),
		FogStart = 40,
		FogEnd = 600,
		Density = 0.48,
		Offset = 0.20,
		Color = Color3.fromRGB(184, 196, 210),
		Decay = Color3.fromRGB(96, 110, 132),
		Glare = 0.35,
		Haze = 2.2,
		OutdoorAmbient = Color3.fromRGB(104, 112, 128),
	} :: Profile,

	--[[
		Beyond the gate. Heavier air than the village, with the treeline
		dissolving rather than ending.

		These numbers were MEASURED, not guessed. The original 0.72 / offset
		0.40 was tested against reference blocks placed at 30/60/90/95 studs
		down the route: at 0.72 everything past about 40 studs vanished, so an
		enemy at bow range (90) or CombatController's reach (95) was invisible.
		Lowering Offset is what buys back the near field — it is the dial that
		pulls fog toward the camera — so density can stay high for distance
		while the first hundred studs read clearly.

		If you retune, re-run that test rather than eyeballing it.
	]]
	Wilds = {
		Name = "Wilds",
		FogColor = Color3.fromRGB(126, 142, 152),
		FogStart = 30,
		FogEnd = 330,
		Density = 0.62,
		Offset = 0.10,
		Color = Color3.fromRGB(172, 186, 194),
		Decay = Color3.fromRGB(70, 84, 96),
		Glare = 0.55,
		Haze = 3.0,
		OutdoorAmbient = Color3.fromRGB(92, 102, 114),
	} :: Profile,
}

--[[
	Blend geometry. Z decreases as the player leaves the village, so a lower Z
	means more Wilds. Centred a little past the gate so the change starts on
	the approach rather than at the arch itself.
]]
AtmosphereConfig.BoundaryZ = -10
AtmosphereConfig.BlendStuds = 110

--[[ How often the controller re-evaluates, in seconds. ]]
AtmosphereConfig.UpdateInterval = 0.2

--[[
	Seconds to ease toward a newly computed target. Without this, respawning or
	teleporting snaps the fog and it reads as a graphics glitch.
]]
AtmosphereConfig.EaseSeconds = 0.8

--[[
	Scale applied to Density and Haze when the player has ReducedEffects on.
	Not zero — the fog is a gameplay boundary cue as much as a look, so it
	thins rather than disappearing.
]]
AtmosphereConfig.ReducedEffectsScale = 0.62

--[[
	Returns 0 for fully Village, 1 for fully Wilds.

	Clamped smoothstep rather than linear so the transition has no visible
	start or stop as you walk through it.
]]
function AtmosphereConfig.GetBlend(z: number): number
	local half = AtmosphereConfig.BlendStuds * 0.5
	local raw = (AtmosphereConfig.BoundaryZ + half - z) / AtmosphereConfig.BlendStuds
	local t = math.clamp(raw, 0, 1)
	return t * t * (3 - 2 * t)
end

return AtmosphereConfig
