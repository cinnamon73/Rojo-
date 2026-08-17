--!strict
--[[
	EnemyService — spawning, AI, damage, death, and rewards.

	Two decisions worth knowing about:

	ONE SHARED AI LOOP. Every living enemy is stepped from a single timer rather
	than each running its own coroutine or Heartbeat connection. Thirty enemies
	is then one timer instead of thirty, and the per-tick cost is a distance
	check per enemy. Enemies with no player anywhere near them are skipped
	before any real work happens, so an empty field costs almost nothing.

	SPAWN MARKERS ARE THE SOURCE OF TRUTH. Population comes from parts placed in
	the world carrying EnemyId / Radius / MaxAlive attributes. Adding enemies to
	a zone is level design, not code — and it means the map and the spawner can
	never disagree about where things live.

	Damage is applied here and nowhere else. CombatService decides how much; this
	decides what it does.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local EnemyConfig = require(Config.EnemyConfig)
local Logger = require(Modules.Logger)
local Signal = require(Modules.Signal)

local log = Logger.new("EnemyService")

local EnemyService = {}

--[[ Fires (player, enemyDefinition, enemyModel) when a player lands a kill. ]]
EnemyService.EnemyKilled = Signal.new()

local ENEMY_TAG = "RNGA_Enemy"
local AI_INTERVAL = 0.2

type EnemyRecord = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Definition: EnemyConfig.EnemyDefinition,
	Marker: BasePart,
	HomePosition: Vector3,
	State: string,
	Target: Player?,
	LastAttackAt: number,
	-- Whoever dealt the most damage gets the reward; prevents kill-stealing
	-- from feeling arbitrary without needing full threat tables.
	DamageBy: { [Player]: number },
}

local enemies: { [Model]: EnemyRecord } = {}
local markerCounts: { [BasePart]: number } = {}
local folder: Folder? = nil

--========================================================================
-- Rig building
--========================================================================

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	b.CFrame = a.CFrame * offset
	local motor = Instance.new("Weld")
	motor.Part0 = a
	motor.Part1 = b
	motor.C0 = offset
	motor.Parent = a
end

--[[
	Assembles a placeholder rig. A real model replaces this wholesale by setting
	ModelId on the definition — the AI only ever touches Humanoid and the root.
]]
local function buildRig(definition: EnemyConfig.EnemyDefinition): (Model, Humanoid, BasePart)
	local appearance = definition.Appearance
	local scale = appearance.Scale

	local model = Instance.new("Model")
	model.Name = definition.Id

	local root = makePart("HumanoidRootPart", Vector3.new(2, 2, 1) * scale, appearance.BodyColor, appearance.Material, model)
	root.Transparency = 1
	root.CanCollide = false

	if appearance.Build == "Blob" then
		local body = makePart("Body", Vector3.new(3.4, 2.8, 3.4) * scale, appearance.BodyColor, appearance.Material, model)
		body.Shape = Enum.PartType.Ball
		weld(root, body, CFrame.new(0, -0.2 * scale, 0))

		local eyeL = makePart("EyeL", Vector3.new(0.5, 0.5, 0.5) * scale, appearance.AccentColor, Enum.Material.Neon, model)
		eyeL.Shape = Enum.PartType.Ball
		weld(root, eyeL, CFrame.new(-0.7 * scale, 0.3 * scale, -1.5 * scale))
		local eyeR = makePart("EyeR", Vector3.new(0.5, 0.5, 0.5) * scale, appearance.AccentColor, Enum.Material.Neon, model)
		eyeR.Shape = Enum.PartType.Ball
		weld(root, eyeR, CFrame.new(0.7 * scale, 0.3 * scale, -1.5 * scale))

	elseif appearance.Build == "Quadruped" then
		local body = makePart("Body", Vector3.new(1.8, 1.6, 4.2) * scale, appearance.BodyColor, appearance.Material, model)
		weld(root, body, CFrame.new(0, 0, 0))
		local head = makePart("Head", Vector3.new(1.4, 1.3, 1.6) * scale, appearance.BodyColor, appearance.Material, model)
		weld(root, head, CFrame.new(0, 0.5 * scale, -2.6 * scale))
		local snout = makePart("Snout", Vector3.new(0.7, 0.6, 0.9) * scale, appearance.AccentColor, appearance.Material, model)
		weld(root, snout, CFrame.new(0, 0.25 * scale, -3.4 * scale))
		for i, x in ipairs({ -0.7, 0.7 }) do
			for j, z in ipairs({ -1.4, 1.4 }) do
				local leg = makePart("Leg" .. i .. j, Vector3.new(0.5, 1.8, 0.5) * scale, appearance.AccentColor, appearance.Material, model)
				weld(root, leg, CFrame.new(x * scale, -1.6 * scale, z * scale))
			end
		end

	else -- Biped
		local torso = makePart("Torso", Vector3.new(2, 2.2, 1.1) * scale, appearance.BodyColor, appearance.Material, model)
		weld(root, torso, CFrame.new(0, 0, 0))
		local head = makePart("Head", Vector3.new(1.5, 1.4, 1.4) * scale, appearance.BodyColor, appearance.Material, model)
		weld(root, head, CFrame.new(0, 1.9 * scale, 0))
		local eyeL = makePart("EyeL", Vector3.new(0.3, 0.3, 0.3) * scale, Color3.fromRGB(255, 220, 120), Enum.Material.Neon, model)
		weld(root, eyeL, CFrame.new(-0.35 * scale, 2.0 * scale, -0.72 * scale))
		local eyeR = makePart("EyeR", Vector3.new(0.3, 0.3, 0.3) * scale, Color3.fromRGB(255, 220, 120), Enum.Material.Neon, model)
		weld(root, eyeR, CFrame.new(0.35 * scale, 2.0 * scale, -0.72 * scale))
		for i, x in ipairs({ -1.4, 1.4 }) do
			local arm = makePart("Arm" .. i, Vector3.new(0.7, 2, 0.7) * scale, appearance.AccentColor, appearance.Material, model)
			weld(root, arm, CFrame.new(x * scale, 0, 0))
		end
		for i, x in ipairs({ -0.5, 0.5 }) do
			local leg = makePart("Leg" .. i, Vector3.new(0.8, 2, 0.8) * scale, appearance.AccentColor, appearance.Material, model)
			weld(root, leg, CFrame.new(x * scale, -2.1 * scale, 0))
		end
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = descendant == root
			descendant.Massless = descendant ~= root
		end
	end
	root.CanCollide = true

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = definition.Health
	humanoid.Health = definition.Health
	humanoid.WalkSpeed = definition.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	model.PrimaryPart = root

	-- Name and health readout above the enemy.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(140, 34)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4 * scale, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 90
	billboard.Adornee = root
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(240, 243, 250)
	label.TextStrokeTransparency = 0.4
	label.Text = string.format("%s  Lv%d", definition.Name, definition.Level)
	label.Parent = billboard

	local track = Instance.new("Frame")
	track.Name = "HealthTrack"
	track.Size = UDim2.new(1, -12, 0, 5)
	track.Position = UDim2.new(0, 6, 0, 20)
	track.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	track.BorderSizePixel = 0
	track.Parent = billboard
	Instance.new("UICorner").Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(226, 76, 84)
	fill.BorderSizePixel = 0
	fill.Parent = track
	Instance.new("UICorner").Parent = fill

	return model, humanoid, root
end

local function updateHealthBar(record: EnemyRecord)
	local billboard = record.Root:FindFirstChild("Info")
	if not billboard then
		return
	end

	local fill = billboard:FindFirstChild("HealthTrack") and billboard.HealthTrack:FindFirstChild("Fill")
	if fill then
		local ratio = if record.Humanoid.MaxHealth > 0 then record.Humanoid.Health / record.Humanoid.MaxHealth else 0
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	end
end

--========================================================================
-- Spawning
--========================================================================

local function spawnAt(marker: BasePart, definition: EnemyConfig.EnemyDefinition)
	local radius = marker:GetAttribute("Radius") or 20
	local angle = math.random() * math.pi * 2
	local distance = math.random() * radius

	local position = marker.Position + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)

	local model, humanoid, root = buildRig(definition)
	model:PivotTo(CFrame.new(position))
	model.Parent = folder

	CollectionService:AddTag(model, ENEMY_TAG)

	local record: EnemyRecord = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Definition = definition,
		Marker = marker,
		HomePosition = position,
		State = "Idle",
		Target = nil,
		LastAttackAt = 0,
		DamageBy = {},
	}

	enemies[model] = record
	markerCounts[marker] = (markerCounts[marker] or 0) + 1

	humanoid.Died:Connect(function()
		EnemyService.HandleDeath(record)
	end)
end

local function populate()
	local zone = Workspace:FindFirstChild("World")
	if not zone then
		return
	end

	for _, marker in ipairs(zone:GetDescendants()) do
		if marker:IsA("BasePart") then
			local enemyId = marker:GetAttribute("EnemyId")
			if type(enemyId) == "string" then
				local definition = EnemyConfig.Get(enemyId)
				local maxAlive = marker:GetAttribute("MaxAlive") or 2

				if definition and (markerCounts[marker] or 0) < maxAlive then
					spawnAt(marker, definition)
				end
			end
		end
	end
end

--========================================================================
-- Damage and death
--========================================================================

--[[
	Applies damage from `source` and returns the amount actually dealt after
	the enemy's defense. Returns 0 if the enemy is already dead or unknown.
]]
function EnemyService.Damage(model: Model, rawDamage: number, source: Player?): number
	local record = enemies[model]
	if not record or record.Humanoid.Health <= 0 then
		return 0
	end

	local dealt = EnemyConfig.ApplyDefense(rawDamage, record.Definition.Defense)
	record.Humanoid.Health = math.max(record.Humanoid.Health - dealt, 0)

	if source then
		record.DamageBy[source] = (record.DamageBy[source] or 0) + dealt

		-- Taking a hit pulls aggro to whoever landed it.
		if record.State == "Idle" then
			record.Target = source
			record.State = "Chase"
		end
	end

	updateHealthBar(record)
	return dealt
end

function EnemyService.HandleDeath(record: EnemyRecord)
	if not enemies[record.Model] then
		return
	end

	-- Reward whoever dealt the most damage.
	local best: Player? = nil
	local bestDamage = 0
	for player, amount in pairs(record.DamageBy) do
		if amount > bestDamage and player.Parent then
			best = player
			bestDamage = amount
		end
	end

	if best then
		EnemyService.EnemyKilled:Fire(best, record.Definition, record.Model)
	end

	enemies[record.Model] = nil
	markerCounts[record.Marker] = math.max((markerCounts[record.Marker] or 1) - 1, 0)

	local model = record.Model
	local marker = record.Marker
	local definition = record.Definition

	task.delay(2, function()
		if model.Parent then
			model:Destroy()
		end
	end)

	task.delay(definition.RespawnSeconds, function()
		if folder and marker.Parent then
			local maxAlive = marker:GetAttribute("MaxAlive") or 2
			if (markerCounts[marker] or 0) < maxAlive then
				spawnAt(marker, definition)
			end
		end
	end)
end

--[[ The record for a model, or nil. Used by CombatService to validate targets. ]]
function EnemyService.GetRecord(model: Model): EnemyRecord?
	return enemies[model]
end

function EnemyService.IsEnemy(model: Instance): boolean
	return model:IsA("Model") and enemies[model :: Model] ~= nil
end

function EnemyService.CountAlive(): number
	local count = 0
	for _ in pairs(enemies) do
		count += 1
	end
	return count
end

--========================================================================
-- AI
--========================================================================

local function nearestPlayer(position: Vector3, range: number): (Player?, number)
	local closest: Player? = nil
	local closestDistance = range

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - position).Magnitude
			if distance < closestDistance then
				closest = player
				closestDistance = distance
			end
		end
	end

	return closest, closestDistance
end

local function stepEnemy(record: EnemyRecord, now: number)
	local humanoid = record.Humanoid
	if humanoid.Health <= 0 then
		return
	end

	local position = record.Root.Position
	local definition = record.Definition

	if record.State == "Idle" then
		local player, _ = nearestPlayer(position, definition.AggroRange)
		if player then
			record.Target = player
			record.State = "Chase"
		end
		return
	end

	-- Leash: too far from home, go back and drop aggro.
	if (position - record.HomePosition).Magnitude > definition.LeashRange then
		record.State = "Return"
		record.Target = nil
	end

	if record.State == "Return" then
		humanoid:MoveTo(record.HomePosition)
		if (position - record.HomePosition).Magnitude < 6 then
			record.State = "Idle"
			-- Heal on leash so a player cannot whittle enemies down by kiting.
			humanoid.Health = humanoid.MaxHealth
			record.DamageBy = {}
			updateHealthBar(record)
		end
		return
	end

	local target = record.Target
	local character = target and target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
		record.State = "Return"
		record.Target = nil
		return
	end

	local toTarget = (targetRoot :: BasePart).Position - position
	local distance = toTarget.Magnitude

	if distance > definition.AggroRange * 1.6 then
		record.State = "Return"
		record.Target = nil
		return
	end

	if distance <= definition.AttackRange then
		-- In range: stop and swing on cooldown.
		humanoid:MoveTo(position)

		if now - record.LastAttackAt >= definition.AttackCooldown then
			record.LastAttackAt = now
			targetHumanoid:TakeDamage(definition.Damage)

			-- Face the target so the hit reads.
			record.Root.CFrame = CFrame.lookAt(position, Vector3.new(targetRoot.Position.X, position.Y, targetRoot.Position.Z))
		end
	else
		humanoid:MoveTo((targetRoot :: BasePart).Position)
	end
end

local function startAI()
	task.spawn(function()
		while true do
			task.wait(AI_INTERVAL)

			local now = os.clock()
			local players = Players:GetPlayers()

			if #players > 0 then
				for model, record in pairs(enemies) do
					if not model.Parent then
						enemies[model] = nil
						continue
					end

					local ok, err = pcall(stepEnemy, record, now)
					if not ok then
						log:Warn("AI error on %s: %s", record.Definition.Id, tostring(err))
					end
				end
			end
		end
	end)
end

--========================================================================
-- Start
--========================================================================

local started = false

function EnemyService.Start()
	if started then
		return
	end
	started = true

	local existing = Workspace:FindFirstChild("Enemies")
	if existing then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = "Enemies"
	container.Parent = Workspace
	folder = container

	populate()
	startAI()

	-- Top up population periodically in case a marker was added at runtime.
	task.spawn(function()
		while true do
			task.wait(15)
			populate()
		end
	end)

	log:Info("started (%d definitions, %d spawned)", EnemyConfig.Count(), EnemyService.CountAlive())
end

return EnemyService
