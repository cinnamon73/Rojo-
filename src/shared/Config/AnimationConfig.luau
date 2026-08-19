--!strict
--[[
	AnimationConfig — keyframed swing animations per weapon archetype.

	THE CONTENT SLOT FOR MONSTER-HUNTER-QUALITY SWINGS. The FX system plays a
	real uploaded animation when an id exists here, and falls back to the
	procedural two-joint pose system when it does not. Making the Berserker
	move like the reference GIF is now a matter of pasting ids into this file,
	not writing code:

	  1. Find or author the animation (Studio Animation Editor, a marketplace
	     combat pack, or Mixamo -> Blender -> Roblox retarget).
	  2. Upload it to the CGS Student Development GROUP — group-owned, so both
	     collaborators' sessions can play it. Personal uploads only work for
	     the uploader.
	  3. Paste the id below, one per combo step.

	The ids prefilled here are ROBLOX'S OWN catalog tool animations (the
	classic R15 slash and lunge). They are usable from any game without
	uploading anything, and they are real keyframed motion with body weight —
	a large step up from procedural poses, and a placeholder standard to beat,
	not the destination.

	SpeedScale is how one slash animation serves many weapons: the greataxe
	plays it slow and heavy, the dagger fast and darting. Weight is timing.
]]

local AnimationConfig = {}

--[[
	Per archetype, one id per combo step (1-3). 0 means "no animation — use
	the procedural pose system for this step".

	522635514 = Roblox R15 tool slash. 522638767 = Roblox R15 tool lunge.
]]
AnimationConfig.Swings = {
	Sword = { 522635514, 522635514, 522638767 },
	Dagger = { 522635514, 522635514, 522638767 },
	Greatsword = { 522635514, 522635514, 522638767 },
	-- Step 3 is BerserkerCrash: our own keyframed overhead slam (authored in
	-- tools/BerserkerAnimations.luau, uploaded to the group 2026-08-19).
	Greataxe = { 522635514, 522635514, 98764921362960 },
	PaladinBlade = { 522635514, 522635514, 522638767 },
	RoyalBlade = { 522635514, 522635514, 522638767 },

	-- Ranged archetypes keep the procedural recoil/draw. A slash animation on
	-- a musket reads as nonsense.
	Bow = { 0, 0, 0 },
	Musket = { 0, 0, 0 },
	NecroStaff = { 0, 0, 0 },
	Staff = { 0, 0, 0 },
} :: { [string]: { number } }

--[[ Playback speed per archetype. Below 1 is heavier, above 1 is quicker. ]]
AnimationConfig.SpeedScale = {
	Greataxe = 0.72,
	Greatsword = 0.72,
	Sword = 1.0,
	PaladinBlade = 0.95,
	RoyalBlade = 0.95,
	Dagger = 1.35,
} :: { [string]: number }

--[[
	Per-step speed overrides. Custom-authored animations carry their timing in
	their own keyframes, so they play at 1.0 while catalog placeholders on the
	same weapon still need the heavy-weapon slowdown.
]]
AnimationConfig.StepSpeeds = {
	Greataxe = { 0.72, 0.72, 1.0 },
} :: { [string]: { number } }

--[[ Seconds the blade trail stays on from the start of an uploaded swing,
     before speed scaling. ]]
AnimationConfig.TrailSeconds = 0.5

function AnimationConfig.GetSwingId(archetype: string?, step: number): number
	local set = AnimationConfig.Swings[archetype or ""]
	if not set then
		return 0
	end
	return set[((step - 1) % #set) + 1] or 0
end

function AnimationConfig.GetSpeed(archetype: string?, step: number?): number
	local perStep = AnimationConfig.StepSpeeds[archetype or ""]
	if perStep and step then
		local v = perStep[((step - 1) % #perStep) + 1]
		if v then
			return v
		end
	end
	return AnimationConfig.SpeedScale[archetype or ""] or 1
end

return AnimationConfig
