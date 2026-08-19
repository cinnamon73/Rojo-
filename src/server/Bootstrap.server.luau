--!strict
--[[
	Bootstrap — server entry point.

	Starts services in dependency order and reports configuration gaps once at
	startup. Every service exposes an idempotent Start(), so running this twice
	(or racing another bootstrap during a Rojo sync) is harmless.

	Ordering rules:
	  - Remotes are built FIRST. Services register handlers against instances
	    that must already exist, and clients may be waiting on them.
	  - DataService comes before anything that reads a profile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local AssetConfig = require(Config.AssetConfig)
local MonetizationConfig = require(Config.MonetizationConfig)

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local NetGuard = require(Services.NetGuard)
local ReplicationService = require(Services.ReplicationService)
local CharacterService = require(Services.CharacterService)
local ClassService = require(Services.ClassService)
local MinionService = require(Services.MinionService)
local AbilityService = require(Services.AbilityService)
local EnemyService = require(Services.EnemyService)
local CombatService = require(Services.CombatService)

local log = Logger.new("Bootstrap")

local startedAt = os.clock()

--[[
	Surfaces unconfigured ids once, as a single line each, rather than letting
	them fail silently later. These are expected during development — the point
	is that they are visible, not that they are errors.
]]
local function reportConfigurationGaps()
	local missingMonetization = MonetizationConfig.GetUnconfigured()
	if #missingMonetization > 0 then
		log:Warn(
			"%d monetization id(s) not configured — those products are inactive: %s",
			#missingMonetization,
			table.concat(missingMonetization, ", ")
		)
	end

	local missingAssets = AssetConfig.GetUnconfigured()
	if #missingAssets > 0 then
		log:Warn("%d asset id(s) not configured — those sounds/images will not play", #missingAssets)
	end
end

local function main()
	log:Info("starting server...")

	-- 1. Wire contract. Must exist before any handler registers or any client
	--    finishes waiting.
	Remotes.Build()
	log:Info("remotes built (%d declared)", (function()
		local count = 0
		for _ in pairs(Remotes.Definitions) do
			count += 1
		end
		return count
	end)())

	-- 2. Player data. Everything downstream reads profiles.
	DataService.Start()

	-- 3. Replication, before any service that pushes state changes.
	ReplicationService.Start()

	-- 4. Character presentation, before equipment — equipping refreshes visuals
	--    and needs the body already standardised.
	CharacterService.Start()

	-- 5. Gameplay services. Classes before combat (combat reads class stats),
	--    enemies before combat (combat subscribes to the kill signal).
	ClassService.Start()
	MinionService.Start()
	EnemyService.Start()
	CombatService.Start()
	-- Last of the gameplay services: it registers a hook on EnemyService and
	-- reads class stats, so both must already be up.
	AbilityService.Start()

	-- 5. Answer any declared-but-unimplemented RemoteFunction so clients get a
	--    clean refusal instead of an invoke that never returns. Must run last.
	NetGuard.SealUnhandled()

	reportConfigurationGaps()

	log:Info("server ready in %.2fs", os.clock() - startedAt)
end

local ok, err = pcall(main)
if not ok then
	-- A bootstrap failure is fatal for gameplay but must not take down the
	-- server process, or players get a blank experience with no explanation.
	log:Error("BOOTSTRAP FAILED: %s", tostring(err))
	warn(debug.traceback("server bootstrap failed", 2))
end
