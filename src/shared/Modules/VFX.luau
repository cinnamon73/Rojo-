--!strict
--[[
	VFX — small, asset-free effect primitives.

	Every effect here is built from parts, particles and lights — nothing needs
	an uploaded texture or sound, so effects work on a fresh clone of the repo.
	(ParticleEmitters fall back to their default sprite when no texture is set,
	which reads as a soft spark and is exactly right for placeholder-free VFX.)

	All functions are fire-and-forget: they clean up after themselves with
	Debris or a delayed destroy, never yield, and never error on a dead target.
	Callers pass a colour — almost always the class ThemeColor — so a
	Necromancer's magic is purple everywhere without any effect knowing what a
	Necromancer is.

	Server-side use is the normal case (parts replicate to everyone). Nothing
	here touches state, so the client could reuse it for local-only flourishes.
]]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local VFX = {}

local function basePart(shape: Enum.PartType, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--[[ Soft impact flash plus a spark burst. The bread-and-butter hit effect. ]]
function VFX.Burst(position: Vector3, color: Color3, scale: number?)
	local size = (scale or 1) * 2.2

	local flash = basePart(Enum.PartType.Ball, Vector3.new(size, size, size) * 0.4, color)
	flash.Position = position
	flash.Transparency = 0.2
	flash.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.25, 0.45)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 * (scale or 1)),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.1)
	emitter.LightEmission = 0.8
	emitter.Rate = 0
	emitter.Parent = flash
	emitter:Emit(math.floor(14 * (scale or 1)))

	TweenService:Create(flash, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size),
		Transparency = 1,
	}):Play()

	Debris:AddItem(flash, 1)
end

--[[
	A shot line from muzzle to impact, faded out over a beat.

	Damage in this game is instant, so the tracer is drawn stretched over the
	whole flight path rather than travelling — it reads as a fast shot instead
	of lying about where the projectile is.
]]
function VFX.Tracer(from: Vector3, to: Vector3, color: Color3, thickness: number?)
	local distance = (to - from).Magnitude
	if distance < 1 then
		return
	end

	local beam = basePart(Enum.PartType.Block, Vector3.new(thickness or 0.14, thickness or 0.14, distance), color)
	beam.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
	beam.Transparency = 0.1
	beam.Parent = Workspace

	TweenService:Create(beam, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	}):Play()

	Debris:AddItem(beam, 0.4)
end

--[[ Expanding flat ring on the ground. Casts, pulses, area telegraphs. ]]
function VFX.GroundRing(position: Vector3, color: Color3, radius: number, duration: number?)
	local ring = basePart(Enum.PartType.Cylinder, Vector3.new(0.18, 1, 1), color)
	-- Cylinders lie along local X; roll 90 about Z stands the axis up so the
	-- disc lies flat. The repo's own geometry lessons, applied.
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.25
	ring.Parent = Workspace

	TweenService:Create(ring, TweenInfo.new(duration or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.18, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()

	Debris:AddItem(ring, (duration or 0.45) + 0.2)
end

--[[
	A glow that follows a character for `duration`: light plus rising motes.

	Attached to the root part, so it survives the character walking, jumping
	and being flung. Returns nothing; cleans itself up.
]]
function VFX.Aura(character: Model, color: Color3, duration: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "VFX_Aura"
	attachment.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, 5, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.25)
	emitter.LightEmission = 0.7
	emitter.Rate = 18
	emitter.Parent = attachment

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 9
	light.Brightness = 1.4
	light.Parent = attachment

	task.delay(duration, function()
		if attachment.Parent then
			-- Stop emitting first so live particles finish instead of popping.
			emitter.Enabled = false
			light.Enabled = false
			Debris:AddItem(attachment, 1)
		end
	end)
end

--[[ Summon entrance: ring plus an upward column of motes. ]]
function VFX.Rise(position: Vector3, color: Color3)
	VFX.GroundRing(position, color, 4, 0.5)

	local column = basePart(Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), color)
	column.Position = position
	column.Transparency = 1
	column.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Lifetime = NumberRange.new(0.6, 1.0)
	emitter.Speed = NumberRange.new(8, 12)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.2)
	emitter.LightEmission = 0.8
	emitter.Rate = 0
	emitter.Parent = column
	emitter:Emit(22)

	Debris:AddItem(column, 1.4)
end

return VFX
