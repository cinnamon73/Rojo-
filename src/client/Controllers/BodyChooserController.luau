--!strict
--[[
	BodyChooserController — first-join body type selection.

	Shows once, when the profile has no BodyType set. The choice only swaps the
	body frame: head, face, hair and accessories are the player's own either
	way, which is worth saying on the screen so nobody thinks they are giving up
	their avatar.

	Deliberately blocking on first join — it is two large buttons and one
	decision, and letting a player start rolling before the body is settled
	means re-welding their equipment mid-session.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")
local UIModules = Modules:WaitForChild("UI")

local Create = require(UIModules.Create)
local Theme = require(UIModules.Theme)
local Remotes = require(Modules.Remotes)
local Logger = require(Modules.Logger)
local BodyConfig = require(Config.BodyConfig)

local log = Logger.new("BodyChooser")
local player = Players.LocalPlayer

local BodyChooserController = {}

local gui: ScreenGui? = nil
local client: any = nil
local shown = false
local pending: string? = nil
local cards: { [string]: Frame } = {}
local confirmButton: Create.Button? = nil

local function highlight(presetId: string?)
	pending = presetId

	for id, card in pairs(cards) do
		local selected = id == presetId
		local stroke = card:FindFirstChildOfClass("UIStroke")

		TweenService:Create(card, Theme.Tween.Fast, {
			BackgroundColor3 = if selected then Theme.Color.PanelHover else Theme.Color.Panel,
		}):Play()

		if stroke then
			stroke.Color = if selected then Theme.Color.Accent else Theme.Color.Divider
			stroke.Thickness = if selected then Theme.Stroke.Thick else Theme.Stroke.Thin
		end
	end

	if confirmButton then
		confirmButton.SetEnabled(presetId ~= nil)
	end
end

local function build()
	local screen = Create.new("ScreenGui", {
		Name = "BodyChooser",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		IgnoreGuiInset = true,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	Create.new("Frame", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Backdrop,
		BackgroundTransparency = 0.08,
		Parent = screen,
	})

	local main = Create.Panel({
		Name = "Panel",
		Size = UDim2.fromOffset(520, 372),
		Position = UDim2.new(0.5, -260, 0.5, -186),
		BackgroundColor3 = Theme.Color.Backdrop,
		Parent = screen,
	}, {
		Create.Padding(Theme.Spacing.XL),
	}) :: Frame

	Create.Label("CHOOSE YOUR BUILD", {
		Size = UDim2.new(1, 0, 0, 30),
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = main,
	})

	Create.Label("Your head, face, hair and accessories stay exactly as they are.\nThis only sets the body frame your armour fits to.", {
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 36),
		Font = Theme.Font.Regular,
		TextSize = Theme.TextSize.Small,
		TextColor3 = Theme.Color.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Parent = main,
	})

	local row = Create.new("Frame", {
		Name = "Options",
		Size = UDim2.new(1, 0, 0, 168),
		Position = UDim2.fromOffset(0, 82),
		BackgroundTransparency = 1,
		Parent = main,
	}, {
		Create.ListLayout(Enum.FillDirection.Horizontal, Theme.Spacing.M, Enum.HorizontalAlignment.Center),
	})

	for index, presetId in ipairs(BodyConfig.Order) do
		local preset = BodyConfig.Get(presetId)
		if preset then
			local card = Create.Panel({
				Name = presetId,
				Size = UDim2.fromOffset(214, 168),
				BackgroundColor3 = Theme.Color.Panel,
				LayoutOrder = index,
				Parent = row,
			}, {
				Create.Label(preset.Name, {
					Size = UDim2.new(1, -24, 0, 26),
					Position = UDim2.fromOffset(12, 18),
					Font = Theme.Font.Bold,
					TextSize = Theme.TextSize.Large,
					TextXAlignment = Enum.TextXAlignment.Center,
				}),
				Create.Label(preset.Description, {
					Size = UDim2.new(1, -24, 0, 40),
					Position = UDim2.fromOffset(12, 50),
					Font = Theme.Font.Regular,
					TextSize = Theme.TextSize.Small,
					TextColor3 = Theme.Color.TextMuted,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true,
				}),
			}) :: Frame

			Create.Stroke(Theme.Color.Divider, Theme.Stroke.Thin, 0).Parent = card

			local hit = Create.new("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				ZIndex = 5,
				Parent = card,
			}) :: TextButton

			hit.Activated:Connect(function()
				highlight(presetId)
			end)

			cards[presetId] = card
		end
	end

	local confirm = Create.Button("CONFIRM", {
		Size = UDim2.fromOffset(196, Theme.Layout.MinTouchPx + 6),
		Position = UDim2.new(0.5, -98, 1, -(Theme.Layout.MinTouchPx + 6)),
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		Parent = main,
	}, function()
		if not pending then
			return
		end

		local remote = Remotes.Get("BodyTypeRequest") :: RemoteFunction
		local result = remote:InvokeServer({ BodyType = pending })

		if type(result) == "table" and result.Success then
			BodyChooserController.Hide()
		else
			log:Warn("body type refused: %s", tostring(type(result) == "table" and result.Error or result))
		end
	end)

	confirm.Instance.Parent = main
	confirmButton = confirm
	confirm.SetEnabled(false)

	gui = screen
end

function BodyChooserController.Show()
	if not gui or shown then
		return
	end

	local screen = gui :: ScreenGui
	shown = true
	screen.Enabled = true
	highlight(nil)
end

function BodyChooserController.Hide()
	if not gui then
		return
	end

	local screen = gui :: ScreenGui
	screen.Enabled = false
end

local started = false

function BodyChooserController.Start(clientState: any)
	if started then
		return
	end
	started = true

	client = clientState

	local existing = player:WaitForChild("PlayerGui"):FindFirstChild("BodyChooser")
	if existing then
		existing:Destroy()
	end

	build()

	local function check(profile: any)
		if not profile or not profile.Character then
			return
		end

		if profile.Character.BodyType == "" then
			BodyChooserController.Show()
		end
	end

	client.ProfileChanged:Connect(check)
	if client.Profile then
		check(client.Profile)
	end

	log:Info("ready (%d presets)", #BodyConfig.Order)
end

return BodyChooserController
