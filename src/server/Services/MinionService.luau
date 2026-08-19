--!strict
--[[
	MinionService — friendly units summoned by abilities.

	Necromancer's skeletons and the King's guard. Both are the same thing with
	different rosters, so there is one implementation and MinionConfig decides
	the composition.

	Rigs come from EnemyService.BuildRig rather than a second builder here. The
	AI is separate and simpler: enemies path toward a target and leash to a home
	point, minions path toward the nearest ENEMY and leash to their summoner.

	Minions are not enemies and are never registered as such. They cannot be
	targeted by CombatService, they do not appear in EnemyService.CountAlive,
	and killing one rewards nothing. That separation is deliberate — an ally
	that a player can accidentally attack, or that counts toward a wave being
	cleared, causes far more problems than it solves.

	They expire. Every squad has a lifetime and is cleaned up whether or not the
	summoner is still alive, so a disconnect mid-wave cannot leave a permanent
	army standing in the field.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local MinionConfig = require(Config.MinionConfig)
local Logger = require(Modules.Logger)

local EnemyService = require(script.Parent.EnemyService)

local log = Logger.new("MinionService")

local MinionService = {}

local FOLDER_NAME = "Minions"
local AI_INTERVAL = 0.25

type MinionRecord = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Definition: any,
	Owner: Player,
	ExpiresAt: number,
	LastAttackAt: number,
}

local minions: { [Model]: MinionRecord } = {}
local folder: Folder? = nil

--========================================================================
-- Targeting
--========================================================================

--[[
	Nearest living enemy to `position` within `range`.

	Walks the enemy folder rather than asking EnemyService for a list: there is
	no public enumerator, and adding one purely for minions would widen its API
	for a caller that only needs positions.
]]
local function nearestEnemy(position: Vector3, range: number): Model?
	local enemyFolder = Workspace:FindFirstChild("Enemies")
	if not enemyFolder then
		return nil
	end

	local closest: Model? = nil
	local closestDistance = range

	for _, model in ipairs(enemyFolder:GetChildren()) do
		if model:IsA("Model") then
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = model:FindFirstChildOfClass("Humanoid")

			if root and humanoid and humanoid.Health > 0 then
				local distance = (root.Position - position).Magnitude
				if distance < closestDistance then
					closest = model
					closestDistance = distance
				end
			end
		end
	end

	return closest
end

--========================================================================
-- AI
--========================================================================

local function stepMinion(record: MinionRecord, now: number)
	local humanoid = record.Humanoid
	if humanoid.Health <= 0 then
		return
	end

	local position = record.Root.Position
	local definition = record.Definition

	local owner = record.Owner
	local ownerRoot = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Leash to the summoner, not to a spawn point: a minion whose owner has
	-- moved up the field should follow rather than guard empty ground.
	if ownerRoot and (position - ownerRoot.Position).Magnitude > definition.LeashRange then
		humanoid:MoveTo(ownerRoot.Position)
		return
	end

	local target = nearestEnemy(position, definition.AggroRange)
	if not target then
		-- Nothing to fight: regroup on the summoner so the squad stays useful
		-- rather than scattering wherever the last kill happened.
		if ownerRoot and (position - ownerRoot.Position).Magnitude > 12 then
			humanoid:MoveTo(ownerRoot.Position)
		end
		return
	end

	local targetRoot = target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return
	end

	local distance = (targetRoot.Position - position).Magnitude

	if distance <= definition.AttackRange then
		humanoid:MoveTo(position)

		if now - record.LastAttackAt >= definition.AttackCooldown then
			record.LastAttackAt = now

			-- Credited to the owner, so a Necromancer's skeletons still earn
			-- their summoner the kill.
			EnemyService.Damage(target, definition.Damage, record.Owner)

			record.Root.CFrame = CFrame.lookAt(
				position,
				Vector3.new(targetRoot.Position.X, position.Y, targetRoot.Position.Z)
			)
		end
	else
		humanoid:MoveTo(targetRoot.Position)
	end
end

--========================================================================
-- Spawning
--========================================================================

local function despawn(record: MinionRecord)
	minions[record.Model] = nil
	if record.Model.Parent then
		record.Model:Destroy()
	end
end

--[[
	Summons a squad for `player`. Returns how many actually spawned.

	Placement is a ring around the summoner rather than a scatter, so a nine
	unit royal guard reads as a formation instead of a crowd landing on top of
	each other.
]]
function MinionService.SummonSquad(player: Player, abilityId: string, duration: number): number
	local squad = MinionConfig.GetSquad(abilityId)
	if not squad then
		return 0
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end

	local container = folder
	if not container then
		return 0
	end

	local origin = root.Position
	local expiresAt = os.clock() + duration
	local spawned = 0

	for index, minionId in ipairs(squad) do
		local definition = MinionConfig.Get(minionId)
		if not definition then
			continue
		end

		local ok, model, humanoid, minionRoot = pcall(function()
			return EnemyService.BuildRig(definition)
		end)

		if not ok or not model then
			log:Warn("failed to build %s", minionId)
			continue
		end

		local angle = (index / #squad) * math.pi * 2
		local offset = Vector3.new(
			math.cos(angle) * MinionConfig.SpawnRadius,
			3,
			math.sin(angle) * MinionConfig.SpawnRadius
		)

		model:PivotTo(CFrame.new(origin + offset))
		model.Parent = container

		local record: MinionRecord = {
			Model = model,
			Humanoid = humanoid,
			Root = minionRoot,
			Definition = definition,
			Owner = player,
			ExpiresAt = expiresAt,
			LastAttackAt = 0,
		}

		minions[model] = record
		spawned += 1

		humanoid.Died:Connect(function()
			task.delay(2, function()
				despawn(record)
			end)
		end)
	end

	log:Info("%s summoned %d for %s", player.Name, spawned, abilityId)
	return spawned
end

--[[ Removes every minion belonging to a player. ]]
function MinionService.ClearFor(player: Player)
	for _, record in pairs(minions) do
		if record.Owner == player then
			despawn(record)
		end
	end
end

function MinionService.CountFor(player: Player): number
	local count = 0
	for _, record in pairs(minions) do
		if record.Owner == player then
			count += 1
		end
	end
	return count
end

--========================================================================
-- Start
--========================================================================

local started = false

function MinionService.Start()
	if started then
		return
	end
	started = true

	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = FOLDER_NAME
	container.Parent = Workspace
	folder = container

	task.spawn(function()
		while true do
			task.wait(AI_INTERVAL)
			local now = os.clock()

			for model, record in pairs(minions) do
				if not model.Parent then
					minions[model] = nil
					continue
				end

				-- Expiry first: a minion whose time is up should not get one
				-- last swing in.
				if now >= record.ExpiresAt or not record.Owner.Parent then
					despawn(record)
					continue
				end

				local ok, err = pcall(stepMinion, record, now)
				if not ok then
					log:Warn("AI error on %s: %s", record.Definition.Id, tostring(err))
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		MinionService.ClearFor(player)
	end)

	log:Info("started")
end

return MinionService
