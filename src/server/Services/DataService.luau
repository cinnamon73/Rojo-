--!strict
--[[
	DataService — profile loading, session locking, autosave, and shutdown flush.

	Design rules, in priority order:

	  1. NEVER overwrite good data with empty data. If a load fails, the player
	     is kicked rather than handed a blank profile that would save over their
	     real one. This is the single most important rule here.
	  2. One live session per player. A session lock stored alongside the data
	     stops two servers writing the same key, which is how duplication bugs
	     and rollbacks happen.
	  3. Every DataStore call is wrapped and retried with backoff. Roblox's
	     data stores fail transiently and that must never surface as a crash.

	Lock semantics: the lock records the JobId that owns the session and when it
	was last refreshed. A lock older than SessionLockTimeout is treated as
	abandoned (its server died without releasing) and can be stolen.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = ReplicatedStorage:WaitForChild("Config")

local DataSchema = require(Modules.DataSchema)
local Logger = require(Modules.Logger)
local Signal = require(Modules.Signal)
local GameConfig = require(Config.GameConfig)

local log = Logger.new("DataService")

local DataService = {}

DataService.ProfileLoaded = Signal.new()
DataService.ProfileReleasing = Signal.new()

local store: DataStore? = nil
local profiles: { [Player]: any } = {}
local loading: { [Player]: boolean } = {}
local shuttingDown = false

--[[
	Session identity.

	In Studio, game.JobId is empty. Using a timestamp here would give every
	play-test a new identity, so a session could never reclaim the lock its own
	previous run left behind — and each restart would fail to load until the
	lock timed out. A stable id means Studio always reclaims immediately, which
	is both correct (it IS the same developer's machine) and testable.
]]
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-local"

--[[
	Studio sessions end abruptly and often, so stale locks are the norm there.
	Live servers get the long timeout, which is what protects against two real
	servers writing the same key.
]]
local function sessionLockTimeout(): number
	return if RunService:IsStudio() then 20 else GameConfig.Data.SessionLockTimeout
end

local function keyFor(userId: number): string
	return "Player_" .. tostring(userId)
end

--[[
	Runs a DataStore call with retry and exponential backoff.
	Returns (ok, resultOrError).
]]
local function withRetry<T>(label: string, fn: () -> T): (boolean, any)
	local settings = GameConfig.Data
	local delay = settings.RetryBaseDelay
	local lastError: any = nil

	for attempt = 1, settings.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end

		lastError = result
		log:Warn("%s attempt %d/%d failed: %s", label, attempt, settings.MaxRetries, tostring(result))

		if attempt < settings.MaxRetries then
			task.wait(delay)
			delay *= settings.RetryBackoff
		end
	end

	return false, lastError
end

local function getStore(): DataStore?
	if store then
		return store
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)

	if ok then
		store = result
		return store
	end

	log:Error("could not open DataStore '%s': %s", GameConfig.Data.StoreName, tostring(result))
	return nil
end

--[[
	True when a stored lock should be considered dead: no lock at all, our own
	JobId (we are reclaiming after a rejoin on the same server), or a stale
	timestamp from a server that never released it.
]]
local function lockIsClaimable(lock: any): boolean
	if type(lock) ~= "table" then
		return true
	end

	if lock.JobId == JOB_ID then
		return true
	end

	local age = os.time() - (tonumber(lock.At) or 0)
	return age > sessionLockTimeout()
end

--[[
	Loads a profile and claims the session lock in one UpdateAsync, so the
	check and the claim cannot race against another server.

	Returns (profile, errorMessage).
]]
local function loadProfile(userId: number): (any?, string?)
	local dataStore = getStore()
	if not dataStore then
		return nil, "datastore unavailable"
	end

	local rejection: string? = nil

	local ok, result = withRetry("load(" .. tostring(userId) .. ")", function()
		rejection = nil

		return dataStore:UpdateAsync(keyFor(userId), function(stored)
			local envelope = stored

			if type(envelope) ~= "table" then
				envelope = { Data = nil, Lock = nil }
			end

			if not lockIsClaimable(envelope.Lock) then
				-- Abort the write; another live server owns this session.
				rejection = "session locked by another server"
				return nil
			end

			local data = envelope.Data
			if type(data) ~= "table" then
				data = DataSchema.CreateDefault()
			else
				local migrated
				data, migrated = DataSchema.MigrateAndReconcile(data)
				if migrated then
					log:Info("migrated profile %d to v%d", userId, DataSchema.Version)
				end
			end

			data.Meta.LastSeenAt = os.time()

			envelope.Data = data
			envelope.Lock = { JobId = JOB_ID, At = os.time() }

			return envelope
		end)
	end)

	if rejection then
		return nil, rejection
	end

	if not ok then
		return nil, "datastore error: " .. tostring(result)
	end

	if type(result) ~= "table" or type(result.Data) ~= "table" then
		return nil, "malformed envelope"
	end

	return result.Data, nil
end

--[[
	Writes the profile and refreshes (or releases) the lock.

	Refuses to write if another server has taken the lock — that means our
	session was stolen after a timeout, and writing would clobber the newer
	session's progress.
]]
local function saveProfile(userId: number, data: any, release: boolean): boolean
	local dataStore = getStore()
	if not dataStore then
		return false
	end

	local refused = false

	local ok, err = withRetry("save(" .. tostring(userId) .. ")", function()
		refused = false

		return dataStore:UpdateAsync(keyFor(userId), function(stored)
			local envelope = if type(stored) == "table" then stored else {}
			local lock = envelope.Lock

			if type(lock) == "table" and lock.JobId ~= JOB_ID and not lockIsClaimable(lock) then
				refused = true
				return nil
			end

			data.Meta.SaveCount = (data.Meta.SaveCount or 0) + 1
			data.Meta.LastSeenAt = os.time()

			envelope.Data = data
			envelope.Lock = if release then nil else { JobId = JOB_ID, At = os.time() }

			return envelope
		end)
	end)

	if refused then
		log:Warn("save for %d refused — session lock held by another server", userId)
		return false
	end

	if not ok then
		log:Error("save for %d failed permanently: %s", userId, tostring(err))
		return false
	end

	return true
end

--========================================================================
-- Public API
--========================================================================

--[[ The live profile table, or nil if not loaded (or still loading). ]]
function DataService.Get(player: Player): any?
	return profiles[player]
end

--[[
	Yields until the profile is available, or timeout elapses.
	Returns nil if the player left or loading failed.
]]
function DataService.WaitFor(player: Player, timeout: number?): any?
	local deadline = os.clock() + (timeout or 20)

	while os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end

		if not player.Parent then
			return nil
		end

		if not loading[player] and not profiles[player] then
			-- Load finished without producing a profile: it failed.
			return nil
		end

		task.wait(0.1)
	end

	return nil
end

--[[ Forces an immediate save. Returns whether it succeeded. ]]
function DataService.Save(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end

	return saveProfile(player.UserId, profile, false)
end

local function onPlayerAdded(player: Player)
	if shuttingDown then
		player:Kick("The server is restarting. Please rejoin.")
		return
	end

	loading[player] = true

	local profile, err = loadProfile(player.UserId)

	loading[player] = nil

	if not player.Parent then
		-- Left during load. Release the lock we just claimed so their next
		-- session is not blocked for SessionLockTimeout.
		if profile then
			task.spawn(saveProfile, player.UserId, profile, true)
		end
		return
	end

	if not profile then
		log:Error("load failed for %s (%d): %s", player.Name, player.UserId, tostring(err))

		if GameConfig.Data.KickOnLoadFailure then
			player:Kick(GameConfig.Data.LoadFailureMessage)
		end
		return
	end

	profiles[player] = profile
	log:Info("loaded profile for %s (save #%d)", player.Name, profile.Meta.SaveCount)

	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	DataService.ProfileReleasing:Fire(player, profile)

	profiles[player] = nil
	saveProfile(player.UserId, profile, true)
end

--[[
	Autosave loop. Staggered by a per-cycle offset rather than saving every
	profile in the same frame, which would burst the request budget on a full
	server.
]]
local function startAutosave()
	task.spawn(function()
		while not shuttingDown do
			task.wait(GameConfig.Data.AutosaveInterval)

			for player, profile in pairs(profiles) do
				if shuttingDown then
					break
				end
				if player.Parent then
					saveProfile(player.UserId, profile, false)
					task.wait(0.2)
				end
			end
		end
	end)
end

--[[
	Flushes every profile on shutdown. BindToClose gets roughly 30 seconds, so
	saves run in parallel and we wait on a counter rather than serially.
]]
local function onClose()
	shuttingDown = true

	local pending = 0
	local done = 0

	for player, profile in pairs(profiles) do
		pending += 1
		task.spawn(function()
			saveProfile(player.UserId, profile, true)
			done += 1
		end)
	end

	if pending == 0 then
		return
	end

	log:Info("shutdown flush: saving %d profile(s)", pending)

	local deadline = os.clock() + 25
	while done < pending and os.clock() < deadline do
		task.wait(0.1)
	end

	log:Info("shutdown flush complete (%d/%d)", done, pending)
end

local started = false

--[[ Idempotent. Safe if another bootstrap path already started the service. ]]
function DataService.Start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players who joined before this ran (Studio play-solo timing).
	for _, player in ipairs(Players:GetPlayers()) do
		if not profiles[player] and not loading[player] then
			task.spawn(onPlayerAdded, player)
		end
	end

	startAutosave()

	if not RunService:IsStudio() or GameConfig.Data.AutosaveInterval > 0 then
		game:BindToClose(onClose)
	end

	log:Info("started (store '%s', schema v%d)", GameConfig.Data.StoreName, DataSchema.Version)
end

return DataService
