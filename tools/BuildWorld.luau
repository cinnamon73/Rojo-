--[[
	================================================================
	LEGACY — DO NOT RUN AGAINST THE CURRENT PLACE
	================================================================

	This builds the ORIGINAL axial village from an early pass. It is kept
	only as a record of how the first world was generated.

	The world has since been rebuilt entirely and is now ~14,000 parts:
	castle, eleven buildings, an organic path network, market, yards,
	outbuildings, foliage, a towered curtain wall and dusk lighting. None
	of that is in this file, and running it would wreck the current place.

	Workspace geometry now lives in the committed place file. See README,
	"Saving the world".
	================================================================
]]

--[[
	BuildWorld — regenerates the entire world from scratch.

	============================================================================
	HOW TO RUN
	Paste this whole file into the Roblox Studio Command Bar (View -> Command
	Bar) and press Enter, in EDIT MODE. It wipes Workspace.World and rebuilds.
	============================================================================

	Why this file exists: Workspace is not managed by Rojo and `.rbxlx` is
	gitignored, so the map would otherwise live only inside one person's place
	file — unreproducible, unshareable, and lost if that file breaks.

	It is idempotent: running it twice produces one world, not two.

	LAYOUT
	  Village      z  52 .. 252   walled safe hub, spawn, no enemies
	  Starter zone z  30 .. -360  enclosed hunting grounds, all enemy markers
	  Boss arena   z -400         Goblin King, behind a 1200-Power gate

	GAMEPLAY CONTRACT — do not rename or remove these, services read them:
	  SpawnLocation                    player spawn
	  SafeZone_Volume                  attrs SafeZone, ZoneId
	  EnemySpawn_<Id>_<n>              attrs EnemyId, Radius, MaxAlive
	  BossSpawn                        attr  BossId
	  ZoneGate                         attrs RequiresPower, GateId
	EnemyService walks Workspace looking for EnemyId attributes; drop those and
	combat silently stops working with no error.

	============================================================================
	GEOMETRY NOTES — every one of these cost a visible bug
	============================================================================

	PITCHED PAIRS (roofs, awnings). For a span S at pitch P, each slab must be
	(S/2)/cos(P) long, centred S/4 across and (S/4)*tan(P) up, rotated -sign*P.
	A slab longer than the offset implies makes the halves cross into an X.
	Rotating +sign lifts the outer edge and splays them open like a book.

	ARCHES. x = sin(a)*r, y = springY + cos(a)*r, a sweeping -pi/2..pi/2. That
	puts the crown at springY+r and the springing at springY on both jambs.
	SUBTRACTING cos inverts the whole curve into a bowl.

	FOLIAGE SCALE. Canopies above ~10 studs at any real density merge into one
	opaque mass with no walkable space. Dense at eye level means trunks and
	undergrowth you weave between, not foliage in your face.

	STACKING ORDER. A part that should be visible must be the highest surface
	at that spot. A slime pool at y=1.1 under a 4-stud basin block centred at
	y=0.2 is completely hidden; a spawn pad below the plaza surface ejects the
	character by physics.

	ALL OF THESE LOOKED FINE FROM ABOVE. Screenshot at player eye height.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

--============================================================ TEARDOWN
-- Terrain inherits BasePart, so it must be excluded explicitly or Destroy throws.
local old = Workspace:FindFirstChild("World"); if old then old:Destroy() end
local enemies = Workspace:FindFirstChild("Enemies"); if enemies then enemies:Destroy() end
for _, d in ipairs(Workspace:GetChildren()) do
	if not d:IsA("Terrain") and not d:IsA("Camera") then
		if d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder") then d:Destroy() end
	end
end

local rng = Random.new(4242)

local World = Instance.new("Folder"); World.Name = "World"; World.Parent = Workspace
local Terra = Instance.new("Folder"); Terra.Name = "Terrain"; Terra.Parent = World
local Village = Instance.new("Folder"); Village.Name = "Village"; Village.Parent = World
local Fort = Instance.new("Folder"); Fort.Name = "Fortifications"; Fort.Parent = Village
local Buildings = Instance.new("Folder"); Buildings.Name = "Buildings"; Buildings.Parent = Village
local Paths = Instance.new("Folder"); Paths.Name = "Pathways"; Paths.Parent = Village
local Lights = Instance.new("Folder"); Lights.Name = "Lighting"; Lights.Parent = Village
local Props = Instance.new("Folder"); Props.Name = "Props"; Props.Parent = Village

local Zone = Instance.new("Folder"); Zone.Name = "StarterZone"; Zone.Parent = World
local Cliffs = Instance.new("Folder"); Cliffs.Name = "PerimeterCliffs"; Cliffs.Parent = Zone
local Flora = Instance.new("Folder"); Flora.Name = "Vegetation"; Flora.Parent = Zone
local Slime = Instance.new("Folder"); Slime.Name = "SlimePitBiome"; Slime.Parent = Zone
local Camps = Instance.new("Folder"); Camps.Name = "GoblinTerritory"; Camps.Parent = Zone
local Story = Instance.new("Folder"); Story.Name = "EnvironmentDetail"; Story.Parent = Zone
local Spawns = Instance.new("Folder"); Spawns.Name = "EnemySpawns"; Spawns.Parent = Zone
local Trails = Instance.new("Folder"); Trails.Name = "HuntingPaths"; Trails.Parent = Zone
local Arena = Instance.new("Folder"); Arena.Name = "BossArena"; Arena.Parent = Zone

--============================================================ PRIMITIVES
-- Everything goes through these two so Anchored and CastShadow are never missed.
local function P(name, size, cf, color, mat, parent, extra)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = mat
	p.Anchored = true; p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then for k, v in pairs(extra) do p[k] = v end end
	p.Parent = parent; return p
end

local function WG(name, size, cf, color, mat, parent)
	local p = Instance.new("WedgePart")
	p.Name = name; p.Size = size; p.CFrame = cf; p.Color = color; p.Material = mat
	p.Anchored = true; p.CastShadow = true; p.Parent = parent; return p
end

--[[ The correct pitched pair. See the geometry notes at the top. ]]
local function pitchedPair(parent, name, cf, span, depth, pitch, thick, color, mat, axis)
	local rad = math.rad(pitch)
	local slab = (span / 2) / math.cos(rad) + 0.8
	local ox, oy = span / 4, (span / 4) * math.tan(rad)
	for _, s in ipairs({ -1, 1 }) do
		if axis == "Z" then
			P(name, Vector3.new(depth, thick, slab),
				cf * CFrame.new(0, oy, s * ox) * CFrame.Angles(math.rad(s * pitch), 0, 0), color, mat, parent)
		else
			P(name, Vector3.new(slab, thick, depth),
				cf * CFrame.new(s * ox, oy, 0) * CFrame.Angles(0, 0, math.rad(-s * pitch)), color, mat, parent)
		end
	end
end

local COBBLE = Color3.fromRGB(126,124,120)
local COBBLE_D = Color3.fromRGB(96,94,92)
local STONE_L = Color3.fromRGB(158,155,148)
local STONE_F = Color3.fromRGB(112,110,106)
local PLASTER = Color3.fromRGB(224,212,188)
local PLASTER2 = Color3.fromRGB(206,190,164)
local TIMBER = Color3.fromRGB(78,54,34)
local WOOD = Color3.fromRGB(126,90,56)
local ROOF_A = Color3.fromRGB(122,58,48)
local ROOF_B = Color3.fromRGB(84,66,56)
local GLASSC = Color3.fromRGB(176,206,222)
local GRASS = Color3.fromRGB(94,142,78)
local MUD = Color3.fromRGB(104,82,58)
local ROCK = Color3.fromRGB(104,100,96)
local ROCK_D = Color3.fromRGB(78,76,74)
local EARTH = Color3.fromRGB(94,72,50)
local EARTH_D = Color3.fromRGB(70,54,38)
local BARK = Color3.fromRGB(72,50,34)
local BARK_D = Color3.fromRGB(54,38,26)
local MOSS = Color3.fromRGB(78,110,58)
local LEAVES = { Color3.fromRGB(54,102,52), Color3.fromRGB(42,84,44), Color3.fromRGB(68,120,60), Color3.fromRGB(48,92,46) }

--============================================================ TERRAIN
P("Ground_Wilds", Vector3.new(900,6,1200), CFrame.new(0,-3,-200), GRASS, Enum.Material.Grass, Terra)
P("Ground_VillagePlateau", Vector3.new(280,8,240), CFrame.new(0,-1,152), MUD, Enum.Material.Ground, Terra)

--============================================================ DEFENSIVE WALL
local WX, WZ_S, WZ_N = 128, 52, 252
local WALL_H = 22

local function crenellate(x1,z1,x2,z2,y)
	local dx,dz = x2-x1, z2-z1
	local len = math.sqrt(dx*dx + dz*dz)
	local steps = math.max(math.floor(len/6), 1)
	local ang = math.atan2(dx,dz)
	for i = 0, steps do
		if i % 2 == 0 then
			local t = i/steps
			P("Battlement_Merlon", Vector3.new(4.4,3.6,4.4),
				CFrame.new(x1+dx*t, y+1.8, z1+dz*t) * CFrame.Angles(0,ang,0), STONE_L, Enum.Material.Cobblestone, Fort)
		end
	end
end

--[[
	Layered curtain: foundation, curtain, capstone, walkway — plus buttresses.

	Each run must be ordered so its local +X points OUT of the village, since
	that is the side the buttresses are placed on.
]]
local function curtain(name,x1,z1,x2,z2)
	local dx,dz = x2-x1, z2-z1
	local len = math.sqrt(dx*dx + dz*dz)
	local ang = math.atan2(dx,dz)
	local base = CFrame.new((x1+x2)/2, 0, (z1+z2)/2) * CFrame.Angles(0,ang,0)

	P(name.."_Foundation", Vector3.new(9,5,len), base*CFrame.new(0,2.5,0), COBBLE_D, Enum.Material.Cobblestone, Fort)
	P(name.."_Curtain", Vector3.new(6.5,WALL_H,len), base*CFrame.new(0,WALL_H/2+5,0), COBBLE, Enum.Material.Cobblestone, Fort)
	P(name.."_Capstone", Vector3.new(8,1.6,len), base*CFrame.new(0,WALL_H+5.8,0), STONE_L, Enum.Material.Slate, Fort)
	P(name.."_Walkway", Vector3.new(5,0.6,len), base*CFrame.new(0,WALL_H+6.6,0), COBBLE_D, Enum.Material.Cobblestone, Fort)

	local count = math.max(math.floor(len/34), 1)
	for i = 0, count do
		local t = i/count
		local bcf = CFrame.new(x1+dx*t, 0, z1+dz*t) * CFrame.Angles(0,ang,0)
		P(name.."_Buttress_Pier", Vector3.new(5,15,6), bcf*CFrame.new(5.5,7.5,0), COBBLE_D, Enum.Material.Cobblestone, Fort)
		WG(name.."_Buttress_Shoulder", Vector3.new(6,9,5),
			bcf*CFrame.new(5.5,19.5,0)*CFrame.Angles(0,math.rad(90),0), COBBLE_D, Enum.Material.Cobblestone, Fort)
		P(name.."_Buttress_Cap", Vector3.new(5.6,1,6.6), bcf*CFrame.new(5.5,15.5,0), STONE_L, Enum.Material.Slate, Fort)
	end
	crenellate(x1,z1,x2,z2,WALL_H+7)
end

curtain("Wall_West", -WX, WZ_N, -WX, WZ_S)
curtain("Wall_East", WX, WZ_S, WX, WZ_N)
curtain("Wall_North", WX, WZ_N, -WX, WZ_N)
curtain("Wall_SouthWest", -WX, WZ_S, -24, WZ_S)
curtain("Wall_SouthEast", 24, WZ_S, WX, WZ_S)

--============================================================ GATEHOUSE
local Gate = Instance.new("Model"); Gate.Name = "Gatehouse"; Gate.Parent = Fort
for _, sx in ipairs({ -1, 1 }) do
	local gx = sx*30
	P("Gatehouse_TowerBase", Vector3.new(23,7,23), CFrame.new(gx,3.5,WZ_S), COBBLE_D, Enum.Material.Cobblestone, Gate)
	P("Gatehouse_Tower", Vector3.new(20,38,20), CFrame.new(gx,19,WZ_S), COBBLE, Enum.Material.Cobblestone, Gate)
	P("Gatehouse_TowerBand", Vector3.new(21.5,1.6,21.5), CFrame.new(gx,26,WZ_S), STONE_L, Enum.Material.Slate, Gate)
	P("Gatehouse_TowerCap", Vector3.new(23,1.8,23), CFrame.new(gx,38.5,WZ_S), STONE_L, Enum.Material.Slate, Gate)
	for i = 0, 7 do
		local a = (i/8)*math.pi*2
		P("Gatehouse_Merlon", Vector3.new(4,4,4), CFrame.new(gx+math.cos(a)*8.5,41.2,WZ_S+math.sin(a)*8.5), STONE_L, Enum.Material.Cobblestone, Gate)
	end
	for i = 1, 3 do
		P("Gatehouse_ArrowSlit", Vector3.new(1.2,5,2), CFrame.new(gx+sx*10.2,14+i*6,WZ_S-3), Color3.fromRGB(24,22,20), Enum.Material.Slate, Gate)
	end
end

-- Semicircular arch. ADDING cos is what puts the crown at the top.
local ARCH_R, SPRING_Y, ARCH_N = 21, 12, 15
for i = 0, ARCH_N do
	local a = (-math.pi/2) + (i/ARCH_N)*math.pi
	P("Gatehouse_Voussoir", Vector3.new(4.6,5,10),
		CFrame.new(math.sin(a)*ARCH_R, SPRING_Y+math.cos(a)*ARCH_R, WZ_S)*CFrame.Angles(0,0,-a),
		(i == math.floor(ARCH_N/2)) and STONE_L or COBBLE, Enum.Material.Cobblestone, Gate)
end
P("Gatehouse_Keystone", Vector3.new(5.6,6.5,11), CFrame.new(0,SPRING_Y+ARCH_R+0.6,WZ_S), STONE_L, Enum.Material.Cobblestone, Gate)
for _, sx in ipairs({ -1, 1 }) do
	P("Gatehouse_Jamb", Vector3.new(6,SPRING_Y,10), CFrame.new(sx*(ARCH_R+1),SPRING_Y/2,WZ_S), COBBLE, Enum.Material.Cobblestone, Gate)
end
P("Gatehouse_Lintel", Vector3.new(60,5,10), CFrame.new(0,33.5,WZ_S), COBBLE, Enum.Material.Cobblestone, Gate)
P("Gatehouse_Battlement", Vector3.new(62,2,11), CFrame.new(0,36.5,WZ_S), STONE_L, Enum.Material.Slate, Gate)
for i = -4, 4 do
	P("Gatehouse_Merlon", Vector3.new(4.4,3.6,4.4), CFrame.new(i*6.4,39,WZ_S), STONE_L, Enum.Material.Cobblestone, Gate)
end
for i = -5, 5 do
	P("Portcullis_Bar", Vector3.new(0.6,7,0.6), CFrame.new(i*3.6,SPRING_Y+ARCH_R-3,WZ_S-4.5), Color3.fromRGB(58,52,48), Enum.Material.Metal, Gate)
end
P("Portcullis_Beam", Vector3.new(40,1.2,1.2), CFrame.new(0,SPRING_Y+ARCH_R-6.6,WZ_S-4.5), Color3.fromRGB(58,52,48), Enum.Material.Metal, Gate)

--============================================================ TOWN PLAN
--[[
	Axial plan, every position measured off the gatehouse rather than eyeballed.

	  MAIN_X   = 0     the gate sits on this axis, so the road runs dead straight
	                   from the arch to the apothecary that terminates it
	  CROSS_Z  = 148   east-west street; tavern and forge face onto it
	  SQ       = 48    half-extent of the square at the crossing
	  ROW_X    = +/-58 the two house terraces, every door facing the road

	Doors are on a building's local -Z face, so rotation follows from position:
	rot 0 faces south, 90 faces west, -90 faces east, 180 faces north.
]]
local MAIN_X, CROSS_Z = 0, 148
local ROAD_W, CROSS_W = 26, 22
local SQ = 48
local ROW_X = 58
local GATE_Z, NORTH_Z = 52, 232

--============================================================ PAVING
local ROAD_T = { Color3.fromRGB(138,134,126), Color3.fromRGB(126,122,114), Color3.fromRGB(148,142,130) }
local SQUARE_T = { Color3.fromRGB(152,146,134), Color3.fromRGB(136,130,120), Color3.fromRGB(160,152,138), Color3.fromRGB(126,110,94) }
local FOOT_T = { Color3.fromRGB(118,110,98), Color3.fromRGB(132,124,110) }

--[[ Grid-aligned with no rotation jitter: roads should read as laid, not scattered. ]]
local function pave(x1,z1,x2,z2,width,palette,label)
	local horizontal = math.abs(x2-x1) > math.abs(z2-z1)
	local a1,a2 = (horizontal and x1 or z1), (horizontal and x2 or z2)
	if a1 > a2 then a1,a2 = a2,a1 end
	local fixed = horizontal and z1 or x1
	local cols = math.floor(width/4.2)
	for a = a1, a2, 4.2 do
		for c = 0, cols do
			local off = (c-cols/2)*4.2
			P("PathTile_"..label, Vector3.new(4,0.5,4),
				CFrame.new(horizontal and a or (fixed+off), 3.25, horizontal and (fixed+off) or a),
				palette[rng:NextInteger(1,#palette)],
				(rng:NextNumber() < 0.3) and Enum.Material.Slate or Enum.Material.Cobblestone, Paths)
		end
	end
end

pave(MAIN_X,GATE_Z,MAIN_X,NORTH_Z,ROAD_W,ROAD_T,"MainRoad")
pave(-112,CROSS_Z,112,CROSS_Z,CROSS_W,ROAD_T,"CrossStreet")

-- Square: flagstone field with a darker border course framing it.
for x = -SQ, SQ, 4.2 do
	for z = CROSS_Z-SQ, CROSS_Z+SQ, 4.2 do
		local edge = (math.abs(x) > SQ-5) or (math.abs(z-CROSS_Z) > SQ-5)
		P("PlazaTile", Vector3.new(4,0.5,4), CFrame.new(x,3.3,z),
			edge and Color3.fromRGB(104,98,90) or SQUARE_T[rng:NextInteger(1,#SQUARE_T)],
			edge and Enum.Material.Slate or Enum.Material.Cobblestone, Paths)
	end
end
for i = 1, 4 do
	local a = (i/4)*math.pi*2
	P("Plaza_CompassRay", Vector3.new(3,0.55,16),
		CFrame.new(MAIN_X+math.cos(a)*11,3.4,CROSS_Z+math.sin(a)*11)*CFrame.Angles(0,-a,0),
		Color3.fromRGB(92,86,80), Enum.Material.Slate, Paths)
end
P("Plaza_CompassHub", Vector3.new(9,0.6,9), CFrame.new(MAIN_X,3.42,CROSS_Z), Color3.fromRGB(168,160,146), Enum.Material.Slate, Paths)

--[[
	Footpath: a straight spur from a door out to the road edge. Narrower and
	darker than the carriageway so the hierarchy reads road > footpath.
]]
local footpathCount = 0
local function footpath(doorPos, toward)
	local x1, x2 = doorPos.X, toward
	local dir = (x2 > x1) and 1 or -1
	for i = 0, math.floor(math.abs(x2-x1)/3.6) do
		for c = -1, 1 do
			P("Footpath_Tile", Vector3.new(3.4,0.5,3.4),
				CFrame.new(x1+dir*i*3.6, 3.28, doorPos.Z+c*3.6),
				FOOT_T[rng:NextInteger(1,#FOOT_T)], Enum.Material.Cobblestone, Paths)
		end
	end
	footpathCount += 1
end

--============================================================ BUILDINGS
--[[
	Depth comes from LAYERING, not one box: stone plinth, wall panels inset
	behind proud corner pillars, windows recessed through reveal/frame/glass/
	sill, doorways set back under a stone surround, roofs overhanging on fascia.
]]
local function roofOver(parent, base, span, depth, pitch, color, overhang)
	local rad = math.rad(pitch)
	local slab = (span/2)/math.cos(rad) + (overhang or 3)
	local ox, oy = span/4, (span/4)*math.tan(rad)
	for _, s in ipairs({ -1, 1 }) do
		P("Roof_Slope", Vector3.new(slab,1.1,depth), base*CFrame.new(s*ox,oy,0)*CFrame.Angles(0,0,math.rad(-s*pitch)), color, Enum.Material.Slate, parent)
		for _, sz in ipairs({ -1, 1 }) do
			P("Roof_Fascia", Vector3.new(slab,0.5,0.8), base*CFrame.new(s*ox,oy-0.6,sz*depth/2)*CFrame.Angles(0,0,math.rad(-s*pitch)), TIMBER, Enum.Material.Wood, parent)
		end
	end
	P("Roof_RidgeBeam", Vector3.new(1.4,1.4,depth+1), base*CFrame.new(0,(span/2)*math.tan(rad),0), color, Enum.Material.Slate, parent)
end

local function building(name,x,z,w,d,h,rot,wallCol,roofCol)
	local m = Instance.new("Model"); m.Name = name; m.Parent = Buildings
	local cf = CFrame.new(x,0,z)*CFrame.Angles(0,math.rad(rot),0)
	local function L(a,b,c) return cf*CFrame.new(a,b,c) end

	P("Foundation_Plinth", Vector3.new(w+3,3,d+3), L(0,1.5,0), STONE_F, Enum.Material.Cobblestone, m)
	P("Foundation_Course", Vector3.new(w+1.6,2.2,d+1.6), L(0,4,0), STONE_F, Enum.Material.Cobblestone, m)
	P("Floor", Vector3.new(w,0.6,d), L(0,5.3,0), Color3.fromRGB(88,62,40), Enum.Material.WoodPlanks, m)

	local inset = 0.9
	P("WallPanel_Front", Vector3.new(w-2.4,h,1.2), L(0,h/2+5,-(d/2-inset)), wallCol, Enum.Material.Concrete, m)
	P("WallPanel_Back", Vector3.new(w-2.4,h,1.2), L(0,h/2+5,(d/2-inset)), wallCol, Enum.Material.Concrete, m)
	P("WallPanel_Left", Vector3.new(1.2,h,d-2.4), L(-(w/2-inset),h/2+5,0), wallCol, Enum.Material.Concrete, m)
	P("WallPanel_Right", Vector3.new(1.2,h,d-2.4), L((w/2-inset),h/2+5,0), wallCol, Enum.Material.Concrete, m)

	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			P("SupportPillar", Vector3.new(2.4,h+1,2.4), L(sx*(w/2-0.6),h/2+5.2,sz*(d/2-0.6)), TIMBER, Enum.Material.Wood, m)
			P("SupportPillar_Cap", Vector3.new(3,0.8,3), L(sx*(w/2-0.6),h+5.9,sz*(d/2-0.6)), TIMBER, Enum.Material.Wood, m)
		end
	end
	for _, sz in ipairs({ -1, 1 }) do
		P("Beam_Header", Vector3.new(w+0.6,1,1.4), L(0,h+5.2,sz*(d/2-inset)), TIMBER, Enum.Material.Wood, m)
	end
	P("Beam_Sill", Vector3.new(w-2,0.8,1.5), L(0,h*0.44+5,-(d/2-inset)), TIMBER, Enum.Material.Wood, m)

	local function window(ox,oy,face)
		local dz = (face == "F") and -(d/2-inset) or (d/2-inset)
		local sgn = (face == "F") and -1 or 1
		P("Window_Reveal", Vector3.new(3.6,3.6,1.9), L(ox,oy,dz), Color3.fromRGB(38,32,28), Enum.Material.Slate, m)
		P("Window_Glass", Vector3.new(3,3,0.3), L(ox,oy,dz+sgn*0.15), GLASSC, Enum.Material.Glass, m, { Transparency = 0.42 })
		for _, sx in ipairs({ -1, 1 }) do
			P("Window_FrameV", Vector3.new(0.45,4.2,1.1), L(ox+sx*1.85,oy,dz+sgn*0.6), TIMBER, Enum.Material.Wood, m)
		end
		P("Window_FrameH", Vector3.new(4.2,0.45,1.1), L(ox,oy+1.85,dz+sgn*0.6), TIMBER, Enum.Material.Wood, m)
		P("Window_Sill", Vector3.new(4.6,0.5,1.9), L(ox,oy-2,dz+sgn*0.5), STONE_F, Enum.Material.Slate, m)
		P("Window_Mullion", Vector3.new(0.3,3.4,0.4), L(ox,oy,dz+sgn*0.35), TIMBER, Enum.Material.Wood, m)
	end
	local wy = h*0.66+5
	window(-w*0.28,wy,"F"); window(w*0.28,wy,"F")
	window(-w*0.28,wy,"B"); window(w*0.28,wy,"B")

	P("Door_Recess", Vector3.new(6,7.4,2), L(0,8.7,-(d/2-inset)), Color3.fromRGB(32,26,22), Enum.Material.Slate, m)
	P("Door_Panel", Vector3.new(5,6.8,0.5), L(0,8.5,-(d/2-inset)-0.7), Color3.fromRGB(72,48,30), Enum.Material.WoodPlanks, m)
	P("Door_Surround", Vector3.new(7.4,0.9,2.4), L(0,12.7,-(d/2-inset)-0.3), STONE_F, Enum.Material.Cobblestone, m)
	for _, sx in ipairs({ -1, 1 }) do
		P("Door_Jamb", Vector3.new(0.9,8,2.4), L(sx*3.3,8.4,-(d/2-inset)-0.3), STONE_F, Enum.Material.Cobblestone, m)
	end
	P("Door_Hood", Vector3.new(9,0.7,3.4), L(0,13.6,-(d/2)-1.6), ROOF_A, Enum.Material.Slate, m)
	P("Door_Handle", Vector3.new(0.5,0.5,0.5), L(1.6,8.4,-(d/2-inset)-1.1), Color3.fromRGB(180,150,80), Enum.Material.Metal, m)
	-- Doorstep, so a footpath arrives at something rather than stopping at a wall.
	P("Door_Step", Vector3.new(8,1.4,3.4), L(0,5.2,-(d/2)-1.4), STONE_F, Enum.Material.Cobblestone, m)
	P("Door_StepLower", Vector3.new(9,1.4,2.6), L(0,3.9,-(d/2)-3.2), STONE_F, Enum.Material.Cobblestone, m)

	local peak = (w/2)*math.tan(math.rad(36))
	for _, sz in ipairs({ -1, 1 }) do
		for step = 1, 6 do
			local frac = step/6
			P("Gable_Infill", Vector3.new(w*(1-frac)+1, peak/6+0.15, 1.2),
				L(0, h+5+peak*(frac-1/6)+peak/12, sz*(d/2-inset)), wallCol, Enum.Material.Concrete, m)
		end
	end
	roofOver(m, L(0,h+5,0), w+3, d+5, 36, roofCol, 3.4)

	-- World position just outside the front door, so footpaths can be routed
	-- to it without re-deriving the rotation at every call site.
	local doorWorld = (cf * CFrame.new(0,0,-(d/2)-4)).Position
	return m, cf, doorWorld
end

local function chimney(cf,ox,oz,h,smoke)
	local m = Instance.new("Model"); m.Name = "Chimney"; m.Parent = Buildings
	P("Chimney_Stack", Vector3.new(3,h,3), cf*CFrame.new(ox,h/2+10,oz), STONE_F, Enum.Material.Brick, m)
	P("Chimney_Crown", Vector3.new(3.8,1,3.8), cf*CFrame.new(ox,h+10.5,oz), Color3.fromRGB(92,90,86), Enum.Material.Slate, m)
	if smoke then
		local s = P("Chimney_SmokeEmitter", Vector3.new(1,1,1), cf*CFrame.new(ox,h+11.5,oz), Color3.new(1,1,1), Enum.Material.SmoothPlastic, m,
			{ Transparency = 1, CanCollide = false, CastShadow = false })
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 6; pe.Lifetime = NumberRange.new(3.5,6); pe.Speed = NumberRange.new(2.5,4.5)
		pe.Size = NumberSequence.new(2.2); pe.Transparency = NumberSequence.new(0.72)
		pe.Color = ColorSequence.new(Color3.fromRGB(196,196,196)); pe.Parent = s
	end
end

local function sign(parent,cf,text,color)
	local b = P("Sign_Board", Vector3.new(11,3.6,0.5), cf, Color3.fromRGB(64,44,28), Enum.Material.WoodPlanks, parent)
	for _, sx in ipairs({ -1, 1 }) do
		P("Sign_Bracket", Vector3.new(0.5,2.4,0.5), cf*CFrame.new(sx*5,2.6,0), Color3.fromRGB(52,48,44), Enum.Material.Metal, parent)
	end
	local g = Instance.new("SurfaceGui"); g.Face = Enum.NormalId.Front; g.Parent = b
	local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1,1); t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack; t.TextScaled = true
	t.TextColor3 = color or Color3.fromRGB(242,216,150); t.Text = text; t.Parent = g
end

-- Tavern and forge flank the square, facing in across the cross street.
local tav, tcf, tavDoor = building("Tavern", -84,CROSS_Z,32,26,17,-90, PLASTER, ROOF_A)
chimney(tcf,12,8,12,true)
sign(tav, tcf*CFrame.new(0,15.5,-15.4), "THE ROLLING DICE")
footpath(tavDoor, -SQ-2)
for i = 1, 3 do
	P("Tavern_BenchSeat", Vector3.new(7,0.5,2), tcf*CFrame.new(-22+i*8,3.6,-19), WOOD, Enum.Material.WoodPlanks, tav)
	P("Tavern_BenchLeg", Vector3.new(0.6,2.6,1.6), tcf*CFrame.new(-22+i*8,2,-19), TIMBER, Enum.Material.Wood, tav)
end

-- Blacksmith
local smi, scf, smiDoor = building("BlacksmithForge", 84,CROSS_Z,30,26,16,90, PLASTER2, ROOF_B)
chimney(scf,-11,8,15,true)
smi.Door_Panel:Destroy()
P("Forge_OpenBay", Vector3.new(13,9,2.2), scf*CFrame.new(0,9,-12.3), Color3.fromRGB(26,22,20), Enum.Material.Slate, smi)
sign(smi, scf*CFrame.new(0,15,-14.4), "THE IRON HEARTH", Color3.fromRGB(255,178,110))
footpath(smiDoor, SQ+2)
P("Forge_Hearth", Vector3.new(7,4,5), scf*CFrame.new(0,7.3,-5), STONE_F, Enum.Material.Brick, smi)
local coals = P("Forge_Coals", Vector3.new(5,0.8,3.6), scf*CFrame.new(0,9.6,-5), Color3.fromRGB(255,120,40), Enum.Material.Neon, smi)
local coalLight = Instance.new("PointLight"); coalLight.Color = Color3.fromRGB(255,146,64); coalLight.Range = 38; coalLight.Brightness = 3; coalLight.Parent = coals
local coalEm = Instance.new("ParticleEmitter"); coalEm.Rate = 20; coalEm.Lifetime = NumberRange.new(0.6,1.4)
coalEm.Speed = NumberRange.new(4,8); coalEm.Size = NumberSequence.new(0.5); coalEm.Transparency = NumberSequence.new(0.2)
coalEm.Color = ColorSequence.new(Color3.fromRGB(255,172,72)); coalEm.Parent = coals
P("Anvil_Stump", Vector3.new(2.4,2.4,2.4), scf*CFrame.new(-8,6.8,-1), TIMBER, Enum.Material.Wood, smi)
P("Anvil_Body", Vector3.new(1.9,1.3,4), scf*CFrame.new(-8,8.6,-1), Color3.fromRGB(62,62,68), Enum.Material.Metal, smi)
P("Anvil_Horn", Vector3.new(1.4,1,1.6), scf*CFrame.new(-8,8.6,-3.6), Color3.fromRGB(62,62,68), Enum.Material.Metal, smi)
P("Quench_Trough", Vector3.new(4,2,2.6), scf*CFrame.new(9,6.6,-1), TIMBER, Enum.Material.Wood, smi)
P("Quench_Water", Vector3.new(3.4,0.3,2), scf*CFrame.new(9,7.5,-1), Color3.fromRGB(58,96,128), Enum.Material.Glass, smi, { Transparency = 0.35 })
P("WeaponRack_Frame", Vector3.new(0.6,6,7), scf*CFrame.new(11,8.5,3), TIMBER, Enum.Material.Wood, smi)
for i = 1, 5 do
	P("Rack_Blade", Vector3.new(0.25,5,0.8), scf*CFrame.new(10.4,9,0.4+i*1.3)*CFrame.Angles(math.rad(12),0,0), Color3.fromRGB(184,188,196), Enum.Material.Metal, smi)
end

-- Apothecary terminates the main road at the north end, facing back down it.
local apo, acf = building("Apothecary", MAIN_X,NORTH_Z,28,22,15,0, Color3.fromRGB(206,214,196), Color3.fromRGB(72,92,80))
chimney(acf,10,6,10,true)
sign(apo, acf*CFrame.new(0,14,-12.4), "GREEN FLASK APOTHECARY", Color3.fromRGB(180,240,190))
P("Apothecary_Shelf", Vector3.new(17,0.5,1.6), acf*CFrame.new(0,9.4,-10.6), WOOD, Enum.Material.WoodPlanks, apo)
for i = 1, 6 do
	local hue = ({ Color3.fromRGB(120,240,150), Color3.fromRGB(150,180,255), Color3.fromRGB(255,160,200),
		Color3.fromRGB(255,220,120), Color3.fromRGB(190,140,255), Color3.fromRGB(140,240,240) })[i]
	local flask = P("Apothecary_Flask", Vector3.new(1.1,1.6,1.1), acf*CFrame.new(-7+i*2.4,10.4,-10.6), hue, Enum.Material.Neon, apo)
	local fl = Instance.new("PointLight"); fl.Color = hue; fl.Range = 8; fl.Brightness = 1.1; fl.Parent = flask
end

--[[
	Two mirrored terraces flanking the main road, evenly spaced, every door
	facing the road. The z spacing is a constant so the rhythm stays exact —
	that regularity is what separates a planned neighbourhood from scatter.
]]
local houseCount = 0
for i, z in ipairs({ 78, 106, 190, 218 }) do
	for _, side in ipairs({ -1, 1 }) do
		local rot = (side == -1) and -90 or 90   -- west row faces east, east row faces west
		local wall = ((i + (side == 1 and 1 or 0)) % 2 == 0) and PLASTER or PLASTER2
		local _, cf, door = building(string.format("Cottage_%s%d", (side == -1) and "W" or "E", i),
			side*ROW_X, z, 22, 18, 12, rot, wall, (i%2 == 0) and ROOF_B or ROOF_A)
		chimney(cf, 6, 5, 8, (i%2 == 1))
		footpath(door, side*(ROAD_W/2+1))
		houseCount += 1
	end
end

--============================================================ LAMPS
local function lampPost(x,z)
	local m = Instance.new("Model"); m.Name = "LampPost"; m.Parent = Lights
	P("LampPost_Base", Vector3.new(2.4,1.2,2.4), CFrame.new(x,4,z), STONE_F, Enum.Material.Cobblestone, m)
	P("LampPost_Column", Vector3.new(0.9,12,0.9), CFrame.new(x,10.6,z), TIMBER, Enum.Material.Wood, m)
	P("Lantern_Housing", Vector3.new(2.2,2.6,2.2), CFrame.new(x,17.2,z), Color3.fromRGB(52,44,36), Enum.Material.Metal, m, { Transparency = 0.25 })
	local core = P("Lantern_Core", Vector3.new(1.4,1.8,1.4), CFrame.new(x,17.2,z), Color3.fromRGB(255,196,110), Enum.Material.Neon, m)
	P("Lantern_Cap", Vector3.new(2.6,0.5,2.6), CFrame.new(x,18.7,z), Color3.fromRGB(52,44,36), Enum.Material.Metal, m)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(255,190,112); l.Range = 30; l.Brightness = 2.1; l.Shadows = true; l.Parent = core
end

-- Paired at a fixed interval down the main road, along the cross street, and
-- at the four corners of the square. Regular spacing, not hand-placed.
for z = GATE_Z+16, NORTH_Z-8, 28 do
	if math.abs(z-CROSS_Z) > SQ-4 then
		for _, side in ipairs({ -1, 1 }) do lampPost(side*(ROAD_W/2+4), z) end
	end
end
for x = -104, 104, 26 do
	if math.abs(x) > SQ+4 then
		for _, side in ipairs({ -1, 1 }) do lampPost(x, CROSS_Z+side*(CROSS_W/2+4)) end
	end
end
for _, sx in ipairs({ -1, 1 }) do
	for _, sz in ipairs({ -1, 1 }) do lampPost(sx*(SQ-6), CROSS_Z+sz*(SQ-6)) end
end

--============================================================ SPAWN
--[[
	Fully hidden, dead centre of the town square.

	Transparency 1, no decals or textures, no shadow, and CanCollide off so it
	cannot be felt underfoot either — characters spawn just above it and settle
	onto the plaza flagstones, which are the real floor. Verified in a live
	session: they land at y~6.5 on a 3.55 surface and do not fall through.
]]
local sp = Instance.new("SpawnLocation")
sp.Name = "SpawnLocation"
sp.Size = Vector3.new(12,0.4,12)
sp.CFrame = CFrame.new(MAIN_X,4.4,CROSS_Z)
sp.Anchored = true
sp.Transparency = 1
sp.CanCollide = false
sp.CanQuery = false
sp.CastShadow = false
sp.Neutral = true
sp.Enabled = true
sp.Parent = Village

local safe = P("SafeZone_Volume", Vector3.new(270,60,220), CFrame.new(0,30,152), Color3.new(1,1,1), Enum.Material.SmoothPlastic, Village,
	{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
safe:SetAttribute("SafeZone", true); safe:SetAttribute("ZoneId", "Village")

--============================================================ MARKET + PROPS
local function stall(x,z,rot,col,label)
	local m = Instance.new("Model"); m.Name = "MarketStall_"..label; m.Parent = Props
	local cf = CFrame.new(x,0,z)*CFrame.Angles(0,math.rad(rot),0)
	for _, o in ipairs({ {-6,-3.4},{6,-3.4},{-6,3.4},{6,3.4} }) do
		P("Stall_Post", Vector3.new(0.7,10,0.7), cf*CFrame.new(o[1],8.5,o[2]), TIMBER, Enum.Material.Wood, m)
	end
	P("Stall_Counter", Vector3.new(13,0.8,3), cf*CFrame.new(0,7.4,-3.4), WOOD, Enum.Material.WoodPlanks, m)
	P("Stall_CounterSkirt", Vector3.new(13,3,0.5), cf*CFrame.new(0,5.6,-4.6), TIMBER, Enum.Material.Wood, m)
	pitchedPair(m, "Stall_Awning", cf*CFrame.new(0,13.4,0), 10, 13.6, 28, 0.4, col, Enum.Material.Fabric, "Z")
	P("Stall_AwningRidge", Vector3.new(13.8,0.5,0.6), cf*CFrame.new(0,13.4+(10/2)*math.tan(math.rad(28)),0), col, Enum.Material.Fabric, m)
	for i = 1, 4 do
		P("Goods_Crate", Vector3.new(2.2,2.2,2.2), cf*CFrame.new(-5+i*2.6,4.7,3.6)*CFrame.Angles(0,rng:NextNumber()*3,0), WOOD, Enum.Material.WoodPlanks, m)
	end
	for i = 1, 5 do
		P("Goods_Produce", Vector3.new(0.9,0.9,0.9), cf*CFrame.new(-4.5+i*2.2,8.2,-3.4),
			Color3.fromRGB(rng:NextInteger(120,240),rng:NextInteger(80,200),rng:NextInteger(60,140)), Enum.Material.SmoothPlastic, m, { Shape = Enum.PartType.Ball })
	end
	local sg = P("Stall_Sign", Vector3.new(7.4,2,0.4), cf*CFrame.new(0,15.6,-2.6), Color3.fromRGB(64,44,28), Enum.Material.WoodPlanks, m)
	local g = Instance.new("SurfaceGui"); g.Face = Enum.NormalId.Front; g.Parent = sg
	local t = Instance.new("TextLabel"); t.Size = UDim2.fromScale(1,1); t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold; t.TextScaled = true; t.TextColor3 = Color3.fromRGB(246,236,214); t.Text = label; t.Parent = g
end
-- All four stalls inside the square as two facing rows either side of centre,
-- making a market street across the plaza rather than four scattered props.
stall(-27,CROSS_Z-26,-90,Color3.fromRGB(178,66,58),"PRODUCE")
stall(-27,CROSS_Z+26,-90,Color3.fromRGB(206,162,62),"TRINKETS")
stall( 27,CROSS_Z-26, 90,Color3.fromRGB(64,110,168),"POTIONS")
stall( 27,CROSS_Z+26, 90,Color3.fromRGB(78,142,94),"SUPPLIES")

-- Well sits in the north-west courtyard. On the road axis it blocked the one
-- route players are meant to walk straight down.
local WELL_X, WELL_Z = -92, 168
local well = Instance.new("Model"); well.Name = "StoneWell"; well.Parent = Props
for i = 1, 16 do
	local a = (i/16)*math.pi*2
	P("Well_Stone", Vector3.new(1.4,3,1.4), CFrame.new(WELL_X+math.cos(a)*3.4,4.9,WELL_Z+math.sin(a)*3.4)*CFrame.Angles(0,-a,0), STONE_F, Enum.Material.Cobblestone, well)
end
P("Well_Water", Vector3.new(0.3,5.4,5.4), CFrame.new(WELL_X,5.4,WELL_Z)*CFrame.Angles(0,0,math.rad(90)), Color3.fromRGB(48,88,124), Enum.Material.Glass, well,
	{ Transparency = 0.28, Shape = Enum.PartType.Cylinder })
for _, ox in ipairs({ -3.6, 3.6 }) do
	P("Well_Post", Vector3.new(0.7,6,0.7), CFrame.new(WELL_X+ox,9.4,WELL_Z), TIMBER, Enum.Material.Wood, well)
end
pitchedPair(well, "Well_Roof", CFrame.new(WELL_X,12.4,WELL_Z), 8, 6, 34, 0.5, ROOF_A, Enum.Material.Slate, "X")
for x = -8, 8, 4 do
	for z = -8, 8, 4 do
		P("Footpath_Tile", Vector3.new(3.8,0.5,3.8), CFrame.new(WELL_X+x,3.28,WELL_Z+z), Color3.fromRGB(124,116,104), Enum.Material.Cobblestone, Paths)
	end
end

-- Barrels stacked against the tavern wall, hay in the east courtyard, cart
-- parked parallel to the cross street. All lined up rather than strewn.
for i = 1, 5 do
	P("Barrel", Vector3.new(3.2,2.6,2.6), CFrame.new(-100,2.6,CROSS_Z-16+i*3.4)*CFrame.Angles(0,0,math.rad(90)), WOOD, Enum.Material.WoodPlanks, Props, { Shape = Enum.PartType.Cylinder })
end
for i = 1, 4 do
	P("HayBale", Vector3.new(4,3.4,3.4), CFrame.new(100,4.9,CROSS_Z+14+i*4.6)*CFrame.Angles(0,0,math.rad(90)),
		Color3.fromRGB(206,178,96), Enum.Material.Grass, Props, { Shape = Enum.PartType.Cylinder })
end
local cart = Instance.new("Model"); cart.Name = "MerchantCart"; cart.Parent = Props
P("Cart_Bed", Vector3.new(8,1.2,4.6), CFrame.new(-62,5.6,CROSS_Z-20), WOOD, Enum.Material.WoodPlanks, cart)
for _, oz in ipairs({ 2.1, -2.1 }) do
	P("Cart_Rail", Vector3.new(8,1.6,0.4), CFrame.new(-62,7,CROSS_Z-20+oz), TIMBER, Enum.Material.Wood, cart)
end
for _, o in ipairs({ {-2.8,-2.5},{-2.8,2.5} }) do
	P("Cart_Wheel", Vector3.new(0.6,3.8,3.8), CFrame.new(-62+o[1],4.5,CROSS_Z-20+o[2])*CFrame.Angles(0,math.rad(90),math.rad(90)), TIMBER, Enum.Material.Wood, cart, { Shape = Enum.PartType.Cylinder })
end

--============================================================ CLIFFS
--[[
	Layered so the silhouette reads as natural stone: earthen ridge at the base,
	rock mass above, a shelf and a crag cap on top, talus wedges at the foot.

	NOTE: an earlier version used a wedge rotated 180 as an overhang. That flips
	it upside down and it floats detached above the rock. Cap with a block.
]]
local function cliffSegment(x,z,facing,scale)
	local h = 48*scale
	local cf = CFrame.new(x,0,z)*CFrame.Angles(0,facing,0)
	P("Cliff_EarthenRidge", Vector3.new(38*scale,16*scale,26*scale), cf*CFrame.new(0,7*scale,7*scale), EARTH, Enum.Material.Ground, Cliffs)
	P("Cliff_RockMass", Vector3.new(32*scale,h,20*scale), cf*CFrame.new(0,h/2,0), ROCK, Enum.Material.Rock, Cliffs)
	P("Cliff_RockShelf", Vector3.new(26*scale,10*scale,14*scale), cf*CFrame.new(rng:NextNumber(-4,4)*scale,h*0.62,-5*scale), ROCK_D, Enum.Material.Rock, Cliffs)
	P("Cliff_Crag", Vector3.new(26*scale,8,18*scale), cf*CFrame.new(0,h+3.5,0), Color3.fromRGB(88,86,84), Enum.Material.Rock, Cliffs)
	WG("Cliff_Talus", Vector3.new(14*scale,12*scale,22*scale),
		cf*CFrame.new(rng:NextNumber(-8,8)*scale,6*scale,14*scale)*CFrame.Angles(0,math.rad(90),0), ROCK, Enum.Material.Rock, Cliffs)
	for i = 1, 3 do
		P("Cliff_Boulder", Vector3.new(1,1,1)*rng:NextNumber(6,13)*scale,
			cf*CFrame.new(rng:NextNumber(-16,16)*scale,rng:NextNumber(2,6)*scale,rng:NextNumber(10,18)*scale)*CFrame.Angles(rng:NextNumber()*3,rng:NextNumber()*3,rng:NextNumber()*3),
			ROCK, Enum.Material.Rock, Cliffs, { Shape = Enum.PartType.Ball })
	end
end

for z = 30, -360, -34 do
	cliffSegment(-286, z, math.rad(90), rng:NextNumber(0.9,1.25))
	cliffSegment(286, z, math.rad(-90), rng:NextNumber(0.9,1.25))
end
for x = -286, 286, 34 do cliffSegment(x, -380, 0, rng:NextNumber(0.95,1.3)) end
for x = -286, -150, 34 do cliffSegment(x, 34, math.rad(180), rng:NextNumber(0.9,1.2)) end
for x = 150, 286, 34 do cliffSegment(x, 34, math.rad(180), rng:NextNumber(0.9,1.2)) end

--============================================================ HUNTING PATH
for i = 0, 52 do
	local t = i/52
	local z = 44 - t*300
	local wob = math.sin(i*0.6)*14
	for c = -2, 2 do
		P("HuntingPath_MudTile", Vector3.new(rng:NextNumber(7,11),0.5,rng:NextNumber(7,11)),
			CFrame.new(wob+c*8.5+rng:NextNumber(-2,2),0.35,z)*CFrame.Angles(0,rng:NextNumber(-0.2,0.2),0),
			(rng:NextNumber() < 0.4) and EARTH_D or EARTH, Enum.Material.Ground, Trails)
	end
end

--============================================================ VEGETATION
--[[
	Canopy scale is the thing to keep an eye on. An earlier pass used 12-19
	stud spheres at up to 1.5x — ~28 studs across — on short trunks, which
	merged into one opaque green mass with nothing walkable underneath.
	Canopies stay 5-8 studs and trunks stay tall enough to walk beneath.
]]
local function gnarledTree(x,z,scale)
	local m = Instance.new("Model"); m.Name = "GnarledTree"; m.Parent = Flora
	local h = rng:NextNumber(20,28)*scale
	local base = CFrame.new(x,0,z)*CFrame.Angles(rng:NextNumber(-0.08,0.08),rng:NextNumber()*6.28,rng:NextNumber(-0.08,0.08))

	P("GnarledTree_Root", Vector3.new(4.2*scale,2.4*scale,4.2*scale), base*CFrame.new(0,1*scale,0), BARK_D, Enum.Material.Wood, m)
	for i = 1, 3 do
		local a = (i/3)*math.pi*2
		P("GnarledTree_RootFlare", Vector3.new(1.5*scale,1.8*scale,3.4*scale),
			base*CFrame.new(math.cos(a)*2*scale,1.1*scale,math.sin(a)*2*scale)*CFrame.Angles(math.rad(30),-a,0), BARK_D, Enum.Material.Wood, m)
	end

	local cur = base*CFrame.new(0,2*scale,0)
	for i = 1, 3 do
		local sh = h/3
		local wdt = (2.8-(i-1)*0.45)*scale
		P("GnarledTree_Trunk", Vector3.new(wdt,sh,wdt), cur*CFrame.new(0,sh/2,0), BARK, Enum.Material.Wood, m)
		cur = cur*CFrame.new(0,sh,0)*CFrame.Angles(rng:NextNumber(-0.13,0.13),rng:NextNumber(-0.25,0.25),rng:NextNumber(-0.13,0.13))
	end

	for i = 1, rng:NextInteger(3,5) do
		local a = rng:NextNumber()*math.pi*2
		local bh = h*rng:NextNumber(0.72,0.98)
		local bl = rng:NextNumber(4.5,7.5)*scale
		local bcf = base*CFrame.new(0,bh,0)*CFrame.Angles(0,a,0)
		P("GnarledTree_Branch", Vector3.new(0.9*scale,0.9*scale,bl), bcf*CFrame.new(0,0,bl/2)*CFrame.Angles(math.rad(-22),0,0), BARK, Enum.Material.Wood, m)
		P("GnarledTree_BranchDroop", Vector3.new(0.7*scale,0.7*scale,bl*0.65),
			bcf*CFrame.new(0,-bl*0.22,bl*0.88)*CFrame.Angles(math.rad(44),0,0), BARK_D, Enum.Material.Wood, m)
		P("GnarledTree_LeafCluster", Vector3.new(1,1,1)*rng:NextNumber(3.6,5.4)*scale,
			bcf*CFrame.new(0,-bl*0.32,bl*1.05), LEAVES[rng:NextInteger(1,4)], Enum.Material.Grass, m, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
	for i = 1, 3 do
		P("GnarledTree_Canopy", Vector3.new(1,1,1)*rng:NextNumber(5,8)*scale,
			base*CFrame.new(rng:NextNumber(-2.4,2.4)*scale,h+rng:NextNumber(-1,2)*scale,rng:NextNumber(-2.4,2.4)*scale),
			LEAVES[rng:NextInteger(1,4)], Enum.Material.Grass, m, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
end

local function bush(x,z,s)
	local m = Instance.new("Model"); m.Name = "WildBush"; m.Parent = Flora
	for i = 1, 3 do
		P("WildBush_Mass", Vector3.new(1,1,1)*rng:NextNumber(2.4,4)*s,
			CFrame.new(x+rng:NextNumber(-1.4,1.4),rng:NextNumber(1,1.9)*s,z+rng:NextNumber(-1.4,1.4)),
			({ LEAVES[1], LEAVES[2], MOSS })[rng:NextInteger(1,3)], Enum.Material.Grass, m, { Shape = Enum.PartType.Ball, CanCollide = false })
	end
end

local function tallGrass(x,z)
	local m = Instance.new("Model"); m.Name = "TallGrassPatch"; m.Parent = Flora
	for i = 1, rng:NextInteger(5,8) do
		P("TallGrass_Blade", Vector3.new(0.3,rng:NextNumber(2.4,4),0.3),
			CFrame.new(x+rng:NextNumber(-3,3),rng:NextNumber(1.3,2.1),z+rng:NextNumber(-3,3))*CFrame.Angles(rng:NextNumber(-0.28,0.28),rng:NextNumber()*6.28,rng:NextNumber(-0.28,0.28)),
			({ MOSS, LEAVES[3], Color3.fromRGB(96,128,62) })[rng:NextInteger(1,3)], Enum.Material.Grass, m, { CanCollide = false, CastShadow = false })
	end
end

local SPX, SPZ = -150, -90
local CAMP_SITES = { {120,-120,"Ridge"}, {-60,-235,"Hollow"}, {180,-250,"Deepwood"} }

-- Keep-out: arena, slime pit, camps, and the path corridor.
local function blocked(x,z,pad)
	if z < -300 and math.abs(x) < 115 then return true end
	if (Vector3.new(x,0,z) - Vector3.new(SPX,0,SPZ)).Magnitude < 78+pad then return true end
	for _, c in ipairs(CAMP_SITES) do
		if (Vector3.new(x,0,z) - Vector3.new(c[1],0,c[2])).Magnitude < 40+pad then return true end
	end
	if math.abs(x - math.sin((44-z)/300*52*0.6)*14) < 24 then return true end
	return false
end

local treeCount = 0
for i = 1, 190 do
	local x,z = rng:NextNumber(-268,268), rng:NextNumber(-352,26)
	if not blocked(x,z,6) then gnarledTree(x,z,rng:NextNumber(0.7,1.05)); treeCount += 1 end
end
for i = 1, 150 do
	local x,z = rng:NextNumber(-272,272), rng:NextNumber(-356,28)
	if not blocked(x,z,0) then bush(x,z,rng:NextNumber(0.8,1.5)) end
end
for i = 1, 190 do
	local x,z = rng:NextNumber(-274,274), rng:NextNumber(-356,30)
	if not blocked(x,z,-14) then tallGrass(x,z) end
end

--============================================================ SLIME PIT
--[[
	The ground slab tops out at y=0 and cannot be carved, so the depression is
	BUILT: a raised earthen bank ringing the pit with the fluid sitting just
	above ground level inside it.

	The fluid must be the highest surface in the middle. An earlier version put
	a 4-stud basin block centred at y=0.2 directly over a pool at y=1.1, which
	hid the pool completely.
]]
for i = 1, 40 do
	local a = (i/40)*math.pi*2
	local r = 54 + rng:NextNumber(-3,3)
	local bx, bz = SPX+math.cos(a)*r, SPZ+math.sin(a)*r
	P("SlimePit_Bank", Vector3.new(rng:NextNumber(11,17),rng:NextNumber(5,9),rng:NextNumber(9,14)),
		CFrame.new(bx,rng:NextNumber(1.6,3.2),bz)*CFrame.Angles(rng:NextNumber(-0.14,0.14),-a,rng:NextNumber(-0.1,0.1)),
		(i%3 == 0) and EARTH_D or EARTH, Enum.Material.Ground, Slime)
	if i%4 == 0 then
		P("SlimePit_BankRock", Vector3.new(1,1,1)*rng:NextNumber(5,9),
			CFrame.new(bx+math.cos(a)*4,2.2,bz+math.sin(a)*4)*CFrame.Angles(rng:NextNumber()*3,rng:NextNumber()*3,rng:NextNumber()*3),
			Color3.fromRGB(96,92,88), Enum.Material.Rock, Slime, { Shape = Enum.PartType.Ball })
	end
end
for i = 1, 30 do
	local a = (i/30)*math.pi*2
	local r = 46 + rng:NextNumber(-3,3)
	P("SlimePit_Shore", Vector3.new(rng:NextNumber(10,16),1.2,rng:NextNumber(10,16)),
		CFrame.new(SPX+math.cos(a)*r,0.5,SPZ+math.sin(a)*r)*CFrame.Angles(0,-a,0), Color3.fromRGB(78,62,44), Enum.Material.Ground, Slime)
end
P("SlimePool_Depth", Vector3.new(88,1.6,80), CFrame.new(SPX,0.5,SPZ), Color3.fromRGB(46,158,64), Enum.Material.SmoothPlastic, Slime, { Transparency = 0.15 })
local pool = P("SlimePool_Surface", Vector3.new(90,0.9,82), CFrame.new(SPX,1.4,SPZ), Color3.fromRGB(118,248,126), Enum.Material.Glass, Slime, { Transparency = 0.36 })
local poolLight = Instance.new("PointLight"); poolLight.Color = Color3.fromRGB(126,255,142); poolLight.Range = 46; poolLight.Brightness = 1.4; poolLight.Parent = pool
for i = 1, 14 do
	local a = rng:NextNumber()*math.pi*2
	local r = rng:NextNumber(6,36)
	P("SlimePool_Bubble", Vector3.new(1,1,1)*rng:NextNumber(2.6,5.5),
		CFrame.new(SPX+math.cos(a)*r,1.9,SPZ+math.sin(a)*r), Color3.fromRGB(160,255,168), Enum.Material.Neon, Slime,
		{ Shape = Enum.PartType.Ball, Transparency = 0.32 })
end
for i = 1, 7 do
	local a = rng:NextNumber()*math.pi*2
	local r = rng:NextNumber(12,34)
	P("SlimePool_SunkenStone", Vector3.new(1,1,1)*rng:NextNumber(6,11),
		CFrame.new(SPX+math.cos(a)*r,1.2,SPZ+math.sin(a)*r)*CFrame.Angles(rng:NextNumber()*3,rng:NextNumber()*3,rng:NextNumber()*3),
		Color3.fromRGB(88,84,80), Enum.Material.Rock, Slime, { Shape = Enum.PartType.Ball })
end
local drip = P("SlimePool_Emitter", Vector3.new(1,1,1), CFrame.new(SPX,2.2,SPZ), Color3.new(1,1,1), Enum.Material.SmoothPlastic, Slime,
	{ Transparency = 1, CanCollide = false, CastShadow = false })
local dripEm = Instance.new("ParticleEmitter")
dripEm.Rate = 9; dripEm.Lifetime = NumberRange.new(1.6,2.8); dripEm.Speed = NumberRange.new(1,2.5)
dripEm.Size = NumberSequence.new(1.5); dripEm.Transparency = NumberSequence.new(0.5)
dripEm.Color = ColorSequence.new(Color3.fromRGB(150,255,160))
dripEm.EmissionDirection = Enum.NormalId.Top; dripEm.SpreadAngle = Vector2.new(180,180); dripEm.Parent = drip

-- Glowing mushrooms. Caps stay 5-8 studs with a modest light; oversized Neon
-- caps at high brightness read as glare, not atmosphere.
local HUES = { Color3.fromRGB(176,104,240), Color3.fromRGB(104,230,132), Color3.fromRGB(96,196,240) }
for i = 1, 20 do
	local a = (i/20)*math.pi*2 + rng:NextNumber(-0.18,0.18)
	local r = rng:NextNumber(50,66)
	local mx, mz = SPX+math.cos(a)*r, SPZ+math.sin(a)*r
	local s = rng:NextNumber(0.7,1.35)
	local hue = HUES[(i%3)+1]
	local m = Instance.new("Model"); m.Name = "GlowingMushroom"; m.Parent = Slime
	P("Mushroom_Stalk", Vector3.new(1.3*s,7*s,1.3*s), CFrame.new(mx,3.5*s,mz), Color3.fromRGB(212,206,192), Enum.Material.SmoothPlastic, m)
	P("Mushroom_StalkRing", Vector3.new(2.2*s,0.5*s,2.2*s), CFrame.new(mx,5.4*s,mz), Color3.fromRGB(190,184,172), Enum.Material.SmoothPlastic, m)
	local cap = P("Mushroom_Cap", Vector3.new(6.5*s,4*s,6.5*s), CFrame.new(mx,7.4*s,mz), hue, Enum.Material.Neon, m, { Shape = Enum.PartType.Ball })
	P("Mushroom_CapUnder", Vector3.new(5.4*s,0.6*s,5.4*s), CFrame.new(mx,6.3*s,mz), Color3.fromRGB(238,232,224), Enum.Material.SmoothPlastic, m)
	local ml = Instance.new("PointLight"); ml.Color = hue; ml.Range = 15*s; ml.Brightness = 1.1; ml.Parent = cap
	for j = 1, rng:NextInteger(1,3) do
		local sa = rng:NextNumber()*6.28
		local sx, sz = mx+math.cos(sa)*rng:NextNumber(2,4), mz+math.sin(sa)*rng:NextNumber(2,4)
		local ss = s*rng:NextNumber(0.7,1.1)
		P("MushroomSprout_Stalk", Vector3.new(0.8*ss,4*ss,0.8*ss), CFrame.new(sx,2*ss,sz), Color3.fromRGB(212,206,192), Enum.Material.SmoothPlastic, m)
		P("MushroomSprout_Cap", Vector3.new(3.4*ss,2.2*ss,3.4*ss), CFrame.new(sx,4.2*ss,sz), hue, Enum.Material.Neon, m, { Shape = Enum.PartType.Ball })
	end
end

--============================================================ GOBLIN CAMPS
local HIDE = { Color3.fromRGB(146,116,80), Color3.fromRGB(120,96,72), Color3.fromRGB(158,132,96), Color3.fromRGB(102,84,64) }
local function camp(cx,cz,label)
	local m = Instance.new("Model"); m.Name = "GoblinCamp_"..label; m.Parent = Camps

	local fire = P("Campfire_Embers", Vector3.new(5,1.4,5), CFrame.new(cx,1.4,cz), Color3.fromRGB(255,124,42), Enum.Material.Neon, m)
	local fl = Instance.new("PointLight"); fl.Color = Color3.fromRGB(255,148,66); fl.Range = 44; fl.Brightness = 3.2; fl.Shadows = true; fl.Parent = fire
	local pe = Instance.new("ParticleEmitter"); pe.Rate = 26; pe.Lifetime = NumberRange.new(0.8,1.8)
	pe.Speed = NumberRange.new(5,10); pe.Size = NumberSequence.new(0.7); pe.Transparency = NumberSequence.new(0.2)
	pe.Color = ColorSequence.new(Color3.fromRGB(255,170,70)); pe.Parent = fire
	for i = 1, 6 do
		local a = (i/6)*math.pi*2
		P("Campfire_Log", Vector3.new(1.4,5.5,1.4), CFrame.new(cx+math.cos(a)*2.4,2.4,cz+math.sin(a)*2.4)*CFrame.Angles(math.rad(34),-a,0), BARK_D, Enum.Material.Wood, m)
		P("Campfire_Stone", Vector3.new(2.6,1.8,2.6), CFrame.new(cx+math.cos(a)*5.4,0.9,cz+math.sin(a)*5.4), ROCK, Enum.Material.Rock, m)
	end

	for t = 1, 3 do
		local a = (t/3)*math.pi*2 + 0.5
		local tcf = CFrame.new(cx+math.cos(a)*17,0,cz+math.sin(a)*17)*CFrame.Angles(0,-a,0)
		P("Tent_RidgePole", Vector3.new(0.7,0.7,14), tcf*CFrame.new(0,9,0), BARK_D, Enum.Material.Wood, m)
		for _, s in ipairs({ -1, 1 }) do
			P("Tent_HidePanel", Vector3.new(0.35,11,14), tcf*CFrame.new(s*3.6,4.6,0)*CFrame.Angles(0,0,math.rad(s*36)),
				HIDE[rng:NextInteger(1,#HIDE)], Enum.Material.Fabric, m)
			P("Tent_GuyLine", Vector3.new(0.25,0.25,7), tcf*CFrame.new(s*7,3.4,5)*CFrame.Angles(math.rad(42),0,0), Color3.fromRGB(78,66,52), Enum.Material.Fabric, m)
		end
		P("Tent_HideFlap", Vector3.new(7.4,7,0.35), tcf*CFrame.new(0,3.6,-6.9), HIDE[rng:NextInteger(1,#HIDE)], Enum.Material.Fabric, m)
	end

	for i = 1, 18 do
		local a = (i/18)*math.pi*2
		local r = 30 + rng:NextNumber(-3,3)
		local bx, bz = cx+math.cos(a)*r, cz+math.sin(a)*r
		if i%5 ~= 0 then
			P("Barricade_Plank", Vector3.new(0.9,rng:NextNumber(7,11),7),
				CFrame.new(bx,4.6,bz)*CFrame.Angles(rng:NextNumber(-0.14,0.14),-a,rng:NextNumber(-0.2,0.2)),
				({ BARK, BARK_D, Color3.fromRGB(96,72,48) })[rng:NextInteger(1,3)], Enum.Material.WoodPlanks, m)
			P("Barricade_CrossBrace", Vector3.new(0.6,0.6,8), CFrame.new(bx,7,bz)*CFrame.Angles(0,-a,math.rad(18)), BARK_D, Enum.Material.Wood, m)
			P("SpikedStake", Vector3.new(0.8,7,0.8), CFrame.new(bx,7.4,bz)*CFrame.Angles(math.rad(30),-a,0), Color3.fromRGB(88,66,44), Enum.Material.Wood, m)
			P("SpikedStake_Tip", Vector3.new(0.9,1.6,0.9), CFrame.new(bx+math.cos(a)*1.6,10.6,bz+math.sin(a)*1.6)*CFrame.Angles(math.rad(30),-a,0), Color3.fromRGB(58,44,32), Enum.Material.Wood, m)
		end
	end

	P("Goblin_BannerPole", Vector3.new(0.8,20,0.8), CFrame.new(cx+9,10,cz-9), BARK_D, Enum.Material.Wood, m)
	P("Goblin_Banner", Vector3.new(0.3,7,5), CFrame.new(cx+9,15,cz-6.6), Color3.fromRGB(126,52,44), Enum.Material.Fabric, m)
	P("Goblin_Skull", Vector3.new(1.8,1.8,1.8), CFrame.new(cx+9,20.6,cz-9), Color3.fromRGB(226,220,204), Enum.Material.SmoothPlastic, m, { Shape = Enum.PartType.Ball })
	P("CookPot", Vector3.new(3,4.4,4.4), CFrame.new(cx-8,2.4,cz+6)*CFrame.Angles(0,0,math.rad(90)), Color3.fromRGB(52,48,46), Enum.Material.Metal, m, { Shape = Enum.PartType.Cylinder })
end
for _, c in ipairs(CAMP_SITES) do camp(c[1], c[2], c[3]) end

--============================================================ STORYTELLING
for i = 1, 34 do
	local x,z = rng:NextNumber(-266,266), rng:NextNumber(-350,24)
	local s = rng:NextNumber(5,14)
	P("MossyBoulder", Vector3.new(s,s*0.8,s*1.1), CFrame.new(x,s*0.28,z)*CFrame.Angles(rng:NextNumber()*3,rng:NextNumber()*3,rng:NextNumber()*3), ROCK, Enum.Material.Rock, Story, { Shape = Enum.PartType.Ball })
	P("MossyBoulder_MossCap", Vector3.new(s*0.85,s*0.3,s*0.9), CFrame.new(x,s*0.5,z), MOSS, Enum.Material.Grass, Story, { Shape = Enum.PartType.Ball })
end
for i = 1, 14 do
	local x,z = rng:NextNumber(-250,250), rng:NextNumber(-330,20)
	local a = rng:NextNumber()*6.28
	local tilt = math.rad(rng:NextNumber(60,88))
	P("BrokenShield", Vector3.new(7,0.6,5), CFrame.new(x,0.9,z)*CFrame.Angles(tilt,a,0), Color3.fromRGB(104,72,52), Enum.Material.WoodPlanks, Story)
	P("BrokenShield_Boss", Vector3.new(2,0.5,2), CFrame.new(x,1.5,z)*CFrame.Angles(tilt,a,0), Color3.fromRGB(132,128,120), Enum.Material.Metal, Story, { Shape = Enum.PartType.Cylinder })
end
for i = 1, 10 do
	local x,z = rng:NextNumber(-244,244), rng:NextNumber(-326,16)
	local a = rng:NextNumber()*6.28
	local m = Instance.new("Model"); m.Name = "TreasureChest"; m.Parent = Story
	P("Chest_Body", Vector3.new(5,3.4,3.6), CFrame.new(x,2,z)*CFrame.Angles(0,a,0), Color3.fromRGB(96,64,38), Enum.Material.WoodPlanks, m)
	P("Chest_Lid", Vector3.new(5.2,1.4,3.8), CFrame.new(x,4.1,z)*CFrame.Angles(math.rad(-26),a,0), Color3.fromRGB(80,52,30), Enum.Material.WoodPlanks, m)
	P("Chest_Band", Vector3.new(5.3,0.5,3.9), CFrame.new(x,2.4,z)*CFrame.Angles(0,a,0), Color3.fromRGB(150,124,64), Enum.Material.Metal, m)
	P("Chest_Lock", Vector3.new(1,1.2,0.5), CFrame.new(x,2.8,z)*CFrame.Angles(0,a,0)*CFrame.new(0,0,-1.9), Color3.fromRGB(180,150,72), Enum.Material.Metal, m)
end
for i = 1, 18 do
	local x,z = rng:NextNumber(-260,260), rng:NextNumber(-340,20)
	P("FallenLog", Vector3.new(4,rng:NextNumber(14,24),4), CFrame.new(x,2,z)*CFrame.Angles(math.rad(90),rng:NextNumber()*6.28,0), BARK_D, Enum.Material.Wood, Story, { Shape = Enum.PartType.Cylinder })
end

--============================================================ ENEMY MARKERS
local SPECS = {
	{"Slime",-150,-70},{"Slime",-118,-108},{"Slime",-182,-104},{"Slime",-150,-130},
	{"Goblin",120,-120},{"Goblin",92,-96},{"Goblin",148,-146},
	{"Wolf",-230,-190},{"Wolf",230,-180},{"Wolf",-30,-160},
	{"GoblinWarrior",-60,-235},{"GoblinWarrior",180,-250},
	{"EliteGoblin",40,-290},
}
for i, s in ipairs(SPECS) do
	local mk = P(string.format("EnemySpawn_%s_%d", s[1], i), Vector3.new(5,0.3,5), CFrame.new(s[2],0.4,s[3]),
		Color3.fromRGB(255,90,90), Enum.Material.Neon, Spawns, { Transparency = 1, CanCollide = false, CastShadow = false })
	mk:SetAttribute("EnemyId", s[1]); mk:SetAttribute("Radius", 26); mk:SetAttribute("MaxAlive", 3)
end

--============================================================ BOSS ARENA
P("Arena_Floor", Vector3.new(3,170,170), CFrame.new(0,1.2,-400)*CFrame.Angles(0,0,math.rad(90)), Color3.fromRGB(96,88,80), Enum.Material.Ground, Arena, { Shape = Enum.PartType.Cylinder })
for i = 1, 20 do
	local a = (i/20)*math.pi*2
	local ph = rng:NextNumber(22,34)
	P("Arena_Pillar", Vector3.new(8,ph,8), CFrame.new(math.cos(a)*80,ph/2,-400+math.sin(a)*80), ROCK_D, Enum.Material.Slate, Arena)
	P("Arena_PillarCap", Vector3.new(10,2,10), CFrame.new(math.cos(a)*80,ph+1,-400+math.sin(a)*80), ROCK, Enum.Material.Slate, Arena)
	local br = P("Arena_Brazier", Vector3.new(3,1.6,3), CFrame.new(math.cos(a)*80,ph+2.8,-400+math.sin(a)*80), Color3.fromRGB(255,110,50), Enum.Material.Neon, Arena)
	local bl = Instance.new("PointLight"); bl.Color = Color3.fromRGB(255,140,60); bl.Range = 32; bl.Brightness = 2; bl.Parent = br
end
local bossMarker = P("BossSpawn", Vector3.new(8,0.3,8), CFrame.new(0,3,-400), Color3.fromRGB(255,60,60), Enum.Material.Neon, Arena,
	{ Transparency = 1, CanCollide = false, CastShadow = false })
bossMarker:SetAttribute("BossId", "GoblinKing")
local zoneGate = P("ZoneGate", Vector3.new(44,30,3), CFrame.new(0,15,-320), Color3.fromRGB(96,132,255), Enum.Material.ForceField, Arena, { Transparency = 0.5 })
zoneGate:SetAttribute("RequiresPower", 1200); zoneGate:SetAttribute("GateId", "GoblinKingArena")
for _, sx in ipairs({ -1, 1 }) do
	P("ZoneGate_Pylon", Vector3.new(7,34,7), CFrame.new(sx*24,17,-320), ROCK_D, Enum.Material.Slate, Arena)
	P("ZoneGate_PylonCap", Vector3.new(9,2,9), CFrame.new(sx*24,34,-320), ROCK, Enum.Material.Slate, Arena)
end

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

--============================================================ REPORT
local parts, unanchored = 0, 0
for _, d in ipairs(World:GetDescendants()) do
	if d:IsA("BasePart") then
		parts += 1
		if not d.Anchored then unanchored += 1 end
	end
end
print(string.format("[BuildWorld] %d parts | %d trees | %d enemy markers | unanchored: %d",
	parts, treeCount, #SPECS, unanchored))
