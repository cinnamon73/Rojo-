--[[
	RestoreGround — puts a walkable floor back under both zones.

	============================================================================
	HOW TO RUN
	Paste this whole file into the Roblox Studio Command Bar (View -> Command
	Bar) and press Enter, in EDIT MODE. Same channel as BuildWorld.luau.

	Unlike BuildWorld, this does NOT wipe anything. It only adds floors that
	are missing, and prints what it found, so running it twice is safe and
	running it on a healthy world does nothing at all.
	============================================================================

	WHY THIS EXISTS
	---------------
	Workspace is not managed by Rojo, so ground geometry cannot be delivered as
	a synced file. The repo's convention for world edits is a script under
	tools/ executed against the live session.

	ZONE EXTENTS — reconciled from two sources that disagree
	--------------------------------------------------------
	BuildWorld.luau (the original pass) records:
	    Village      z  52 .. 252
	    Starter zone z  30 .. -360
	    Boss arena   z -400
	ROADMAP Phase 5b (the current plan) puts Zone 1 further south:
	    gate apron z 24, Zone 2 gate ~z -470, arena z -370 .. -450
	CLAUDE.md describes the rebuilt village ground as a cylinder of radius 411
	centred at (0, 380), which is what puts its southern edge at z = -31.

	The slab below spans z +40 .. -500 so it covers BOTH the old extent and the
	newer plan, with no gap at either end. It is wider than Zone 1 strictly
	needs; a stopgap floor that overhangs is harmless, one with holes is not.

	WHAT IT BUILDS
	--------------
	1. Ground_Pasture — the village floor. Rebuilt to the dimensions CLAUDE.md
	   documents: a cylinder of radius 411 centred at (0, 380), which is what
	   puts its southern edge at z = -31.

	2. Ground_Wilds_TEMP — a stopgap slab under Zone 1.

	READ THIS BEFORE KEEPING #2
	---------------------------
	ROADMAP Phase 5b rebuilds Zone 1 on **voxel Terrain**, not Parts. This slab
	is a placeholder so the zone is walkable in the meantime, and it is named
	_TEMP and kept in its own folder precisely so it can be deleted in one
	click when the terrain sculpt lands. Do not build on top of it.

	TWO GEOMETRY DETAILS THAT MATTER
	--------------------------------
	- **Cylinders lie along local X**, so a flat disc needs a 90 degree roll
	  about Z to stand its axis up. This is CLAUDE.md's own recorded lesson and
	  it is easy to get wrong.
	- **The wilds slab sits 0.5 studs BELOW the village disc.** The village
	  ground is a circle, so a rectangle abutting its southernmost point would
	  leave crescent gaps either side of x = 0. The slab therefore overlaps
	  northward and tucks underneath. Coplanar overlap would z-fight; a small
	  vertical offset does not, and half a stud is well inside what a Humanoid
	  steps over without noticing.

	TO UNDO
	-------
	  workspace.World.Terrain.Ground_Pasture:Destroy()
	  workspace.World.StarterZone.Ground_TEMP:Destroy()
]]

local Workspace = game:GetService("Workspace")

-- Documented village geometry. Changing these desynchronises the ground from
-- everything CLAUDE.md says about the world.
local PASTURE_RADIUS = 411
local PASTURE_CENTRE_Z = 380
local SURFACE_Y = 0
local THICKNESS = 4

-- Zone 1 extent. ROADMAP puts the zone at roughly 520 x 460 studs running
-- south from the gate to about z = -470; this is sized a little wider so the
-- perimeter cliffs have something to stand on.
local WILDS_MIN_X, WILDS_MAX_X = -300, 300
local WILDS_MIN_Z = -500

--[[
	North edge, and it is further north than it looks like it should be.

	The village ground is a CIRCLE, so its southern edge curves away from the
	centre line: at x = 0 it reaches z = -31, but at x = +/-300 it does not
	begin until z = 380 - sqrt(411^2 - 300^2) ~= +99. A slab stopping at the
	gate would therefore leave a crescent-shaped hole either side of the road.

	120 clears that worst case with margin. The overlap sits harmlessly under
	the village disc, which is half a stud higher.
]]
local WILDS_MAX_Z = 120

--[[
	Vertical offset below the village surface. Coplanar surfaces z-fight;
	an offset does not. Half a stud is far inside what a Humanoid steps over,
	so the seam is not felt underfoot.
]]
local WILDS_DROP = 0.5

local PASTURE_COLOR = Color3.fromRGB(127, 142, 100)
local WILDS_COLOR = Color3.fromRGB(104, 118, 86)

local created = {}
local skipped = {}

--[[ Finds a descendant by name anywhere under a root, or nil. ]]
local function find(root: Instance, name: string): Instance?
	if root:FindFirstChild(name) then
		return root:FindFirstChild(name)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function folder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = name
	made.Parent = parent
	return made
end

local world = Workspace:FindFirstChild("World")
if not world then
	warn("[RestoreGround] Workspace.World not found — is the right place open? Aborting.")
	return
end

--========================================================================
-- 1. Village floor
--========================================================================

local pasture = find(world, "Ground_Pasture")

if pasture and pasture:IsA("BasePart") then
	table.insert(skipped, string.format(
		"Ground_Pasture already exists at %s (size %s, transparency %.2f)",
		tostring(pasture.Position), tostring(pasture.Size), pasture.Transparency
	))
else
	local part = Instance.new("Part")
	part.Name = "Ground_Pasture"
	part.Shape = Enum.PartType.Cylinder
	-- Cylinder axis is local X: X is the thickness, Y and Z are the diameter.
	part.Size = Vector3.new(THICKNESS, PASTURE_RADIUS * 2, PASTURE_RADIUS * 2)
	-- Roll 90 degrees about Z so the axis stands up and the disc lies flat.
	part.CFrame = CFrame.new(0, SURFACE_Y - THICKNESS / 2, PASTURE_CENTRE_Z)
		* CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CastShadow = true
	part.Color = PASTURE_COLOR
	part.Material = Enum.Material.Grass
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder(world, "Terrain")

	table.insert(created, string.format(
		"Ground_Pasture — cylinder r=%d at (0, %d), top y=%d",
		PASTURE_RADIUS, PASTURE_CENTRE_Z, SURFACE_Y
	))
end

--========================================================================
-- 2. Zone 1 stopgap floor
--========================================================================

local zone = world:FindFirstChild("StarterZone") or world
local existingWilds = find(zone, "Ground_Wilds_TEMP")

if existingWilds then
	table.insert(skipped, "Ground_Wilds_TEMP already exists — left alone")
else
	local width = WILDS_MAX_X - WILDS_MIN_X
	local depth = WILDS_MAX_Z - WILDS_MIN_Z
	local top = SURFACE_Y - WILDS_DROP

	local slab = Instance.new("Part")
	slab.Name = "Ground_Wilds_TEMP"
	slab.Size = Vector3.new(width, THICKNESS, depth)
	slab.Position = Vector3.new(
		(WILDS_MIN_X + WILDS_MAX_X) / 2,
		top - THICKNESS / 2,
		(WILDS_MIN_Z + WILDS_MAX_Z) / 2
	)
	slab.Anchored = true
	slab.CastShadow = true
	slab.Color = WILDS_COLOR
	slab.Material = Enum.Material.Grass
	slab.TopSurface = Enum.SurfaceType.Smooth
	slab.BottomSurface = Enum.SurfaceType.Smooth
	slab.Parent = folder(zone, "Ground_TEMP")

	table.insert(created, string.format(
		"Ground_Wilds_TEMP — %d x %d slab, top y=%.1f (tucked under the village disc)",
		width, depth, top
	))
end

--========================================================================
-- Report
--========================================================================

print("========== RestoreGround ==========")

if #created == 0 then
	print("Nothing created — both floors were already present.")
else
	print(string.format("Created %d:", #created))
	for _, line in ipairs(created) do
		print("  + " .. line)
	end
end

for _, line in ipairs(skipped) do
	print("  = " .. line)
end

print("Ground_Wilds_TEMP is a PLACEHOLDER. ROADMAP 5b replaces Zone 1 with")
print("voxel Terrain — delete workspace.World.StarterZone.Ground_TEMP then.")
print("Save the place (File > Download a Copy over RNGArmory.rbxl) to keep this.")
print("===================================")
