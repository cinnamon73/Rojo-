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

	Equipment models are placeholder geometry built from ItemConfig.Appearance.
	Swapping in real meshes means setting MeshId on the template — the welding,
	attach points, and cleanup here do not change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local BodyConfig = require(Config.BodyConfig)
local ItemConfig = require(Config.ItemConfig)
local RarityConfig = require(Config.RarityConfig)
local ItemInstance = require(Modules.ItemInstance)
local WeaponModels = require(Modules.WeaponModels)
local Logger = require(Modules.Logger)

local DataService = require(script.Parent.DataService)

local log = Logger.new("CharacterService")

local CharacterService = {}

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
local function buildPiece(instance: ItemInstance.Instance_, attachTo: BasePart, offset: CFrame, parent: Folder)
	local template = ItemConfig.Get(instance.TemplateId)
	if not template then
		return
	end

	local rarity = RarityConfig.Get(instance.Rarity)
	local appearance = template.Appearance

	local part = Instance.new("Part")
	part.Name = template.Id
	part.Size = appearance.Size
	part.Color = appearance.Color
	part.Material = appearance.Material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	-- Rare and above get a subtle glow in their rarity colour. Cheap, and it
	-- makes good gear read at a glance in a crowd.
	if rarity and rarity.VFXTier >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rarity.GlowColor
		light.Range = 6
		light.Brightness = 0.6 + 0.2 * rarity.VFXTier
		light.Parent = part
	end

	part.CFrame = attachTo.CFrame * offset
	part.Parent = parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachTo
	weld.Part1 = part
	weld.Parent = part
end

--[[
	Builds the weapon model and joints it to the right hand with a Motor6D.

	A Motor6D rather than a weld specifically so the swing can be animated by
	tweening C0 — that replicates to every client automatically, so the
	animation costs no extra network traffic and stays in sync with the damage
	the server already applied.
]]
local function buildWeapon(instance: ItemInstance.Instance_, character: Model, parent: Folder)
	local hand = character:FindFirstChild("RightHand") :: BasePart?
	if not hand then
		return
	end

	local model = WeaponModels.Build(instance)
	if not model then
		return
	end

	local template = ItemConfig.Get(instance.TemplateId)
	local archetype = template and template.Archetype
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
	model:SetAttribute("Archetype", archetype or "Sword")
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
	Rebuilds every equipped item's model on the character.

	Destroys and rebuilds wholesale rather than diffing: equipment changes are
	rare and a handful of parts is cheap, whereas diff bugs leave ghost armour
	welded to players.
]]
function CharacterService.RefreshEquipmentVisuals(player: Player)
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

	for slot, instanceId in pairs(profile.Equipment) do
		if instanceId ~= "" then
			local instance = profile.Inventory.Items[instanceId]
			local attach = BodyConfig.AttachPoints[slot]

			if instance and slot == "Weapon" then
				buildWeapon(instance, character, folder)

			elseif instance and attach then
				local mirrored = BodyConfig.MirroredSlots[slot]

				if mirrored then
					-- Boots and similar: one model per side, mirrored across X.
					for index, partName in ipairs(mirrored) do
						local bodyPart = character:FindFirstChild(partName) :: BasePart?
						if bodyPart then
							local offset = attach.Offset
							if index == 2 then
								offset = CFrame.new(-offset.X, offset.Y, offset.Z) * (offset - offset.Position)
							end
							buildPiece(instance, bodyPart, offset, folder)
						end
					end
				else
					local bodyPart = character:FindFirstChild(attach.Part) :: BasePart?
					if bodyPart then
						buildPiece(instance, bodyPart, attach.Offset, folder)
					end
				end
			end
		end
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

	-- ApplyDescription rebuilds body parts, so visuals must come after it or
	-- they weld to parts that are about to be replaced.
	task.wait(0.2)
	CharacterService.RefreshEquipmentVisuals(player)
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
