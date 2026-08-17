--[[
	BuildWorld — regenerates the entire world from scratch.

	============================================================================
	HOW TO RUN
	Paste this whole file into the Roblox Studio Command Bar (View -> Command
	Bar) and press Enter, in EDIT MODE. It wipes Workspace.World and rebuilds.
	============================================================================

	Why this file exists: Workspace is not managed by Rojo and `.rbxlx` is
	gitignored, so the map would otherwise live only inside one person's place
	file — unreproducible, unshareable, and lost if that file breaks. Keeping
	the builder in the repo makes the world a build artefact rather than
	something hand-sculpted that nobody can recreate.

	It is idempotent: running it twice produces the same world, not two worlds.

	LAYOUT
	  Village  z 58..240   walled safe hub, spawn, roll altar, no enemies
	  Zone 1   z 40..-350  Verdant Fields, all enemy spawn markers
	  Arena    z -430      Goblin King, behind a 1200-Power gate

	GEOMETRY NOTE — pitched roofs
	  A pitched pair is easy to get wrong, and I got it wrong twice. For a span
	  S at pitch P, each slab must be (S/2)/cos(P) long, centred at S/4
	  horizontally and (S/4)*tan(P) vertically, rotated -sign*P. Using a slab
	  longer than the offset implies makes the halves cross into an X; rotating
	  +sign lifts the outer edge and splays them open like a book. Both bugs
	  are only visible from ground level, so check there before trusting it.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local old = Workspace:FindFirstChild("World"); if old then old:Destroy() end
local en = Workspace:FindFirstChild("Enemies"); if en then en:Destroy() end
local bp = Workspace:FindFirstChild("Baseplate"); if bp then bp:Destroy() end

local rng = Random.new(4242)
local World = Instance.new("Folder"); World.Name = "World"; World.Parent = Workspace
local Village = Instance.new("Folder"); Village.Name = "Village"; Village.Parent = World
local Zone1 = Instance.new("Folder"); Zone1.Name = "VerdantFields"; Zone1.Parent = World
local Ground = Instance.new("Folder"); Ground.Name = "Ground"; Ground.Parent = World

local function P(props, parent)
	local p = Instance.new("Part"); p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent; return p
end

local GRASS = Color3.fromRGB(106,158,88)
local DIRT = Color3.fromRGB(152,126,94)
local STONE = Color3.fromRGB(154,154,160)
local STONED = Color3.fromRGB(118,118,126)
local WOOD = Color3.fromRGB(132,94,58)
local WOODD = Color3.fromRGB(88,62,38)
local ROOF = Color3.fromRGB(150,68,54)
local ROOF2 = Color3.fromRGB(94,72,60)

--[[ The correct pitched pair. See the geometry note at the top. ]]
local function pitchedPair(parent, name, cf, span, depth, pitch, thickness, color, material, axis)
	local rad = math.rad(pitch)
	local slab = (span / 2) / math.cos(rad) + 0.7
	local ox, oy = span / 4, (span / 4) * math.tan(rad)
	for _, s in ipairs({ -1, 1 }) do
		if axis == "Z" then
			P({ Name = name, Size = Vector3.new(depth, thickness, slab),
				CFrame = cf * CFrame.new(0, oy, s * ox) * CFrame.Angles(math.rad(s * pitch), 0, 0),
				Color = color, Material = material }, parent)
		else
			P({ Name = name, Size = Vector3.new(slab, thickness, depth),
				CFrame = cf * CFrame.new(s * ox, oy, 0) * CFrame.Angles(0, 0, math.rad(-s * pitch)),
				Color = color, Material = material }, parent)
		end
	end
end

P({ Name = "Field", Size = Vector3.new(700,4,1000), CFrame = CFrame.new(0,-2,-140), Color = GRASS, Material = Enum.Material.Grass }, Ground)
P({ Name = "VillageGround", Size = Vector3.new(240,5,240), CFrame = CFrame.new(0,-1.4,150), Color = DIRT, Material = Enum.Material.Ground }, Ground)

--============================================================ HOUSES
local PITCH = 38
local function house(x, z, w, d, h, rot, wallColor, roofColor, name)
	local m = Instance.new("Model"); m.Name = name; m.Parent = Village
	local cf = CFrame.new(x,0,z) * CFrame.Angles(0, math.rad(rot), 0)
	local function L(ox, oy, oz) return cf * CFrame.new(ox, oy, oz) end

	P({ Name="Floor", Size=Vector3.new(w,0.8,d), CFrame=L(0,0.6,0), Color=WOODD, Material=Enum.Material.WoodPlanks }, m)
	P({ Name="W1", Size=Vector3.new(w,h,0.7), CFrame=L(0,h/2+1,-d/2), Color=wallColor, Material=Enum.Material.Concrete }, m)
	P({ Name="W2", Size=Vector3.new(w,h,0.7), CFrame=L(0,h/2+1, d/2), Color=wallColor, Material=Enum.Material.Concrete }, m)
	P({ Name="W3", Size=Vector3.new(0.7,h,d), CFrame=L(-w/2,h/2+1,0), Color=wallColor, Material=Enum.Material.Concrete }, m)
	P({ Name="W4", Size=Vector3.new(0.7,h,d), CFrame=L( w/2,h/2+1,0), Color=wallColor, Material=Enum.Material.Concrete }, m)

	for _, ox in ipairs({ -w/2+0.45, w/2-0.45 }) do
		for _, oz in ipairs({ -d/2, d/2 }) do
			P({ Name="Beam", Size=Vector3.new(0.6,h,0.6), CFrame=L(ox,h/2+1,oz), Color=WOODD, Material=Enum.Material.Wood }, m)
		end
	end

	-- Stepped gable fills the triangle under the roof at each end.
	local half, peak = w/2, (w/2) * math.tan(math.rad(PITCH))
	for _, oz in ipairs({ -d/2, d/2 }) do
		for step = 1, 5 do
			local frac = step/5
			P({ Name="Gable", Size=Vector3.new(w*(1-frac)+0.6, peak/5+0.1, 0.7),
				CFrame=L(0, h+1+peak*(frac-0.1)-peak/10, oz), Color=wallColor, Material=Enum.Material.Concrete }, m)
		end
	end

	P({ Name="Door", Size=Vector3.new(3,4.6,0.35), CFrame=L(0,2.9,-d/2-0.25), Color=WOODD, Material=Enum.Material.WoodPlanks }, m)
	for _, ox in ipairs({ -w*0.3, w*0.3 }) do
		for _, sz in ipairs({ -1, 1 }) do
			P({ Name="Window", Size=Vector3.new(2,2,0.3), CFrame=L(ox,h*0.66,sz*(d/2+0.25)),
				Color=Color3.fromRGB(206,228,240), Material=Enum.Material.Glass, Transparency=0.3 }, m)
		end
	end

	pitchedPair(m, "Roof", L(0, h+1, 0), w, d+2.6, PITCH, 0.8, roofColor, Enum.Material.Slate, "X")
	P({ Name="Ridge", Size=Vector3.new(1,1,d+3), CFrame=L(0,h+1+peak,0), Color=roofColor, Material=Enum.Material.Slate }, m)
	return m, cf
end

local function chimney(cf, ox, oz, h, lit)
	local m = Instance.new("Model"); m.Name = "Chimney"; m.Parent = Village
	P({ Name="Stack", Size=Vector3.new(2.2,h,2.2), CFrame=cf*CFrame.new(ox,h/2+6,oz), Color=STONED, Material=Enum.Material.Brick }, m)
	if lit then
		local s = P({ Name="Smoke", Size=Vector3.new(1,1,1), Transparency=1, CanCollide=false, CFrame=cf*CFrame.new(ox,h+6.5,oz) }, m)
		local pe = Instance.new("ParticleEmitter")
		pe.Rate=5; pe.Lifetime=NumberRange.new(3,5); pe.Speed=NumberRange.new(2,4)
		pe.Size=NumberSequence.new(1.8); pe.Transparency=NumberSequence.new(0.7)
		pe.Color=ColorSequence.new(Color3.fromRGB(200,200,200)); pe.Parent=s
	end
end

local function signOn(part, text, color)
	local g = Instance.new("SurfaceGui"); g.Face = Enum.NormalId.Front; g.Parent = part
	local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1,1); t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack; t.TextScaled = true
	t.TextColor3 = color or Color3.fromRGB(244,224,168); t.Text = text; t.Parent = g
end

local function lamp(x, z, h)
	local m = Instance.new("Model"); m.Name="Lamp"; m.Parent=Village
	P({ Name="Post", Size=Vector3.new(0.5,h,0.5), CFrame=CFrame.new(x,h/2+1,z), Color=WOODD, Material=Enum.Material.Wood }, m)
	local g = P({ Name="Glow", Size=Vector3.new(1.3,1.6,1.3), CFrame=CFrame.new(x,h+1.4,z), Color=Color3.fromRGB(255,212,140), Material=Enum.Material.Neon }, m)
	local l = Instance.new("PointLight"); l.Color=Color3.fromRGB(255,204,128); l.Range=18; l.Brightness=1.2; l.Parent=g
end

--============================================================ TAVERN
local tav, tcf = house(-50,118,30,24,15,0,Color3.fromRGB(220,202,168),ROOF,"Tavern")
chimney(tcf,11,7,10,true)
signOn(P({ Name="Sign", Size=Vector3.new(9,3.4,0.4), CFrame=tcf*CFrame.new(0,12,-13), Color=WOODD, Material=Enum.Material.WoodPlanks }, tav), "THE ROLLING DICE")
for i = 1, 6 do
	P({ Name="Barrel", Shape=Enum.PartType.Cylinder, Size=Vector3.new(3,2.4,2.4),
		CFrame=tcf*CFrame.new(-18,2,-10+i*3.4)*CFrame.Angles(0,0,math.rad(90)), Color=WOOD, Material=Enum.Material.WoodPlanks }, tav)
end
for _, ox in ipairs({ -11, 11 }) do
	local g = P({ Name="Lantern", Size=Vector3.new(1.1,1.5,1.1), CFrame=tcf*CFrame.new(ox,8.5,-12.5), Color=Color3.fromRGB(255,206,132), Material=Enum.Material.Neon }, tav)
	local l = Instance.new("PointLight"); l.Color=Color3.fromRGB(255,200,124); l.Range=20; l.Brightness=1.6; l.Parent=g
end

--============================================================ BLACKSMITH
local smi, scf = house(50,118,28,24,14,0,Color3.fromRGB(180,170,154),ROOF2,"Blacksmith")
chimney(scf,-10,6,13,true)
smi.Door:Destroy()
P({ Name="ForgeMouth", Size=Vector3.new(12,8,1.4), CFrame=scf*CFrame.new(0,5,-12.3), Color=Color3.fromRGB(28,24,22), Material=Enum.Material.Slate }, smi)
signOn(P({ Name="Sign", Size=Vector3.new(8.5,3.2,0.4), CFrame=scf*CFrame.new(0,11.5,-12.6), Color=WOODD, Material=Enum.Material.WoodPlanks }, smi), "FORGE", Color3.fromRGB(255,178,110))
P({ Name="Forge", Size=Vector3.new(6,3.4,4.5), CFrame=scf*CFrame.new(0,2.8,-6), Color=STONED, Material=Enum.Material.Brick }, smi)
local coals = P({ Name="Coals", Size=Vector3.new(4,0.7,3), CFrame=scf*CFrame.new(0,4.7,-6), Color=Color3.fromRGB(255,124,44), Material=Enum.Material.Neon }, smi)
local fl = Instance.new("PointLight"); fl.Color=Color3.fromRGB(255,146,64); fl.Range=30; fl.Brightness=2.6; fl.Parent=coals
local fp = Instance.new("ParticleEmitter"); fp.Rate=16; fp.Lifetime=NumberRange.new(0.6,1.3)
fp.Speed=NumberRange.new(3,7); fp.Size=NumberSequence.new(0.6); fp.Transparency=NumberSequence.new(0.25)
fp.Color=ColorSequence.new(Color3.fromRGB(255,168,72)); fp.Parent=coals
P({ Name="AnvilBase", Size=Vector3.new(1.8,2,1.8), CFrame=scf*CFrame.new(-7,2.2,-3), Color=WOODD, Material=Enum.Material.Wood }, smi)
P({ Name="Anvil", Size=Vector3.new(1.6,1.1,3.4), CFrame=scf*CFrame.new(-7,3.7,-3), Color=Color3.fromRGB(66,66,72), Material=Enum.Material.Metal }, smi)
for i = 1, 5 do
	P({ Name="RackSword", Size=Vector3.new(0.22,4.4,0.7), CFrame=scf*CFrame.new(8,4,-9+i*1.6)*CFrame.Angles(math.rad(14),0,0),
		Color=Color3.fromRGB(180,184,192), Material=Enum.Material.Metal }, smi)
end

--============================================================ HOUSES
for i, s in ipairs({ {-76,182,22,18,12,10},{-28,196,20,17,11,-6},{20,194,21,18,12,4},
	{68,180,22,18,12,-12},{-92,146,20,17,11,90},{92,148,20,17,11,-90},
	{-64,86,19,16,11,180},{64,86,19,16,11,180} }) do
	local wall = (i%2==0) and Color3.fromRGB(228,216,190) or Color3.fromRGB(208,192,166)
	local _, cf = house(s[1],s[2],s[3],s[4],s[5],s[6], wall, (i%3==0) and ROOF2 or ROOF, "House"..i)
	if i%2==1 then chimney(cf, s[3]*0.3, s[4]*0.25, 8, i%4==1) end
end

--============================================================ MARKET
local function stall(x, z, rot, col, label)
	local m = Instance.new("Model"); m.Name = "Stall_"..label; m.Parent = Village
	local cf = CFrame.new(x,0,z)*CFrame.Angles(0,math.rad(rot),0)
	for _, o in ipairs({ {-5,-3},{5,-3},{-5,3},{5,3} }) do
		P({ Name="Post", Size=Vector3.new(0.5,8,0.5), CFrame=cf*CFrame.new(o[1],4.5,o[2]), Color=WOOD, Material=Enum.Material.Wood }, m)
	end
	P({ Name="Counter", Size=Vector3.new(11,0.6,2.4), CFrame=cf*CFrame.new(0,4,-3), Color=WOOD, Material=Enum.Material.WoodPlanks }, m)
	pitchedPair(m, "Awning", cf*CFrame.new(0,8.8,0), 9, 11.8, 26, 0.3, col, Enum.Material.Fabric, "Z")
	for i = 1, 4 do
		P({ Name="Crate", Size=Vector3.new(2,2,2), CFrame=cf*CFrame.new(-4.4+i*2.3,2,3.4)*CFrame.Angles(0,rng:NextNumber()*3,0),
			Color=WOOD, Material=Enum.Material.WoodPlanks }, m)
	end
	signOn(P({ Name="StallSign", Size=Vector3.new(6.4,1.8,0.3), CFrame=cf*CFrame.new(0,10.4,-2.1), Color=WOODD, Material=Enum.Material.WoodPlanks }, m), label, Color3.fromRGB(248,238,214))
end
stall(-30,160,0,Color3.fromRGB(206,88,80),"PRODUCE")
stall(30,160,0,Color3.fromRGB(78,132,196),"POTIONS")
stall(-30,200,180,Color3.fromRGB(228,182,74),"TRINKETS")
stall(30,200,180,Color3.fromRGB(96,168,112),"SUPPLIES")

--============================================================ WELL
local well = Instance.new("Model"); well.Name="Well"; well.Parent=Village
local WX, WZ = -34, 186
for i = 1, 14 do
	local a = (i/14)*math.pi*2
	P({ Name="Stone", Size=Vector3.new(1.1,2,1.1), CFrame=CFrame.new(WX+math.cos(a)*2.6,1.6,WZ+math.sin(a)*2.6)*CFrame.Angles(0,-a,0),
		Color=STONED, Material=Enum.Material.Cobblestone }, well)
end
P({ Name="Water", Shape=Enum.PartType.Cylinder, Size=Vector3.new(0.3,4.2,4.2), CFrame=CFrame.new(WX,1.5,WZ)*CFrame.Angles(0,0,math.rad(90)),
	Color=Color3.fromRGB(52,96,138), Material=Enum.Material.Glass, Transparency=0.25 }, well)
for _, ox in ipairs({ -2.7, 2.7 }) do
	P({ Name="Post", Size=Vector3.new(0.4,4.2,0.4), CFrame=CFrame.new(WX+ox,4.3,WZ), Color=WOOD, Material=Enum.Material.Wood }, well)
end
pitchedPair(well, "WellRoof", CFrame.new(WX,6.6,WZ), 6.4, 4.6, 34, 0.4, ROOF, Enum.Material.Slate, "X")

--============================================================ ALTAR
local Altar = Instance.new("Model"); Altar.Name="RollAltar"; Altar.Parent=Village
for i = 0, 2 do
	P({ Name="Step"..i, Shape=Enum.PartType.Cylinder, Size=Vector3.new(1.4,26-i*6,26-i*6),
		CFrame=CFrame.new(0,1.6+i*1.3,150)*CFrame.Angles(0,0,math.rad(90)),
		Color=(i==2) and STONE or STONED, Material=Enum.Material.Slate }, Altar)
end
local ped = P({ Name="Pedestal", Size=Vector3.new(4.5,5.5,4.5), CFrame=CFrame.new(0,7.5,150), Color=STONED, Material=Enum.Material.Slate }, Altar)
local cry = P({ Name="Crystal", Size=Vector3.new(2.8,4.6,2.8), CFrame=CFrame.new(0,12.2,150)*CFrame.Angles(0,math.rad(45),0),
	Color=Color3.fromRGB(126,240,255), Material=Enum.Material.Neon }, Altar)
local cl = Instance.new("PointLight"); cl.Color=Color3.fromRGB(126,240,255); cl.Range=26; cl.Brightness=1.6; cl.Parent=cry
Altar.PrimaryPart = ped

--============================================================ SPAWN
-- Plaza top surface is y=1.40; the pad sits ON it at y=1.65. A spawn buried
-- inside geometry gets the character ejected by physics — that bug threw the
-- player clean outside the village gate.
local sp = Instance.new("SpawnLocation")
sp.Name="SpawnLocation"; sp.Size=Vector3.new(13,0.5,13); sp.CFrame=CFrame.new(0,1.65,172)
sp.Anchored=true; sp.Color=Color3.fromRGB(158,150,138); sp.Material=Enum.Material.Cobblestone
sp.TopSurface=Enum.SurfaceType.Smooth; sp.Neutral=true; sp.Parent=Village
for i = 1, 16 do
	local a = (i/16)*math.pi*2
	P({ Name="SpawnInlay", Size=Vector3.new(1.1,0.3,1.1), CanCollide=false, CanQuery=false,
		CFrame=CFrame.new(math.cos(a)*7.4,1.55,172+math.sin(a)*7.4)*CFrame.Angles(0,-a,0),
		Color=Color3.fromRGB(200,190,172), Material=Enum.Material.Slate }, Village)
end
local safe = P({ Name="SafeZone", Size=Vector3.new(240,50,240), CFrame=CFrame.new(0,25,150), Transparency=1, CanCollide=false, CanQuery=false }, Village)
safe:SetAttribute("SafeZone", true); safe:SetAttribute("ZoneId", "Village")

--============================================================ WALLS
local Wall = Instance.new("Folder"); Wall.Name="Wall"; Wall.Parent=Village
local function run(x1,z1,x2,z2)
	local dx,dz = x2-x1, z2-z1
	local len = math.sqrt(dx*dx+dz*dz)
	P({ Name="Wall", Size=Vector3.new(3,14,len), CFrame=CFrame.new((x1+x2)/2,7,(z1+z2)/2)*CFrame.Angles(0,math.atan2(dx,dz),0),
		Color=STONED, Material=Enum.Material.Cobblestone }, Wall)
end
run(-118,58,-118,240); run(118,58,118,240); run(-118,240,118,240); run(-118,58,-18,58); run(18,58,118,58)
for _, gx in ipairs({ -18, 18 }) do
	P({ Name="GateTower", Size=Vector3.new(10,24,10), CFrame=CFrame.new(gx,12,58), Color=STONE, Material=Enum.Material.Cobblestone }, Wall)
	pitchedPair(Wall, "TowerRoof", CFrame.new(gx,24.6,58), 9, 9, 40, 0.6, ROOF2, Enum.Material.Slate, "X")
end
P({ Name="GateArch", Size=Vector3.new(36,3.5,7), CFrame=CFrame.new(0,20,58), Color=STONE, Material=Enum.Material.Cobblestone }, Wall)

--============================================================ DRESSING
for i = 1, 44 do
	P({ Name="Road", Size=Vector3.new(18,0.5,8), CFrame=CFrame.new(rng:NextNumber(-1.5,1.5),1.0,236-i*4.4),
		Color=Color3.fromRGB(136,128,116), Material=Enum.Material.Cobblestone }, Ground)
end
P({ Name="Plaza", Shape=Enum.PartType.Cylinder, Size=Vector3.new(0.6,80,80), CFrame=CFrame.new(0,1.1,160)*CFrame.Angles(0,0,math.rad(90)),
	Color=Color3.fromRGB(142,134,122), Material=Enum.Material.Cobblestone }, Ground)
for _, p in ipairs({ {-22,132},{22,132},{-22,186},{22,186},{-46,208},{46,208},{-14,72},{14,72} }) do lamp(p[1],p[2],8) end
for i = 1, 10 do P({ Name="Fence", Size=Vector3.new(6,3,0.4), CFrame=CFrame.new(-100+i*0.2,2.5,214+i*2.4), Color=WOOD, Material=Enum.Material.Wood }, Village) end
for i = 1, 4 do
	P({ Name="Hay", Shape=Enum.PartType.Cylinder, Size=Vector3.new(3.4,3,3), CFrame=CFrame.new(88+rng:NextNumber(-4,4),2.5,206+i*4)*CFrame.Angles(0,0,math.rad(90)),
		Color=Color3.fromRGB(212,182,96), Material=Enum.Material.Grass }, Village)
end
local cart = Instance.new("Model"); cart.Name="Cart"; cart.Parent=Village
P({ Name="Bed", Size=Vector3.new(7,1,4), CFrame=CFrame.new(-60,3,152), Color=WOOD, Material=Enum.Material.WoodPlanks }, cart)
for _, o in ipairs({ {-2.4,-2.2},{-2.4,2.2} }) do
	P({ Name="Wheel", Shape=Enum.PartType.Cylinder, Size=Vector3.new(0.5,3.4,3.4),
		CFrame=CFrame.new(-60+o[1],2,152+o[2])*CFrame.Angles(0,math.rad(90),math.rad(90)), Color=WOODD, Material=Enum.Material.Wood }, cart)
end
for _, t in ipairs({ {-100,196},{100,196},{-100,110},{100,110} }) do
	local m = Instance.new("Model"); m.Name="VillageTree"; m.Parent=Village
	P({ Name="Trunk", Size=Vector3.new(2.4,12,2.4), CFrame=CFrame.new(t[1],7,t[2]), Color=WOODD, Material=Enum.Material.Wood }, m)
	for i = 1, 3 do
		P({ Name="Canopy", Shape=Enum.PartType.Ball, Size=Vector3.new(1,1,1)*rng:NextNumber(8,12),
			CFrame=CFrame.new(t[1]+rng:NextNumber(-3,3),13+rng:NextNumber(0,3),t[2]+rng:NextNumber(-3,3)),
			Color=Color3.fromRGB(76,150,80), Material=Enum.Material.Grass }, m)
	end
end

--============================================================ ZONE 1
local Scenery = Instance.new("Folder"); Scenery.Name="Scenery"; Scenery.Parent=Zone1
local Spawns = Instance.new("Folder"); Spawns.Name="EnemySpawns"; Spawns.Parent=Zone1
for i = 1, 52 do
	local x, z = rng:NextNumber(-290,290), rng:NextNumber(-350,40)
	if math.abs(x) > 28 or z < -70 then
		local m = Instance.new("Model"); m.Name="Tree"; m.Parent=Scenery
		local s = rng:NextNumber(0.7,1.4); local h = 10*s
		P({ Name="Trunk", Size=Vector3.new(2*s,h,2*s), CFrame=CFrame.new(x,h/2,z), Color=WOODD, Material=Enum.Material.Wood }, m)
		local sh = { Color3.fromRGB(72,148,76), Color3.fromRGB(86,166,88), Color3.fromRGB(62,132,68) }
		for j = 1, 3 do
			P({ Name="Canopy", Shape=Enum.PartType.Ball, Size=Vector3.new(1,1,1)*rng:NextNumber(6,10.5)*s,
				CFrame=CFrame.new(x+rng:NextNumber(-3,3)*s, h+rng:NextNumber(0,2.5)*s, z+rng:NextNumber(-3,3)*s),
				Color=sh[j], Material=Enum.Material.Grass }, m)
		end
	end
end
for i = 1, 30 do
	local s = rng:NextNumber(2.5,7)
	P({ Name="Rock", Shape=Enum.PartType.Ball, Size=Vector3.new(s,s*0.75,s*1.1),
		CFrame=CFrame.new(rng:NextNumber(-290,290), s*0.22, rng:NextNumber(-350,30))*CFrame.Angles(0,rng:NextNumber()*6.28,0),
		Color=STONE, Material=Enum.Material.Rock }, Scenery)
end

-- Every marker is outside the walls, so the village stays a true safe zone.
for i, s in ipairs({ {"Slime",-70,-10},{"Slime",70,-10},{"Slime",0,-55},{"Slime",-140,-40},
	{"Goblin",-115,-115},{"Goblin",115,-115},{"Goblin",0,-150},
	{"Wolf",-200,-75},{"Wolf",200,-75},{"Wolf",-45,-215},
	{"GoblinWarrior",130,-225},{"GoblinWarrior",-130,-230},{"EliteGoblin",0,-270} }) do
	local mk = P({ Name=string.format("Spawn_%s_%d", s[1], i), Size=Vector3.new(4,0.2,4),
		CFrame=CFrame.new(s[2],0.2,s[3]), Transparency=1, CanCollide=false }, Spawns)
	mk:SetAttribute("EnemyId", s[1]); mk:SetAttribute("Radius", 24); mk:SetAttribute("MaxAlive", 3)
end

--============================================================ ARENA
local Arena = Instance.new("Folder"); Arena.Name="BossArena"; Arena.Parent=Zone1
P({ Name="ArenaFloor", Shape=Enum.PartType.Cylinder, Size=Vector3.new(2,150,150),
	CFrame=CFrame.new(0,0.9,-430)*CFrame.Angles(0,0,math.rad(90)), Color=Color3.fromRGB(118,108,100), Material=Enum.Material.Ground }, Arena)
for i = 1, 18 do
	local a = (i/18)*math.pi*2
	P({ Name="Pillar", Size=Vector3.new(6,rng:NextNumber(16,24),6), CFrame=CFrame.new(math.cos(a)*70,10,-430+math.sin(a)*70),
		Color=STONED, Material=Enum.Material.Slate }, Arena)
end
local bm = P({ Name="BossSpawn", Size=Vector3.new(6,0.2,6), CFrame=CFrame.new(0,2,-430), Transparency=1, CanCollide=false }, Arena)
bm:SetAttribute("BossId", "GoblinKing")
local gate = P({ Name="ZoneGate", Size=Vector3.new(38,26,3), CFrame=CFrame.new(0,13,-340),
	Color=Color3.fromRGB(96,132,255), Material=Enum.Material.ForceField, Transparency=0.55 }, Arena)
gate:SetAttribute("RequiresPower", 1200); gate:SetAttribute("GateId", "GoblinKingArena")

--============================================================ LIGHTING
Lighting.Ambient = Color3.fromRGB(88,92,104)
Lighting.OutdoorAmbient = Color3.fromRGB(122,128,142)
Lighting.Brightness = 1.9
Lighting.ClockTime = 15.4
Lighting.FogEnd = 820
Lighting.FogStart = 340
Lighting.FogColor = Color3.fromRGB(180,200,210)
Lighting.EnvironmentDiffuseScale = 0.45
Lighting.ExposureCompensation = -0.15

local n = 0
for _ in ipairs(World:GetDescendants()) do n += 1 end
print(string.format("[BuildWorld] %d instances | village + Verdant Fields + boss arena", n))
