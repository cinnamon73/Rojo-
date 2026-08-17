--!strict
--[[
	Create — declarative instance construction.

		local frame = Create("Frame", {
			Size = UDim2.fromOffset(200, 60),
			BackgroundColor3 = Theme.Color.Panel,
		}, {
			Create("UICorner", { CornerRadius = Theme.Radius.Medium }),
			Create("TextLabel", { Text = "hello" }),
		})

	Children are parented AFTER properties are applied, so a child's layout
	never reads a half-configured parent. Parent is applied last for the same
	reason — an instance should be fully built before it enters the DataModel,
	which also avoids a frame of visible pop-in.

	The helpers below cover the patterns this game repeats constantly: rounded
	panels, padding, and buttons with real hover/press/disabled states.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

type Props = { [string]: any }

local function Create(className: string, props: Props?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent: Instance? = nil

	if props then
		for key, value in pairs(props) do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end

	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end

--========================================================================
-- Composition helpers
--========================================================================

local Helpers = {}

--[[ Rounded corners. ]]
function Helpers.Corner(radius: UDim?): UICorner
	return Create("UICorner", { CornerRadius = radius or Theme.Radius.Medium }) :: UICorner
end

--[[ Uniform or per-side padding, in pixels. ]]
function Helpers.Padding(all: number?, overrides: Props?): UIPadding
	local value = all or Theme.Spacing.M
	local props: Props = {
		PaddingTop = UDim.new(0, value),
		PaddingBottom = UDim.new(0, value),
		PaddingLeft = UDim.new(0, value),
		PaddingRight = UDim.new(0, value),
	}

	if overrides then
		for key, override in pairs(overrides) do
			props[key] = override
		end
	end

	return Create("UIPadding", props) :: UIPadding
end

function Helpers.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Create("UIStroke", {
		Color = color or Theme.Color.Divider,
		Thickness = thickness or Theme.Stroke.Thin,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}) :: UIStroke
end

function Helpers.ListLayout(direction: Enum.FillDirection?, padding: number?, alignment: Enum.HorizontalAlignment?): UIListLayout
	return Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or Theme.Spacing.S),
		HorizontalAlignment = alignment or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}) :: UIListLayout
end

--[[ A standard rounded surface. ]]
function Helpers.Panel(props: Props?, children: { Instance }?): Frame
	local merged: Props = {
		BackgroundColor3 = Theme.Color.Panel,
		BorderSizePixel = 0,
	}

	if props then
		for key, value in pairs(props) do
			merged[key] = value
		end
	end

	local kids = { Helpers.Corner(Theme.Radius.Large) }
	if children then
		for _, child in ipairs(children) do
			table.insert(kids, child)
		end
	end

	return Create("Frame", merged, kids) :: Frame
end

function Helpers.Label(text: string, props: Props?): TextLabel
	local merged: Props = {
		Text = text,
		Font = Theme.Font.Medium,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
	}

	if props then
		for key, value in pairs(props) do
			merged[key] = value
		end
	end

	return Create("TextLabel", merged) :: TextLabel
end

export type Button = {
	Instance: TextButton,
	SetEnabled: (enabled: boolean) -> (),
	Destroy: () -> (),
}

--[[
	A button with hover, press, and disabled states already wired.

	Returns a handle rather than the raw instance so callers can toggle the
	disabled state without re-implementing the visual treatment. Connections are
	tracked and dropped on Destroy so nothing leaks when a panel closes.
]]
function Helpers.Button(text: string, props: Props?, onClick: (() -> ())?): Button
	local baseColor = (props and props.BackgroundColor3) or Theme.Color.Accent
	local hoverColor = (props and props.HoverColor) or Theme.Color.AccentHover
	local pressColor = (props and props.PressColor) or Theme.Color.AccentPressed

	local merged: Props = {
		Text = text,
		Font = Theme.Font.Bold,
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Color.Text,
		BackgroundColor3 = baseColor,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(140, Theme.Layout.MinTouchPx),
	}

	if props then
		for key, value in pairs(props) do
			-- Strip our own pseudo-props before they hit the instance.
			if key ~= "HoverColor" and key ~= "PressColor" then
				merged[key] = value
			end
		end
	end

	local button = Create("TextButton", merged, {
		Helpers.Corner(Theme.Radius.Medium),
	}) :: TextButton

	local enabled = true
	local connections: { RBXScriptConnection } = {}

	local function tweenTo(color: Color3)
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = color }):Play()
	end

	table.insert(connections, button.MouseEnter:Connect(function()
		if enabled then
			tweenTo(hoverColor)
		end
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		if enabled then
			tweenTo(baseColor)
		end
	end))

	table.insert(connections, button.MouseButton1Down:Connect(function()
		if enabled then
			tweenTo(pressColor)
		end
	end))

	table.insert(connections, button.MouseButton1Up:Connect(function()
		if enabled then
			tweenTo(hoverColor)
		end
	end))

	table.insert(connections, button.Activated:Connect(function()
		if enabled and onClick then
			onClick()
		end
	end))

	local function setEnabled(value: boolean)
		enabled = value
		button.AutoButtonColor = false
		button.BackgroundColor3 = baseColor
		button.BackgroundTransparency = if value then 0 else Theme.Transparency.Disabled
		button.TextTransparency = if value then 0 else Theme.Transparency.Disabled
		button.Active = value
	end

	local function destroy()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		button:Destroy()
	end

	return {
		Instance = button,
		SetEnabled = setEnabled,
		Destroy = destroy,
	}
end

return {
	new = Create,
	Corner = Helpers.Corner,
	Padding = Helpers.Padding,
	Stroke = Helpers.Stroke,
	ListLayout = Helpers.ListLayout,
	Panel = Helpers.Panel,
	Label = Helpers.Label,
	Button = Helpers.Button,
}
