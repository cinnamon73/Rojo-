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

--========================================================================
-- Public
--========================================================================

--[[
	Builds the weapon model for an item instance.

	Returns nil if the template is not a weapon, so callers can fall through to
	the generic armour builder without special-casing.
]]
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
	elseif archetype == "Greatsword" then
		return CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	end

	return CFrame.new(0, -0.7, 0)
end

--[[
	Swing arc for an archetype, as (restC0, swungC0) offsets applied to the
	joint. Kept here so weapon feel lives with weapon geometry.
]]
function WeaponModels.GetSwing(archetype: string?): (CFrame, CFrame)
	local rest = WeaponModels.GetGripOffset(archetype)

	if archetype == "Greatsword" then
		-- Heavy overhead chop.
		return rest, rest * CFrame.Angles(math.rad(-110), 0, math.rad(20))
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
