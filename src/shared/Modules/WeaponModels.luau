--!strict
--[[
	WeaponModels — placeholder weapon geometry, built per archetype.

	Each build returns a Model whose PrimaryPart is a Handle. The handle is what
	gets jointed to the hand; everything else is welded to it, so the whole
	weapon swings as one rigid piece and animation only ever touches one joint.

	Colour and material come from the CLASS, not from a rolled item — shape
	reads archetype, tint reads class. Callers pass them in, so this module
	knows nothing about where a weapon came from.

	Replacing these with real meshes means swapping the builder body; the
	jointing and animation below do not care what shape they are moving.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Config")

local WeaponModels = {}

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[ Welds `part` to `handle` at `offset` and positions it there. ]]
local function attach(handle: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = handle.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

local GRIP = Color3.fromRGB(58, 44, 34)
local GUARD = Color3.fromRGB(122, 100, 62)

--========================================================================
-- Archetype builders
--========================================================================

local builders: { [string]: (Model, BasePart, Color3, Enum.Material) -> () } = {}

builders.Sword = function(model, handle, color, material)
	local blade = makePart("Blade", Vector3.new(0.22, 3.6, 0.7), color, material, model)
	attach(handle, blade, CFrame.new(0, 2.2, 0))

	local tip = makePart("Tip", Vector3.new(0.22, 0.6, 0.7), color, material, model)
	attach(handle, tip, CFrame.new(0, 4.2, 0) * CFrame.Angles(math.rad(45), 0, 0))

	local guard = makePart("Guard", Vector3.new(0.3, 0.24, 1.7), GUARD, Enum.Material.Metal, model)
	attach(handle, guard, CFrame.new(0, 0.5, 0))

	local pommel = makePart("Pommel", Vector3.new(0.4, 0.4, 0.4), GUARD, Enum.Material.Metal, model)
	pommel.Shape = Enum.PartType.Ball
	attach(handle, pommel, CFrame.new(0, -0.7, 0))
end

builders.Greatsword = function(model, handle, color, material)
	local blade = makePart("Blade", Vector3.new(0.3, 5.4, 1.25), color, material, model)
	attach(handle, blade, CFrame.new(0, 3.4, 0))

	local tip = makePart("Tip", Vector3.new(0.3, 0.9, 1.25), color, material, model)
	attach(handle, tip, CFrame.new(0, 6.4, 0) * CFrame.Angles(math.rad(45), 0, 0))

	local guard = makePart("Guard", Vector3.new(0.4, 0.32, 2.6), GUARD, Enum.Material.Metal, model)
	attach(handle, guard, CFrame.new(0, 0.62, 0))

	local pommel = makePart("Pommel", Vector3.new(0.5, 0.5, 0.5), GUARD, Enum.Material.Metal, model)
	attach(handle, pommel, CFrame.new(0, -1.0, 0))
end

builders.Dagger = function(model, handle, color, material)
	local blade = makePart("Blade", Vector3.new(0.16, 1.5, 0.42), color, material, model)
	attach(handle, blade, CFrame.new(0, 1.1, 0))

	local tip = makePart("Tip", Vector3.new(0.16, 0.36, 0.42), color, material, model)
	attach(handle, tip, CFrame.new(0, 1.95, 0) * CFrame.Angles(math.rad(45), 0, 0))

	local guard = makePart("Guard", Vector3.new(0.22, 0.16, 0.85), GUARD, Enum.Material.Metal, model)
	attach(handle, guard, CFrame.new(0, 0.38, 0))
end

builders.Bow = function(model, handle, color, material)
	-- Two angled limbs plus a string reads as a bow far better than one curve
	-- approximated with boxes.
	for index, sign in ipairs({ 1, -1 }) do
		local limb = makePart("Limb" .. index, Vector3.new(0.2, 2.1, 0.34), color, material, model)
		attach(handle, limb, CFrame.new(0, sign * 1.15, 0.22) * CFrame.Angles(math.rad(sign * 18), 0, 0))

		local tip = makePart("LimbTip" .. index, Vector3.new(0.16, 0.9, 0.26), color, material, model)
		attach(handle, tip, CFrame.new(0, sign * 2.3, 0.62) * CFrame.Angles(math.rad(sign * 42), 0, 0))
	end

	local string_ = makePart("String", Vector3.new(0.06, 4.6, 0.06), Color3.fromRGB(228, 226, 214), Enum.Material.SmoothPlastic, model)
	attach(handle, string_, CFrame.new(0, 0, 0.92))
end

builders.Staff = function(model, handle, color, material)
	local shaft = makePart("Shaft", Vector3.new(0.24, 5.0, 0.24), GRIP, Enum.Material.Wood, model)
	attach(handle, shaft, CFrame.new(0, 2.2, 0))

	local orb = makePart("Orb", Vector3.new(1.05, 1.05, 1.05), color, Enum.Material.Neon, model)
	orb.Shape = Enum.PartType.Ball
	attach(handle, orb, CFrame.new(0, 5.0, 0))

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	light.Parent = orb

	-- Three prongs cradling the orb.
	for index = 1, 3 do
		local angle = (index / 3) * math.pi * 2
		local prong = makePart("Prong" .. index, Vector3.new(0.14, 0.9, 0.14), GUARD, Enum.Material.Metal, model)
		attach(handle, prong, CFrame.new(math.cos(angle) * 0.42, 4.5, math.sin(angle) * 0.42)
			* CFrame.Angles(math.rad(math.sin(angle) * 18), 0, math.rad(-math.cos(angle) * 18)))
	end
end


--[[ Berserker: a brutal double-headed axe. Reads as weight, not finesse. ]]
builders.Greataxe = function(model, handle, color, material)
	local haft = makePart("Haft", Vector3.new(0.26, 4.6, 0.26), GRIP, Enum.Material.Wood, model)
	attach(handle, haft, CFrame.new(0, 2.0, 0))

	for _, sign in ipairs({ 1, -1 }) do
		local head = makePart("Head" .. tostring(sign), Vector3.new(0.28, 1.7, 1.1), color, material, model)
		attach(handle, head, CFrame.new(0, 3.6, sign * 0.75))

		local edge = makePart("Edge" .. tostring(sign), Vector3.new(0.24, 1.9, 0.5), color, material, model)
		attach(handle, edge, CFrame.new(0, 3.6, sign * 1.35) * CFrame.Angles(math.rad(sign * -14), 0, 0))
	end

	local spike = makePart("Spike", Vector3.new(0.2, 0.9, 0.2), GUARD, Enum.Material.Metal, model)
	attach(handle, spike, CFrame.new(0, 4.7, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)))
end

--[[ Musketeer: long barrel, wooden stock, brass fittings. ]]
builders.Musket = function(model, handle, color, material)
	local stock = makePart("Stock", Vector3.new(0.34, 1.6, 0.6), GRIP, Enum.Material.Wood, model)
	attach(handle, stock, CFrame.new(0, 0.2, 0.12) * CFrame.Angles(math.rad(12), 0, 0))

	local barrel = makePart("Barrel", Vector3.new(0.22, 3.9, 0.22), color, material, model)
	attach(handle, barrel, CFrame.new(0, 2.6, -0.08))

	local band = makePart("Band", Vector3.new(0.3, 0.2, 0.3), GUARD, Enum.Material.Metal, model)
	attach(handle, band, CFrame.new(0, 1.6, -0.08))

	local muzzle = makePart("Muzzle", Vector3.new(0.3, 0.35, 0.3), GUARD, Enum.Material.Metal, model)
	attach(handle, muzzle, CFrame.new(0, 4.5, -0.08))
end

--[[ Necromancer: crooked dark staff crowned with a horned soul-orb. ]]
builders.NecroStaff = function(model, handle, color, material)
	local shaft = makePart("Shaft", Vector3.new(0.22, 4.6, 0.22), Color3.fromRGB(46, 38, 52), Enum.Material.Wood, model)
	attach(handle, shaft, CFrame.new(0, 2.0, 0))

	local crook = makePart("Crook", Vector3.new(0.2, 1.1, 0.2), Color3.fromRGB(46, 38, 52), Enum.Material.Wood, model)
	attach(handle, crook, CFrame.new(0, 4.5, -0.28) * CFrame.Angles(math.rad(-28), 0, 0))

	local orb = makePart("Orb", Vector3.new(0.85, 0.85, 0.85), color, Enum.Material.Neon, model)
	orb.Shape = Enum.PartType.Ball
	attach(handle, orb, CFrame.new(0, 5.1, 0))

	for _, sign in ipairs({ 1, -1 }) do
		local horn = makePart("Horn" .. tostring(sign), Vector3.new(0.16, 0.8, 0.16), Color3.fromRGB(226, 222, 210), Enum.Material.Slate, model)
		attach(handle, horn, CFrame.new(sign * 0.42, 5.35, 0) * CFrame.Angles(0, 0, math.rad(sign * -30)))
	end

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	light.Parent = orb
end

--[[ Paladin: a broad consecrated blade with a radiant winged guard. ]]
builders.PaladinBlade = function(model, handle, color, material)
	local blade = makePart("Blade", Vector3.new(0.24, 3.7, 0.85), color, material, model)
	attach(handle, blade, CFrame.new(0, 2.25, 0))

	local fuller = makePart("Fuller", Vector3.new(0.26, 3.0, 0.2), Color3.fromRGB(250, 240, 210), Enum.Material.Neon, model)
	attach(handle, fuller, CFrame.new(0, 2.1, 0))

	local tip = makePart("Tip", Vector3.new(0.24, 0.65, 0.85), color, material, model)
	attach(handle, tip, CFrame.new(0, 4.35, 0) * CFrame.Angles(math.rad(45), 0, 0))

	for _, sign in ipairs({ 1, -1 }) do
		local wing = makePart("Wing" .. tostring(sign), Vector3.new(0.28, 0.7, 0.8), GUARD, Enum.Material.Metal, model)
		attach(handle, wing, CFrame.new(0, 0.62, sign * 0.75) * CFrame.Angles(math.rad(sign * 24), 0, 0))
	end

	local pommel = makePart("Pommel", Vector3.new(0.42, 0.42, 0.42), GUARD, Enum.Material.Metal, model)
	pommel.Shape = Enum.PartType.Ball
	attach(handle, pommel, CFrame.new(0, -0.7, 0))
end

--[[ King: a gilded longsword with a crowned crossguard and a gem pommel. ]]
builders.RoyalBlade = function(model, handle, color, material)
	local blade = makePart("Blade", Vector3.new(0.24, 3.9, 0.8), Color3.fromRGB(226, 228, 236), Enum.Material.Metal, model)
	attach(handle, blade, CFrame.new(0, 2.35, 0))

	local tip = makePart("Tip", Vector3.new(0.24, 0.7, 0.8), Color3.fromRGB(226, 228, 236), Enum.Material.Metal, model)
	attach(handle, tip, CFrame.new(0, 4.6, 0) * CFrame.Angles(math.rad(45), 0, 0))

	local guard = makePart("Guard", Vector3.new(0.34, 0.26, 1.9), color, material, model)
	attach(handle, guard, CFrame.new(0, 0.52, 0))

	-- Three points of a crown rising off the guard.
	for index = -1, 1 do
		local point = makePart("Crown" .. tostring(index + 2), Vector3.new(0.2, 0.5, 0.24), color, material, model)
		attach(handle, point, CFrame.new(0, 0.85, index * 0.6) * CFrame.Angles(math.rad(index * -12), 0, 0))
	end

	local gem = makePart("Gem", Vector3.new(0.38, 0.38, 0.38), Color3.fromRGB(196, 64, 88), Enum.Material.Neon, model)
	gem.Shape = Enum.PartType.Ball
	attach(handle, gem, CFrame.new(0, -0.72, 0))

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 224, 140)
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = gem
end

--========================================================================
-- Offhands
--========================================================================

--[[
	Offhand builders keyed by ClassConfig.Offhand. Static: welded to the left
	arm, never animated, so there is no motor and no swing entry for them.
]]
local offhandBuilders: { [string]: (Model, BasePart, Color3, Enum.Material) -> () } = {}

offhandBuilders.Dagger = builders.Dagger

offhandBuilders.Shield = function(model, handle, color, material)
	local face = makePart("Face", Vector3.new(0.3, 2.2, 2.2), color, material, model)
	face.Shape = Enum.PartType.Cylinder
	attach(handle, face, CFrame.new(0, 0, 0))

	local boss = makePart("Boss", Vector3.new(0.5, 0.7, 0.7), GUARD, Enum.Material.Metal, model)
	boss.Shape = Enum.PartType.Cylinder
	attach(handle, boss, CFrame.new(-0.2, 0, 0))
end

--========================================================================
-- Public
--========================================================================

--[[
	Builds the weapon model for an item instance.

	Returns nil if the template is not a weapon, so callers can fall through to
	the generic armour builder without special-casing.
]]
--[[
	Blade length per archetype, for the trail's tip attachment. Ranged weapons
	are absent on purpose: a musket does not leave an arc.
]]
local TRAIL_TIP_Y: { [string]: number } = {
	Sword = 4.4,
	Dagger = 2.1,
	Greatsword = 6.8,
	Greataxe = 4.9,
	PaladinBlade = 4.6,
	RoyalBlade = 4.9,
}

local addSwingTrail

function WeaponModels.Build(archetype: string?, color: Color3, material: Enum.Material, name: string?): Model?
	local builder = builders[archetype or ""]
	if not builder then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = name or (archetype :: string)

	local handle = makePart("Handle", Vector3.new(0.32, 1.2, 0.32), GRIP, Enum.Material.Wood, model)
	model.PrimaryPart = handle

	builder(model, handle, color, material)

	--[[
		The swing trail. Built disabled into every melee weapon; the client FX
		layer enables it only during strike frames. The ribbon between these
		two attachments IS what makes a 0.07s strike readable — the arc paints
		itself even when the weapon moves too fast to track.
	]]
	addSwingTrail(handle, archetype, color)

	return model
end

--[[
	Builds the weapon from an uploaded mesh when the item has one.

	A SpecialMesh rather than a MeshPart: MeshPart.MeshId cannot be assigned at
	runtime, and AssetService:CreateMeshPartAsync yields on every spawn. A
	FileMesh on the Handle renders the whole weapon from one part, so the mesh
	build is also CHEAPER than the part assembly it replaces (1 part, not 5-8).

	The mesh is authored with its origin at the grip and the weapon running up
	+Y (tools/blender_weapons.py), which is the same frame the Handle uses — so
	GetGripOffset, the trail attachments and every swing animation are unchanged.
]]
function WeaponModels.BuildFromItem(weapon: any, name: string?): Model?
	local appearance = weapon and weapon.Appearance
	local meshId = appearance and appearance.MeshId or 0

	if meshId <= 0 then
		-- No upload yet: fall back to the part-built model rather than nothing.
		return WeaponModels.Build(
			weapon.Archetype,
			appearance.Color,
			appearance.Material,
			name
		)
	end

	local model = Instance.new("Model")
	model.Name = name or weapon.Id

	local handle = makePart("Handle", Vector3.new(0.32, 1.2, 0.32),
		appearance.Color, appearance.Material, model)
	model.PrimaryPart = handle

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = "rbxassetid://" .. tostring(meshId)
	mesh.Scale = Vector3.one
	mesh.Parent = handle

	addSwingTrail(handle, weapon.Archetype, appearance.Color)

	return model
end

--[[
	The swing trail, shared by both build paths.

	Built disabled into every melee weapon; the client FX layer enables it only
	during strike frames. The ribbon between these two attachments IS what makes
	a 0.07s strike readable — the arc paints itself even when the weapon moves
	too fast to track.
]]
function addSwingTrail(handle: BasePart, archetype: string?, color: Color3)
	local tipY = TRAIL_TIP_Y[archetype or ""]
	if tipY then
		local base = Instance.new("Attachment")
		base.Name = "TrailBase"
		base.Position = Vector3.new(0, 0.8, 0)
		base.Parent = handle

		local tip = Instance.new("Attachment")
		tip.Name = "TrailTip"
		tip.Position = Vector3.new(0, tipY, 0)
		tip.Parent = handle

		local trail = Instance.new("Trail")
		trail.Name = "SwingTrail"
		trail.Attachment0 = base
		trail.Attachment1 = tip
		trail.Color = ColorSequence.new(color)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Lifetime = 0.22
		trail.LightEmission = 0.9
		trail.FaceCamera = true
		trail.Enabled = false
		trail.Parent = handle
	end
end

--[[
	Builds an offhand model, or nil for a kind with no builder. The offhand is
	decorative: welded flat to the left arm by CharacterService, no joint.
]]
function WeaponModels.BuildOffhand(kind: string?, color: Color3, material: Enum.Material, name: string?): Model?
	local builder = offhandBuilders[kind or ""]
	if not builder then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = name or (kind :: string)

	local handle = makePart("Handle", Vector3.new(0.3, 0.9, 0.3), GRIP, Enum.Material.Wood, model)
	model.PrimaryPart = handle

	builder(model, handle, color, material)

	return model
end

--[[
	Where the handle sits relative to the hand, per archetype.

	Bows are held across the body rather than pointed forward, and staves sit
	upright — both look wrong at the sword offset.
]]
function WeaponModels.GetGripOffset(archetype: string?): CFrame
	if archetype == "Bow" then
		return CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(90), math.rad(90), 0)
	elseif archetype == "Staff" then
		return CFrame.new(0, -0.7, 0)
	elseif archetype == "Greatsword" or archetype == "Greataxe" then
		return CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	elseif archetype == "Musket" then
		-- Held low and angled forward, stock into the shoulder side.
		return CFrame.new(0, -0.5, 0.15) * CFrame.Angles(math.rad(-64), 0, 0)
	elseif archetype == "NecroStaff" then
		return CFrame.new(0, -0.7, 0)
	end

	return CFrame.new(0, -0.7, 0)
end

--[[ Archetypes that swing rather than shoot. Combos only make sense here. ]]
local MELEE = {
	Sword = true,
	Dagger = true,
	Greatsword = true,
	Greataxe = true,
	PaladinBlade = true,
	RoyalBlade = true,
}

function WeaponModels.IsMelee(archetype: string?): boolean
	return MELEE[archetype or ""] == true
end

--[[
	One step of the melee combo: slash, backhand, overhead finisher.

	Three distinct arcs so a repeating combo reads as swordplay instead of the
	same chop looped. Step wraps 1-3; ranged archetypes never come through here
	— they get their single GetSwing action (draw, recoil, thrust).
]]
function WeaponModels.GetComboSwing(archetype: string?, step: number): (CFrame, CFrame)
	local rest = WeaponModels.GetGripOffset(archetype)
	local index = ((step - 1) % 3) + 1

	if index == 1 then
		-- Diagonal slash, right to left.
		return rest, rest * CFrame.Angles(math.rad(-85), 0, math.rad(30))
	elseif index == 2 then
		-- Backhand return, opposite roll so it visibly comes back the other way.
		return rest, rest * CFrame.Angles(math.rad(-45), 0, math.rad(-80))
	end

	-- Overhead finisher: bigger wind, slight forward push.
	return rest, rest * CFrame.new(0, 0.4, -0.5) * CFrame.Angles(math.rad(-120), 0, 0)
end

--[[
	Swing arc for an archetype, as (restC0, swungC0) offsets applied to the
	joint. Kept here so weapon feel lives with weapon geometry.
]]
function WeaponModels.GetSwing(archetype: string?): (CFrame, CFrame)
	local rest = WeaponModels.GetGripOffset(archetype)

	if archetype == "Greatsword" or archetype == "Greataxe" then
		-- Heavy overhead chop.
		return rest, rest * CFrame.Angles(math.rad(-110), 0, math.rad(20))
	elseif archetype == "Musket" then
		-- Recoil kick, not a swing.
		return rest, rest * CFrame.new(0, -0.35, 0.3) * CFrame.Angles(math.rad(14), 0, 0)
	elseif archetype == "NecroStaff" then
		-- Thrust the orb forward, same read as the plain staff.
		return rest, rest * CFrame.new(0, 0.3, -0.5) * CFrame.Angles(math.rad(-28), 0, 0)
	elseif archetype == "Dagger" then
		-- Quick forward stab.
		return rest, rest * CFrame.new(0, 0.5, -0.8) * CFrame.Angles(math.rad(-35), 0, 0)
	elseif archetype == "Bow" then
		-- Draw back rather than swing.
		return rest, rest * CFrame.new(0, 0, 0.4) * CFrame.Angles(0, math.rad(-18), 0)
	elseif archetype == "Staff" then
		-- Thrust the orb forward.
		return rest, rest * CFrame.new(0, 0.3, -0.5) * CFrame.Angles(math.rad(-28), 0, 0)
	end

	-- Sword: diagonal slash.
	return rest, rest * CFrame.Angles(math.rad(-85), 0, math.rad(30))
end

return WeaponModels
