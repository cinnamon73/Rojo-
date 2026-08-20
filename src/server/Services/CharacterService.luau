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
local WeaponModels = require(Modules.WeaponModels)
local WeaponConfig = require(Config.WeaponConfig)
local Remotes = require(Modules.Remotes)
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
local function buildWeapon(weapon: WeaponConfig.WeaponDefinition, character: Model, _parent: Folder)
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid then
		return
	end

	local model = WeaponModels.BuildFromItem(weapon, weapon.Id .. "Weapon")
	if not model then
		return
	end

	--[[
		The weapon is a real Tool: it lives in the backpack, shows on the
		hotbar, and can be stowed and drawn with the 1 key. Tool.Grip uses the
		same hand-relative CFrame our Motor6D C0 did, so GetGripOffset carries
		over unchanged — and swings tween Grip instead of a joint.
	]]
	local tool = Instance.new("Tool")
	tool.Name = weapon.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.Grip = WeaponModels.GetGripOffset(weapon.Archetype)
	tool:SetAttribute("Archetype", weapon.Archetype)
	-- The moveset is looked up from this, not from the wielder's class.
	tool:SetAttribute("WeaponId", weapon.Id)
	tool:SetAttribute("ClassWeapon", true)

	for _, child in ipairs(model:GetChildren()) do
		child.Parent = tool
	end
	model:Destroy()

	tool.Parent = player:FindFirstChildOfClass("Backpack") or player
	humanoid:EquipTool(tool)
end

--[[
	Plays a swing on the player's equipped weapon.

	No-ops when there is no weapon, so unarmed attacks simply do not animate
	rather than erroring.
]]

--[[
	Per-player combo bookkeeping. Melee cycles slash -> backhand -> overhead;
	pausing longer than COMBO_RESET drops back to the opener.

	These declarations were deleted once by a mechanical edit that consumed
	"the comment above the function" — which was the comment above THESE — and
	every melee swing then died with "attempt to index nil" at the first
	comboState lookup. If you move them, move their comment with them.
]]
local comboState: { [Player]: { Step: number, LastAt: number } } = {}
local COMBO_RESET = 1.6

--[[
	Announces a swing on the FX bus. The animation itself runs CLIENT-side in
	FXController on every machine — a 0.07s strike tweened on the server
	arrives as one or two network snapshots and looks like teleporting, which
	is exactly the mistake the old weld tween made.

	The server still owns the combo COUNT (slash -> backhand -> overhead,
	resetting after COMBO_RESET seconds idle) so all clients draw the same
	step and a future per-step damage bonus has a server-side number.
]]
function CharacterService.SwingWeapon(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or not tool:GetAttribute("ClassWeapon") then
		return
	end

	local archetype = (tool:GetAttribute("Archetype") or "Sword") :: string
	local step = 1

	local weaponId = (tool:GetAttribute("WeaponId") or archetype) :: string

	if WeaponModels.IsMelee(archetype) then
		local state = comboState[player]
		local now = os.clock()

		-- Combo length comes from how many swings the weapon actually has
		-- authored. Hardcoding 3 here made the greataxe's two-hit combo play
		-- cleave, crash, cleave-again-as-step-3 - a stutter with no animation
		-- of its own.
		local steps = WeaponConfig.GetComboLength(weaponId)

		if not state or now - state.LastAt > COMBO_RESET then
			state = { Step = 1, LastAt = now }
		else
			state = { Step = (state.Step % steps) + 1, LastAt = now }
		end
		comboState[player] = state
		step = state.Step
	end

	local fx = Remotes.Get("FXEvent") :: RemoteEvent
	fx:FireAllClients({
		Kind = "Swing",
		UserId = player.UserId,
		Archetype = archetype,
		WeaponId = weaponId,
		Step = step,
	})
end

--[[
	Welds the class offhand (shield, parrying dagger) to the left forearm.

	A WeldConstraint, not a Motor6D: offhands are never animated, and a weld
	survives the arm being moved by animations without fighting them.
]]
local function buildOffhand(weapon: WeaponConfig.WeaponDefinition, character: Model, parent: Folder)
	if not weapon.Offhand then
		return
	end

	local arm = character:FindFirstChild("LeftLowerArm") :: BasePart?
	if not arm then
		return
	end

	local model = WeaponModels.BuildOffhand(
		weapon.Offhand,
		weapon.Appearance.Color,
		weapon.Appearance.Material,
		weapon.Id .. "Offhand"
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

	Reads the equipped ITEM from the profile via WeaponConfig rather than asking
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

	-- Retire the previous class weapon wherever it is: equipped (a child of
	-- the character) or stowed (in the backpack).
	for _, container in ipairs({ character, player:FindFirstChildOfClass("Backpack") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("ClassWeapon") then
					child:Destroy()
				end
			end
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = EQUIPMENT_FOLDER
	folder.Parent = character

	local weapon = WeaponConfig.GetEquipped(profile)
	buildWeapon(weapon, character, folder)
	buildOffhand(weapon, character, folder)
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

	Players.PlayerRemoving:Connect(function(player)
		comboState[player] = nil
	end)

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
