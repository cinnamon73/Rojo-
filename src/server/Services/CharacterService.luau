--!strict
--[[
	CharacterService — standardised bodies and equipment visuals.

	Body standardisation works by taking the player's OWN applied description
	and overwriting only the body fields. Head, Face, hair, hats, and every
	other accessory are left exactly as they were, so players still look like
	themselves; only the frame the armour welds to becomes uniform.

	Using GetAppliedDescription rather than GetHumanoidDescriptionFromUserId
	matters: the former reads what is already loaded, the latter is a web call
	that can fail or rate-limit on a full server.

	The class weapon is placeholder geometry built by WeaponModels.
	Swapping in real meshes means setting MeshId on the template — the welding,
	attach points, and cleanup here do not change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local BodyConfig = require(Config.BodyConfig)
local ClassConfig = require(Config.ClassConfig)
local WeaponModels = require(Modules.WeaponModels)
local Logger = require(Modules.Logger)
local Signal = require(Modules.Signal)

local DataService = require(script.Parent.DataService)

local log = Logger.new("CharacterService")

local CharacterService = {}

--[[
	Fires (player) once a spawned character is fully built and its profile is
	loaded. ClassService listens for this to apply stats and the class weapon,
	which keeps CharacterService from having to know classes exist.
]]
CharacterService.CharacterReady = Signal.new()

local EQUIPMENT_FOLDER = "EquippedVisuals"

-- Warned once per server rather than per spawn.
local warnedAboutRig = false

--========================================================================
-- Body
--========================================================================

--[[
	Normalises the body fields of `description`, leaving head, face, and
	accessories alone.
]]
local function applyStandardBody(description: HumanoidDescription)
	local body = BodyConfig.Standard

	description.Torso = body.Torso
	description.LeftArm = body.LeftArm
	description.RightArm = body.RightArm
	description.LeftLeg = body.LeftLeg
	description.RightLeg = body.RightLeg

	description.BodyTypeScale = body.BodyTypeScale
	description.HeightScale = body.HeightScale
	description.WidthScale = body.WidthScale
	description.DepthScale = body.DepthScale
	description.HeadScale = body.HeadScale
	description.ProportionScale = body.ProportionScale

	if BodyConfig.ClearClothing then
		description.Shirt = 0
		description.Pants = 0
		description.GraphicTShirt = 0
	end
end

--[[
	Applies the player's chosen body to their current character.
	Safe to call repeatedly; ApplyDescription is idempotent.
]]
function CharacterService.ApplyBody(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		if not warnedAboutRig then
			warnedAboutRig = true
			log:Warn(
				"characters are loading as %s, but the equipment attach points assume R15. "
					.. "Set Game Settings > Avatar > Avatar Type to R15.",
				humanoid.RigType.Name
			)
		end
		return false
	end

	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()
		applyStandardBody(description)
		humanoid:ApplyDescription(description)
	end)

	if not ok then
		log:Warn("could not apply body for %s: %s", player.Name, tostring(err))
		return false
	end

	return true
end

--========================================================================
-- Equipment visuals
--========================================================================

local function clearVisuals(character: Model)
	local folder = character:FindFirstChild(EQUIPMENT_FOLDER)
	if folder then
		folder:Destroy()
	end
end

--[[
	Builds one placeholder part for an item and welds it to `attachTo`.

	WeldConstraint rather than Motor6D: these are decorative and never animated
	independently, and a weld survives the part being unanchored by physics.
]]

--[[
	Builds the weapon model and joints it to the right hand with a Motor6D.

	A Motor6D rather than a weld specifically so the swing can be animated by
	tweening C0 — that replicates to every client automatically, so the
	animation costs no extra network traffic and stays in sync with the damage
	the server already applied.
]]
local function buildWeapon(definition: ClassConfig.ClassDefinition, character: Model, parent: Folder)
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end

	local model = WeaponModels.Build(
		definition.WeaponArchetype,
		definition.WeaponColor,
		definition.WeaponMaterial,
		definition.Id .. "Weapon"
	)
	if not model then
		return
	end

	local archetype = definition.WeaponArchetype
	local grip = WeaponModels.GetGripOffset(archetype)

	local handle = model.PrimaryPart :: BasePart
	model.Parent = parent
	handle.CFrame = hand.CFrame * grip

	local motor = Instance.new("Motor6D")
	motor.Name = "WeaponJoint"
	motor.Part0 = hand
	motor.Part1 = handle
	motor.C0 = grip
	motor.Parent = hand

	-- Recorded so the swing animation can find it without a search.
	model:SetAttribute("Archetype", archetype)
end

--[[
	Plays a swing on the player's equipped weapon.

	No-ops when there is no weapon, so unarmed attacks simply do not animate
	rather than erroring.
]]
function CharacterService.SwingWeapon(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local hand = character:FindFirstChild("RightHand")
	local motor = hand and hand:FindFirstChild("WeaponJoint") :: Motor6D?
	if not motor then
		return
	end

	local folder = character:FindFirstChild(EQUIPMENT_FOLDER)
	local model = folder and folder:FindFirstChildWhichIsA("Model")
	local archetype = model and model:GetAttribute("Archetype") or "Sword"

	local rest, swung = WeaponModels.GetSwing(archetype :: string)

	-- Out fast, back slower: the snap is what makes a hit feel like it landed.
	TweenService:Create(motor, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = swung }):Play()
	task.delay(0.11, function()
		if motor.Parent then
			TweenService:Create(motor, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = rest }):Play()
		end
	end)
end

--[[
	Welds the class offhand (shield, parrying dagger) to the left forearm.

	A WeldConstraint, not a Motor6D: offhands are never animated, and a weld
	survives the arm being moved by animations without fighting them.
]]
local function buildOffhand(definition: ClassConfig.ClassDefinition, character: Model, parent: Folder)
	if not definition.Offhand then
		return
	end

	local arm = character:FindFirstChild("LeftLowerArm") :: BasePart?
	if not arm then
		return
	end

	local model = WeaponModels.BuildOffhand(
		definition.Offhand,
		definition.WeaponColor,
		definition.WeaponMaterial,
		definition.Id .. "Offhand"
	)
	if not model then
		return
	end

	local handle = model.PrimaryPart :: BasePart
	model.Parent = parent

	-- Flat against the outside of the forearm, face outward.
	handle.CFrame = arm.CFrame * CFrame.new(-0.55, 0, 0) * CFrame.Angles(0, 0, math.rad(90))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arm
	weld.Part1 = handle
	weld.Parent = handle
end

--[[
	Rebuilds the class weapon on the character.

	Destroys and rebuilds wholesale rather than diffing. There is only one item
	now, changes are rare, and diff bugs leave ghost weapons welded to players.

	Reads the class from the profile via ClassConfig rather than asking
	ClassService, deliberately: ClassService already depends on this module, and
	going the other way would close a require cycle.
]]
function CharacterService.RefreshLoadout(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local profile = DataService.Get(player)
	if not profile then
		return
	end

	clearVisuals(character)

	-- Drop any joint left over from the previous weapon.
	local hand = character:FindFirstChild("RightHand")
	local oldMotor = hand and hand:FindFirstChild("WeaponJoint")
	if oldMotor then
		oldMotor:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = EQUIPMENT_FOLDER
	folder.Parent = character

	local definition = ClassConfig.Get(profile.Class) or ClassConfig.Get(ClassConfig.Default)
	if definition then
		buildWeapon(definition, character, folder)
		buildOffhand(definition, character, folder)
	end
end

--========================================================================
-- Lifecycle
--========================================================================

local function onCharacterAdded(player: Player, character: Model)
	-- Wait for the humanoid and the parts we weld to before touching anything.
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	character:WaitForChild("UpperTorso", 10)

	-- The profile may still be loading on a fast spawn.
	local deadline = os.clock() + 15
	while not DataService.Get(player) and os.clock() < deadline and player.Parent do
		task.wait(0.15)
	end

	if not player.Parent then
		return
	end

	CharacterService.ApplyBody(player)

	-- ApplyDescription rebuilds body parts, so anything welded must come after
	-- it or it attaches to parts that are about to be replaced.
	task.wait(0.2)

	CharacterService.CharacterReady:Fire(player)
end

local started = false

function CharacterService.Start()
	if started then
		return
	end
	started = true

	local function hook(player: Player)
		player.CharacterAppearanceLoaded:Connect(function(character)
			task.spawn(onCharacterAdded, player, character)
		end)

		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end

	log:Info("started (standard R15 body for all players)")
end

return CharacterService
