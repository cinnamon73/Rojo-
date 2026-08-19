--!strict
--[[
	AbilityController — the ability button, its key bind, and the cooldown dial.

	Sends nothing but "I pressed it", plus an aim point for the grenade. Whether
	the cooldown is up, what the ability does and how long it lasts are all
	decided server-side; this only asks and then draws the wait.

	THE COOLDOWN SHOWN HERE IS A PREDICTION.
	----------------------------------------
	It starts locally on press using the duration in ClassConfig, because the
	server does not push a cooldown event and adding one would be a remote per
	press for something the client can already work out. The consequence is that
	a refused press (dead, no character) still draws a cooldown that the server
	never started. That is the safe direction to be wrong in — it under-promises
	— but it is a prediction, not the truth.

	Bound through ContextActionService so keyboard, touch and gamepad all come
	from one definition, matching how CombatController binds attacking.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local ClassConfig = require(Config.ClassConfig)

local log = Logger.new("AbilityController")
local player = Players.LocalPlayer

local AbilityController = {}

local ACTION_NAME = "RNGA_Ability"
local BUTTON_SIZE = 76

local client: any = nil
local screenGui: ScreenGui? = nil
local button: TextButton? = nil
local label: TextLabel? = nil
local sweep: Frame? = nil

local readyAt = 0
local currentCooldown = 0

--========================================================================
-- Class lookup
--========================================================================

local function currentAbility(): ClassConfig.Ability?
	local profile = client and client.Profile
	local definition = ClassConfig.Get(profile and profile.Class) or ClassConfig.Get(ClassConfig.Default)
	return if definition then definition.Ability else nil
end

--========================================================================
-- Firing
--========================================================================

local function press()
	local ability = currentAbility()
	if not ability then
		return
	end

	if os.clock() < readyAt then
		return
	end

	--[[
		Aim point for the grenade. Sent for every ability rather than only the
		Musketeer's, because the client does not decide which ability it has —
		the server ignores it for the other seven.
	]]
	local mouse = player:GetMouse()
	local payload = { Position = mouse.Hit and mouse.Hit.Position or nil }

	local remote = Remotes.Get("AbilityRequest") :: RemoteEvent
	remote:FireServer(payload)

	readyAt = os.clock() + ability.Cooldown
	currentCooldown = ability.Cooldown
end

--========================================================================
-- Build
--========================================================================

local function build(): ScreenGui
	local gui = Create.new("ScreenGui", {
		Name = "AbilityHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 4,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	--[[
		Bottom centre, where the ROLL button used to be. That spot is muscle
		memory for anyone who played the old build, and the ability is now the
		one thing worth pressing there.
	]]
	local frame = Create.new("TextButton", {
		Name = "Ability",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Layout.HUDMargin - 56),
		Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		BackgroundColor3 = Theme.Color.PanelRaised,
		AutoButtonColor = false,
		Text = "",
		Parent = gui,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Large }),
		Create.new("UIStroke", {
			Name = "Ring",
			Color = Theme.Color.Accent,
			Thickness = Theme.Stroke.Medium,
			Transparency = 0.2,
		}),
	}) :: TextButton

	-- Cooldown sweep: a bar that drains from full to empty across the wait.
	-- Clipped by the parent's corner so it reads as part of the button.
	sweep = Create.new("Frame", {
		Name = "Sweep",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Theme.Color.Accent,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		Parent = frame,
	}) :: Frame

	label = Create.new("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.Text,
		TextWrapped = true,
		Text = "",
		Parent = frame,
	}) :: TextLabel

	frame.Activated:Connect(press)
	button = frame

	return gui
end

--========================================================================
-- Render
--========================================================================

local function render()
	local frame = button
	local text = label
	local bar = sweep

	if not frame or not text or not bar then
		return
	end

	local ability = currentAbility()
	if not ability then
		frame.Visible = false
		return
	end

	frame.Visible = true

	local remaining = readyAt - os.clock()

	if remaining > 0 and currentCooldown > 0 then
		bar.Size = UDim2.fromScale(1, math.clamp(remaining / currentCooldown, 0, 1))
		text.Text = string.format("%.0f", math.ceil(remaining))
		text.TextColor3 = Theme.Color.TextMuted
	else
		bar.Size = UDim2.fromScale(1, 0)
		text.Text = ability.Name
		text.TextColor3 = Theme.Color.Text
	end
end

--========================================================================
-- Start
--========================================================================

function AbilityController.Start(clientState: any)
	client = clientState

	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("AbilityHud")
	if existing then
		existing:Destroy()
	end

	screenGui = build()

	ContextActionService:BindAction(ACTION_NAME, function(_, state)
		if state == Enum.UserInputState.Begin then
			press()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)

	RunService.RenderStepped:Connect(render)

	-- Switching class changes the ability, so the label has to follow. The
	-- cooldown is deliberately NOT reset: a class swap applies on the next
	-- spawn, so the old ability's timer is still the honest one until then.
	client.ProfileChanged:Connect(render)

	log:Info("ready")
end

return AbilityController
