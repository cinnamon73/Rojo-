--!strict
--[[
	CombatController — attack input and combat feedback.

	Sends nothing but "I attacked this model". Damage, crits, range and cooldown
	are all decided server-side; this only picks a target and draws the result.

	Targeting tries the model under the cursor first, then falls back to the
	nearest enemy in front of the player. The fallback is what makes this work
	on touch without asking players to tap a moving enemy precisely — and on
	desktop it means a slightly-off click still lands, which matters far more
	for feel than strict aiming does for a game like this.

	Bound through ContextActionService so mouse, touch and gamepad all work from
	one definition rather than three input paths.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Theme = require(UIModules.Theme)
local Remotes = require(Modules.Remotes)
local Logger = require(Modules.Logger)
local GameConfig = require(Config.GameConfig)
local ClassConfig = require(Config.ClassConfig)

local log = Logger.new("CombatController")
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local CombatController = {}

local ACTION_NAME = "RNGA_Attack"
local MAX_TARGET_DISTANCE = 95

local client: any = nil
local attackCooldownUntil = 0

--========================================================================
-- Targeting
--========================================================================

local function enemiesFolder(): Folder?
	return Workspace:FindFirstChild("Enemies") :: Folder?
end

--[[ Walks up from a hit part to the enemy model that owns it. ]]
local function enemyFromInstance(instance: Instance?): Model?
	local folder = enemiesFolder()
	if not instance or not folder then
		return nil
	end

	local current: Instance? = instance
	while current and current ~= folder do
		if current:IsA("Model") and current.Parent == folder then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function isAlive(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

--[[
	Nearest living enemy, preferring ones the player is roughly facing so
	attacking does not silently target something behind them.
]]
local function nearestEnemy(): Model?
	local folder = enemiesFolder()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not folder or not root then
		return nil
	end

	local origin = (root :: BasePart).Position
	local facing = (root :: BasePart).CFrame.LookVector

	local best: Model? = nil
	local bestScore = math.huge

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and isAlive(model) then
			local primary = model.PrimaryPart
			if primary then
				local offset = primary.Position - origin
				local distance = offset.Magnitude

				if distance <= MAX_TARGET_DISTANCE then
					-- Penalise anything behind the player rather than excluding
					-- it, so a target directly behind is still reachable when
					-- it is the only one.
					local alignment = facing:Dot(offset.Unit)
					local score = distance * (if alignment > 0.1 then 1 else 2.5)

					if score < bestScore then
						best = model
						bestScore = score
					end
				end
			end
		end
	end

	return best
end

local function targetUnderCursor(): Model?
	local mouseLocation = game:GetService("UserInputService"):GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * MAX_TARGET_DISTANCE, params)
	if not result then
		return nil
	end

	local model = enemyFromInstance(result.Instance)
	if model and isAlive(model) then
		return model
	end

	return nil
end

--========================================================================
-- Attacking
--========================================================================

local function attack()
	local now = os.clock()
	if now < attackCooldownUntil then
		return
	end

	--[[
		ALWAYS fire, target or not. The server swings at air on purpose ("the
		player still pressed the button") — but that logic was unreachable,
		because this used to return silently when nothing was in range. A click
		that produces nothing at all is indistinguishable from a broken game,
		and was reported as exactly that.
	]]
	local target = targetUnderCursor() or nearestEnemy()

	-- Local throttle only. The server enforces the real cooldown from the
	-- player's attack speed; this just avoids flooding the remote.
	attackCooldownUntil = now + 0.1

	log:Info("attack: target=%s", target and target.Name or "air")

	local remote = Remotes.Get("AttackRequest") :: RemoteEvent
	remote:FireServer(target)
end

--[[
	Debug handle so the full CLIENT attack path — targeting included — can be
	exercised from the command bar. The earlier "verified" combat test fired
	the remote directly and skipped everything in this file, which is how a
	dead click chain shipped as working.
]]
function CombatController.DebugAttack()
	attack()
end

--========================================================================
-- Feedback
--========================================================================

--[[ Floating damage number that rises and fades. ]]
local function showDamage(position: Vector3, amount: number, crit: boolean)
	local settings = (client and client.Profile and client.Profile.Settings) or {}
	if settings.DamageNumbers == false then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Anchored = true
	anchor.Position = position + Vector3.new(math.random(-15, 15) / 10, 2, math.random(-15, 15) / 10)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 40)
	billboard.AlwaysOnTop = true
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = if crit then Theme.Font.Display else Theme.Font.Bold
	label.TextSize = if crit then 30 else 21
	label.TextColor3 = if crit then Theme.Color.Warning else Theme.Color.Text
	label.TextStrokeTransparency = 0.35
	label.Text = if crit then string.format("%d!", amount) else tostring(amount)
	label.Parent = billboard

	TweenService:Create(anchor, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 6, 0),
	}):Play()

	TweenService:Create(label, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()

	Debris:AddItem(anchor, 1)
end

--========================================================================
-- Start
--========================================================================

--========================================================================
-- Aim zoom
--========================================================================

local DEFAULT_FOV = 70
local AIM_FOV = 52
local aiming = false

--[[
	Ranged classes zoom while the attack button is held: press to shoulder the
	bow and fire, release to relax. Purely a camera FOV tween — no accuracy
	mechanic behind it (yet), so it can be cosmetic without lying about
	anything.
]]
local function isRangedClass(): boolean
	local profile = client and client.Profile
	local definition = ClassConfig.Get(profile and profile.Class) or ClassConfig.Get(ClassConfig.Default)
	return definition ~= nil and definition.AttackRange >= 30
end

local function setAiming(on: boolean)
	if aiming == on then
		return
	end
	aiming = on

	local target = if on then AIM_FOV else DEFAULT_FOV
	TweenService:Create(camera, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = target,
	}):Play()
end

local started = false

function CombatController.Start(clientState: any)
	if started then
		return
	end
	started = true

	client = clientState

	ContextActionService:BindAction(ACTION_NAME, function(_, state)
		if state == Enum.UserInputState.Begin then
			if isRangedClass() then
				setAiming(true)
			end
			attack()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			setAiming(false)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.ButtonR2)

	--[[
		The weapon is a Tool, and an equipped Tool claims left-click as its
		activation. Whether ContextActionService also still receives that click
		varies by input path — so the tool's own Activated signal is bound as a
		second trigger. Double-fires are absorbed by attack()'s 0.1s throttle.
	]]
	local function hookTool(character: Model)
		local function onChild(child: Instance)
			if child:IsA("Tool") and child:GetAttribute("ClassWeapon") then
				child.Activated:Connect(attack)
			end
		end
		for _, child in ipairs(character:GetChildren()) do
			onChild(child)
		end
		character.ChildAdded:Connect(onChild)
	end

	if player.Character then
		hookTool(player.Character)
	end
	player.CharacterAdded:Connect(hookTool)

	-- A class swap can land while zoomed; a melee class stuck at aim FOV
	-- would look broken with no way back.
	client.ProfileChanged:Connect(function()
		if not isRangedClass() then
			setAiming(false)
		end
	end)

	local feedback = Remotes.Get("CombatEvent") :: RemoteEvent
	feedback.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		if payload.Kind == "Damage" and typeof(payload.Position) == "Vector3" then
			showDamage(payload.Position, payload.Amount or 0, payload.Crit == true)
		elseif payload.Kind == "Kill" then
			log:Info("killed %s (+%d XP, +%d coins)%s",
				tostring(payload.EnemyName), payload.XP or 0, payload.Coins or 0,
				payload.LevelUp and " LEVEL UP" or "")
		end
	end)

	log:Info("ready")
end

return CombatController
