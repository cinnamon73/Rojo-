--!strict
--[[
	EnemyAnimationController — drives the articulated enemy rigs.

	WHY THIS IS ON THE CLIENT. Posing a rig means writing ~18 joint C0s every
	frame. Doing that on the server replicates every one of them to every
	player, for every enemy alive. Driving it locally costs nothing across the
	network: the server replicates only the model's position and a couple of
	attributes, and each client animates what it can see.

	The server does not tell us to walk. We read the Humanoid's own velocity,
	so an enemy chasing a player animates without any extra message. The server
	only bumps a counter for things velocity cannot imply — a swing, a flinch.

	Enemies opt in by carrying a `Rig` attribute (set in EnemyService). Anything
	without one is left alone, so the older welded bodies are unaffected.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local EnemyAnimation = require(Modules.EnemyAnimation)

local EnemyAnimationController = {}

-- Beyond this there is no point posing anything; the enemy is a few pixels.
local ANIMATE_DISTANCE = 220
-- Squared, so the per-frame check avoids a square root per enemy.
local ANIMATE_DISTANCE_SQ = ANIMATE_DISTANCE * ANIMATE_DISTANCE
-- Above this speed the walk cycle plays; below it, idle.
local WALK_THRESHOLD = 0.6

type Rigged = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Joints: { [string]: Motor6D },
	FootL: BasePart?,
	FootR: BasePart?,
	Phase: number,
	Drop: number,
	-- Time remaining on a one-shot (attack, flinch), and which one.
	OneShot: string?,
	OneShotT: number,
	OneShotLen: number,
	-- Last counter values seen from the server; a rise means "play it now".
	LastAttack: number,
	LastFlinch: number,
}

local tracked: { [Model]: Rigged } = {}
local connection: RBXScriptConnection? = nil

local function collect(model: Model): Rigged?
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return nil
	end
	local joints: { [string]: Motor6D } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d:GetAttribute("RestC0") ~= nil then
			joints[d.Name] = d
		end
	end
	if next(joints) == nil then
		return nil
	end
	return {
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Joints = joints,
		FootL = model:FindFirstChild("FootL") :: BasePart?,
		FootR = model:FindFirstChild("FootR") :: BasePart?,
		Phase = math.random() * 10, -- desync identical enemies so they do not march in step
		Drop = 0,
		OneShot = nil,
		OneShotT = 0,
		OneShotLen = 0,
		-- Seed from whatever has already replicated, so a goblin that swung
		-- before we started tracking it does not replay that swing on sight.
		LastAttack = (model:GetAttribute("AttackSeq") :: number?) or 0,
		LastFlinch = (model:GetAttribute("FlinchSeq") :: number?) or 0,
	}
end

local function add(model: Instance)
	if not model:IsA("Model") or tracked[model] then
		return
	end
	if model:GetAttribute("Rig") == nil then
		return
	end
	-- The model replicates in pieces; wait a moment for its joints to arrive.
	task.defer(function()
		if not model.Parent then
			return
		end
		local rigged = collect(model)
		if rigged then
			tracked[model] = rigged
		end
	end)
end

--[[
	The server bumps `AttackSeq` / `FlinchSeq` when something happens. Polling
	them each frame rather than binding attribute-changed signals is both
	simpler and race-free: the old version wired listeners from a loop that ran
	twice a second, so a goblin that spawned and swung inside that window
	played nothing at all.
]]
local function pollTriggers(rigged: Rigged)
	local attack = (rigged.Model:GetAttribute("AttackSeq") :: number?) or 0
	if attack > rigged.LastAttack then
		rigged.LastAttack = attack
		rigged.OneShot = "Attack"
		rigged.OneShotT = 0
		rigged.OneShotLen = 1.05
		return
	end
	local flinch = (rigged.Model:GetAttribute("FlinchSeq") :: number?) or 0
	if flinch > rigged.LastFlinch then
		rigged.LastFlinch = flinch
		-- Do not let a flinch cancel a swing that is already in the air.
		if rigged.OneShot ~= "Attack" then
			rigged.OneShot = "Flinch"
			rigged.OneShotT = 0
			rigged.OneShotLen = 0.42
		end
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local origin = if camera then camera.CFrame.Position else Vector3.zero

	for model, rigged in pairs(tracked) do
		if not model.Parent or not rigged.Root.Parent then
			tracked[model] = nil
			continue
		end
		if (rigged.Root.Position - origin).Magnitude > ANIMATE_DISTANCE then
			continue
		end

		rigged.Phase += dt
		local joints = rigged.Joints

		pollTriggers(rigged)

		if rigged.OneShot then
			rigged.OneShotT += dt
			local u = rigged.OneShotT / rigged.OneShotLen
			if u >= 1 then
				rigged.OneShot = nil
			elseif rigged.OneShot == "Attack" then
				EnemyAnimation.Attack(joints, u, rigged.Drop)
			else
				EnemyAnimation.Flinch(joints, u, rigged.Drop)
			end
		end

		if not rigged.OneShot then
			-- Horizontal speed only: falling should not read as walking.
			local v = rigged.Root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			if speed > WALK_THRESHOLD then
				EnemyAnimation.Walk(joints, rigged.Phase, rigged.Drop)
			else
				EnemyAnimation.Idle(joints, rigged.Phase, rigged.Drop)
			end
		end

		--[[
			Ground clamp. Swinging the legs changes how far the feet reach, so
			without this the body visibly floats at the extremes of a stride.
			Measure the lowest foot and carry a correction into the next frame's
			pelvis offset — one frame of lag is invisible.
		]]
		local footL, footR = rigged.FootL, rigged.FootR
		if footL and footR and footL.Parent and footR.Parent then
			local lowest = math.min(
				footL.Position.Y - footL.Size.Y / 2,
				footR.Position.Y - footR.Size.Y / 2
			)
			local target = rigged.Root.Position.Y - rigged.Humanoid.HipHeight - rigged.Root.Size.Y / 2
			rigged.Drop = math.clamp(rigged.Drop - (lowest - target) * 0.5, -1.4, 0.3)
		end
	end
end

function EnemyAnimationController.Start()
	for _, d in ipairs(Workspace:GetDescendants()) do
		add(d)
	end
	Workspace.DescendantAdded:Connect(add)
	Workspace.DescendantRemoving:Connect(function(d)
		if d:IsA("Model") then
			tracked[d] = nil
		end
	end)

	connection = RunService.RenderStepped:Connect(step)
end

function EnemyAnimationController.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	table.clear(tracked)
end

return EnemyAnimationController
