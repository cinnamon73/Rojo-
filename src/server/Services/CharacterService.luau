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

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local BodyConfig = require(Config.BodyConfig)
local ItemConfig = require(Config.ItemConfig)
local RarityConfig = require(Config.RarityConfig)
local ItemInstance = require(Modules.ItemInstance)
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
	Resolved body-part ids per preset, keyed by preset id. Populated lazily and
	cached for the life of the server — a bundle's contents never change.
]]
local resolvedParts: { [string]: { [string]: number } } = {}
local resolveAttempted: { [string]: boolean } = {}

--[[
	Turns a bundle id into concrete body-part mesh ids.

	The path is Roblox's own: a body bundle contains a UserOutfit, and an outfit
	can be turned into a HumanoidDescription that already has the part ids
	filled in. Reading them out of that is far more robust than hardcoding five
	asset ids that silently rot when the bundle is updated.

	Both calls are web-backed, so both are pcall'd and the result cached. A
	failure is not fatal — the preset falls back to default R15 parts shaped by
	its scale values.
]]
local function resolveBundleParts(preset: BodyConfig.BodyPreset): { [string]: number }?
	if resolvedParts[preset.Id] then
		return resolvedParts[preset.Id]
	end

	if preset.BundleId == 0 or resolveAttempted[preset.Id] then
		return nil
	end

	resolveAttempted[preset.Id] = true

	local ok, details = pcall(function()
		return AssetService:GetBundleDetailsAsync(preset.BundleId)
	end)

	if not ok or type(details) ~= "table" then
		log:Warn("could not read bundle %d for '%s': %s", preset.BundleId, preset.Id, tostring(details))
		return nil
	end

	local outfitId: number? = nil
	for _, item in ipairs(details.Items or {}) do
		if item.Type == "UserOutfit" then
			outfitId = item.Id
			break
		end
	end

	if not outfitId then
		log:Warn("bundle %d ('%s') contains no outfit — cannot read body parts", preset.BundleId, preset.Id)
		return nil
	end

	local okDesc, description = pcall(function()
		return Players:GetHumanoidDescriptionFromOutfitId(outfitId :: number)
	end)

	if not okDesc then
		log:Warn("could not load outfit %d for '%s': %s", outfitId, preset.Id, tostring(description))
		return nil
	end

	local parts = {
		Torso = description.Torso,
		LeftArm = description.LeftArm,
		RightArm = description.RightArm,
		LeftLeg = description.LeftLeg,
		RightLeg = description.RightLeg,
	}

	resolvedParts[preset.Id] = parts
	log:Info("resolved body parts for '%s' from bundle %d", preset.Id, preset.BundleId)

	return parts
end

--[[
	Overwrites the body fields of `description` from `preset`, leaving head,
	face, and accessories alone.

	Part ids come from the bundle when one is configured, otherwise from the
	preset's explicit overrides, otherwise 0 (default R15). Scales apply either
	way — they shape whatever meshes are in use.
]]
local function applyPresetToDescription(description: HumanoidDescription, preset: BodyConfig.BodyPreset)
	local parts = resolveBundleParts(preset)

	description.Torso = (parts and parts.Torso) or preset.Torso
	description.LeftArm = (parts and parts.LeftArm) or preset.LeftArm
	description.RightArm = (parts and parts.RightArm) or preset.RightArm
	description.LeftLeg = (parts and parts.LeftLeg) or preset.LeftLeg
	description.RightLeg = (parts and parts.RightLeg) or preset.RightLeg

	description.BodyTypeScale = preset.BodyTypeScale
	description.HeightScale = preset.HeightScale
	description.WidthScale = preset.WidthScale
	description.DepthScale = preset.DepthScale
	description.HeadScale = preset.HeadScale
	description.ProportionScale = preset.ProportionScale

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

	local profile = DataService.Get(player)
	local presetId = (profile and profile.Character and profile.Character.BodyType) or ""
	local preset = BodyConfig.Get(presetId) or BodyConfig.Get(BodyConfig.DefaultPreset)
	if not preset then
		return false
	end

	local ok, err = pcall(function()
		local description = humanoid:GetAppliedDescription()
		applyPresetToDescription(description, preset)
		humanoid:ApplyDescription(description)
	end)

	if not ok then
		log:Warn("could not apply body for %s: %s", player.Name, tostring(err))
		return false
	end

	return true
end

--[[
	Sets the body preset and re-applies it. Returns a result table so the
	remote handler can pass a reason straight back to the UI.
]]
function CharacterService.SetBodyType(player: Player, presetId: string): any
	if not BodyConfig.IsValid(presetId) then
		return { Success = false, Error = "InvalidBodyType" }
	end

	local profile = DataService.Get(player)
	if not profile then
		return { Success = false, Error = "ProfileNotLoaded" }
	end

	profile.Character.BodyType = presetId
	CharacterService.ApplyBody(player)

	return { Success = true, BodyType = presetId }
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

	local folder = Instance.new("Folder")
	folder.Name = EQUIPMENT_FOLDER
	folder.Parent = character

	for slot, instanceId in pairs(profile.Equipment) do
		if instanceId ~= "" then
			local instance = profile.Inventory.Items[instanceId]
			local attach = BodyConfig.AttachPoints[slot]

			if instance and attach then
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

	local unconfigured = BodyConfig.GetUnconfigured()
	if #unconfigured > 0 then
		log:Warn(
			"no body bundle set for: %s — these use default R15 meshes shaped only by scale. "
				.. "Set BundleId in BodyConfig for real body meshes.",
			table.concat(unconfigured, ", ")
		)
	end

	log:Info("started")
end

return CharacterService
