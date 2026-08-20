--!strict
--[[
	ClassSelectController — the join screen.

	You click Play and this is what you see: a full-screen menu, one card per
	class, each card a banner with the class name and a mannequin underneath
	wearing the class colour and holding its actual weapon. Picking a card is
	what spawns you — the server has CharacterAutoLoads off, so until a class
	is confirmed there is no character at all.

	The mannequins are built from parts in ViewportFrames, no uploaded assets:
	a blocky figure tinted with the class ThemeColor, holding the same model
	WeaponModels builds for the real character. What you see on the card is
	genuinely what you will hold.

	There is no unlock state to draw any more — no levelling, no tiers-as-gates.
	The one exception is the King, whose card carries a PAID tag; the server
	refuses the pick without the gamepass.

	The menu also reopens from the "Class" nav button mid-session. Switching
	then applies on your next spawn (a server rule — swapping mid-fight would
	dodge a killing blow), and the Close button only exists in that mode: on
	first join there is nothing to close down to.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local WeaponModels = require(Modules.WeaponModels)
local ClassConfig = require(Config.ClassConfig)
local WeaponConfig = require(Config.WeaponConfig)

local UIController = require(script.Parent.UIController)

local log = Logger.new("ClassSelectController")
local player = Players.LocalPlayer

local ClassSelectController = {}

local CARD_WIDTH = 200
local BANNER_HEIGHT = 38
local VIEWPORT_HEIGHT = 212
local CARD_HEIGHT = BANNER_HEIGHT + VIEWPORT_HEIGHT

--[[ How many times a pick retries while the profile is still loading. ]]
local PICK_RETRIES = 6
local PICK_RETRY_DELAY = 1

local client: any = nil
local screenGui: ScreenGui? = nil
local grid: Frame? = nil
local closeButton: Instance? = nil
local open = false
local picking = false

--========================================================================
-- Mannequin
--========================================================================

local function darker(color: Color3, factor: number): Color3
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

local function mannequinPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--[[
	A blocky figure in the class colours, weapon in its right hand.

	Proportions are eyeballed R15-ish. Nothing here is animated — a viewport
	has no physics — so every part is placed by CFrame and stays put.
]]
local function buildMannequin(definition: ClassConfig.ClassDefinition, parent: Instance)
	local skin = Color3.fromRGB(232, 190, 152)
	local outfit = definition.ThemeColor
	local legs = darker(definition.ThemeColor, 0.65)

	local model = Instance.new("Model")
	model.Name = definition.Id

	mannequinPart("Torso", Vector3.new(2, 2.2, 1.1), CFrame.new(0, 3.1, 0), outfit, model)
	mannequinPart("Head", Vector3.new(1.25, 1.25, 1.25), CFrame.new(0, 4.8, 0), skin, model)

	mannequinPart("LegL", Vector3.new(0.85, 2, 1), CFrame.new(-0.5, 1, 0), legs, model)
	mannequinPart("LegR", Vector3.new(0.85, 2, 1), CFrame.new(0.5, 1, 0), legs, model)

	-- Left arm hangs; right arm angles forward toward the weapon grip.
	mannequinPart("ArmL", Vector3.new(0.8, 2, 0.9), CFrame.new(-1.45, 3.1, 0), skin, model)
	mannequinPart(
		"ArmR",
		Vector3.new(0.8, 2, 0.9),
		CFrame.new(1.5, 3.15, -0.25) * CFrame.Angles(math.rad(-24), 0, math.rad(-10)),
		skin,
		model
	)

	-- The mannequin holds whatever item the class starts with.
	local item = WeaponConfig.Get(definition.StartingWeapon)
	local weapon = item and WeaponModels.BuildFromItem(item, item.Id .. "Weapon")

	if weapon then
		-- Roughly where the right hand ends up, blade tilted outward so long
		-- weapons clear the head and short ones stay visible.
		weapon:PivotTo(CFrame.new(1.95, 3.0, -0.55) * CFrame.Angles(math.rad(-18), 0, math.rad(-14)))
		weapon.Parent = model
	end

	model.Parent = parent
end

local function makeViewport(definition: ClassConfig.ClassDefinition, parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Position = UDim2.fromOffset(0, BANNER_HEIGHT)
	viewport.Size = UDim2.new(1, 0, 0, VIEWPORT_HEIGHT)
	viewport.BackgroundColor3 = Theme.Color.Backdrop
	viewport.BackgroundTransparency = 0.15
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(140, 140, 155)
	viewport.LightColor = Color3.fromRGB(255, 248, 235)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	viewport.Parent = parent

	buildMannequin(definition, viewport)

	--[[
		Slightly orbited so the weapon side faces the viewer — a dead-on front
		view hides the weapon behind the arm, and the weapon is half of what
		the card is communicating.
	]]
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(2.6, 3.6, -6.4), Vector3.new(0, 2.9, 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	return viewport
end

--========================================================================
-- Picking
--========================================================================

--[[
	Confirms a class. Retries while the profile is still loading server-side,
	because on a first join the player can click faster than DataStores answer,
	and failing their very first interaction with the game is the worst
	possible place to be brittle.
]]
local function pick(definition: ClassConfig.ClassDefinition)
	if picking then
		return
	end
	picking = true

	task.spawn(function()
		local remote = Remotes.Get("ClassSelectRequest") :: RemoteFunction

		for attempt = 1, PICK_RETRIES do
			local ok, result = pcall(function()
				return remote:InvokeServer({ ClassId = definition.Id })
			end)

			if ok and type(result) == "table" and result.Success then
				ClassSelectController.SetOpen(false)
				picking = false
				return
			end

			local errorId = if ok and type(result) == "table" then result.Error else "Invoke"

			if errorId ~= "ProfileNotLoaded" then
				-- A real refusal (gamepass, unknown class): stop retrying.
				log:Warn("class select refused: %s", tostring(errorId))
				picking = false
				return
			end

			task.wait(PICK_RETRY_DELAY)
		end

		log:Warn("profile never loaded after %d attempts", PICK_RETRIES)
		picking = false
	end)
end

--========================================================================
-- Cards
--========================================================================

local function makeCard(definition: ClassConfig.ClassDefinition, order: number, parent: Instance)
	local profile = client and client.Profile
	local isCurrent = profile ~= nil and profile.Class == definition.Id and player.Character ~= nil

	local card = Create.new("TextButton", {
		Name = definition.Id,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = Theme.Color.Panel,
		AutoButtonColor = false,
		ClipsDescendants = true,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}, {
		Create.new("UICorner", { CornerRadius = Theme.Radius.Medium }),
		Create.new("UIStroke", {
			Color = if isCurrent then Theme.Color.Positive else darker(definition.ThemeColor, 1.0),
			Thickness = if isCurrent then Theme.Stroke.Thick else Theme.Stroke.Thin,
			Transparency = 0.15,
		}),
	}) :: TextButton

	-- The banner: class colour, class name. This IS the card's identity.
	local banner = Create.new("Frame", {
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, BANNER_HEIGHT),
		BackgroundColor3 = definition.ThemeColor,
		BorderSizePixel = 0,
		Parent = card,
	}, {
		Create.new("TextLabel", {
			Name = "Title",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.Large,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Text = string.upper(definition.Name),
		}),
	}) :: Frame

	if definition.RequiresGamepass then
		Create.new("TextLabel", {
			Name = "Paid",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 4),
			Size = UDim2.fromOffset(44, 16),
			BackgroundColor3 = Theme.Color.Backdrop,
			BackgroundTransparency = 0.25,
			Font = Theme.Font.Bold,
			TextSize = Theme.TextSize.Tiny,
			TextColor3 = Theme.Color.Coins,
			Text = "PAID",
			Parent = banner,
		}, {
			Create.new("UICorner", { CornerRadius = Theme.Radius.Pill }),
		})
	end

	makeViewport(definition, card)

	card.Activated:Connect(function()
		pick(definition)
	end)
end

--========================================================================
-- Render / build
--========================================================================

function ClassSelectController.Render()
	local frame = grid
	if not frame then
		return
	end

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	for order, classId in ipairs(ClassConfig.Order) do
		local definition = ClassConfig.Get(classId)
		if definition then
			makeCard(definition, order, frame)
		end
	end

	-- Close only exists mid-session. On first join there is no character and
	-- nothing underneath the menu to return to.
	if closeButton then
		(closeButton :: any).Visible = player.Character ~= nil
	end
end

local function build(): ScreenGui
	local gui = Create.new("ScreenGui", {
		Name = "ClassSelect",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 12,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	-- Opaque: on join there is nothing behind it worth seeing (no character
	-- exists yet), and an empty world showing through reads as a bug.
	local root = Create.new("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Backdrop,
		BorderSizePixel = 0,
		Parent = gui,
	}) :: Frame

	Create.Label("CHOOSE YOUR CLASS", {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 36),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Display,
		TextColor3 = Theme.Color.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})

	grid = Create.new("Frame", {
		Name = "Grid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 24),
		Size = UDim2.fromOffset(CARD_WIDTH * 4 + Theme.Spacing.M * 3, CARD_HEIGHT * 2 + Theme.Spacing.M),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		Create.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			CellPadding = UDim2.fromOffset(Theme.Spacing.M, Theme.Spacing.M),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		-- Shrinks the whole grid on short screens rather than clipping row two.
		Create.new("UIScale", { Name = "Fit", Scale = 1 }),
	}) :: Frame

	local close = Create.Button("CLOSE", {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(160, Theme.Layout.MinTouchPx),
		BackgroundColor3 = Theme.Color.PanelRaised,
		HoverColor = Theme.Color.PanelHover,
		PressColor = Theme.Color.Panel,
		Parent = root,
	}, function()
		ClassSelectController.SetOpen(false)
	end)

	closeButton = if close and (close :: any).Instance then (close :: any).Instance else nil

	-- Fit the grid to the viewport.
	local camera = workspace.CurrentCamera
	local fit = (grid :: Frame):FindFirstChild("Fit") :: UIScale?

	local function refit()
		if not fit or not camera then
			return
		end
		local available = camera.ViewportSize.Y - 140
		local needed = CARD_HEIGHT * 2 + Theme.Spacing.M
		fit.Scale = math.clamp(available / needed, 0.55, 1)
	end

	refit()
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	end

	return gui
end

--========================================================================
-- Open / close
--========================================================================

function ClassSelectController.SetOpen(value: boolean)
	open = value

	if screenGui then
		screenGui.Enabled = value
	end

	if value then
		ClassSelectController.Render()
	end
end

function ClassSelectController.Start(clientState: any)
	client = clientState

	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("ClassSelect")
	if existing then
		existing:Destroy()
	end

	screenGui = build()

	UIController.NavActivated:Connect(function(name: string)
		if name == "Class" then
			ClassSelectController.SetOpen(not open)
		end
	end)

	client.ProfileChanged:Connect(function()
		if open then
			ClassSelectController.Render()
		end
	end)

	-- THE JOIN FLOW: the menu is up from the first frame. There is no
	-- character yet — picking a card is what asks the server to spawn one.
	ClassSelectController.SetOpen(true)

	log:Info("ready (%d classes)", #ClassConfig.Order)
end

return ClassSelectController
