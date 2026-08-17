--!strict
--[[
	NetGuard — per-player, per-remote rate limiting and handler registration.

	Every remote handler in the game goes through here rather than connecting to
	OnServerEvent directly. That buys three things uniformly:

	  1. Token-bucket rate limiting, using the budgets declared in the remote
	     manifest. Over-budget requests are DROPPED, not errored — a laggy
	     client bursting is normal, and punishing it would hurt real players.
	  2. Handlers wrapped in pcall, so one bad request cannot kill the
	     connection for everyone.
	  3. Unregistered RemoteFunctions answer immediately instead of yielding
	     forever, which is what an un-handled invoke would otherwise do.

	Rate limiting is a nuisance filter, not an anti-cheat. The real defence is
	that every handler re-validates its own inputs against server state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = require(Modules.Remotes)
local Logger = require(Modules.Logger)
local GameConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("GameConfig"))

local log = Logger.new("NetGuard")

local NetGuard = {}

type Bucket = {
	Tokens: number,
	LastRefill: number,
	Strikes: number,
}

-- player -> remote name -> bucket
local buckets: { [Player]: { [string]: Bucket } } = {}
local registered: { [string]: boolean } = {}

local function getBucket(player: Player, remoteName: string): Bucket
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end

	local bucket = playerBuckets[remoteName]
	if not bucket then
		local definition = Remotes.Definitions[remoteName]
		bucket = {
			Tokens = (definition and definition.Burst) or GameConfig.Network.DefaultBurst,
			LastRefill = os.clock(),
			Strikes = 0,
		}
		playerBuckets[remoteName] = bucket
	end

	return bucket
end

--[[
	Consumes one token. Returns false when the player is over budget.
]]
local function consume(player: Player, remoteName: string): boolean
	local definition = Remotes.Definitions[remoteName]
	local burst = (definition and definition.Burst) or GameConfig.Network.DefaultBurst
	local refillRate = (definition and definition.RefillPerSecond) or GameConfig.Network.DefaultRefillPerSecond

	local bucket = getBucket(player, remoteName)
	local now = os.clock()

	bucket.Tokens = math.min(burst, bucket.Tokens + (now - bucket.LastRefill) * refillRate)
	bucket.LastRefill = now

	if bucket.Tokens < 1 then
		bucket.Strikes += 1

		-- Log once at the threshold rather than every drop, so a spamming
		-- client cannot also spam our output.
		if bucket.Strikes == GameConfig.Network.SuspiciousStrikeThreshold then
			log:Warn(
				"%s (%d) has hit the rate limit on '%s' %d times",
				player.Name, player.UserId, remoteName, bucket.Strikes
			)
		end

		return false
	end

	bucket.Tokens -= 1
	return true
end

--[[
	Registers a RemoteEvent handler.

	`handler(player, ...)` runs in its own thread. Its return value is ignored —
	use OnFunction when the client needs an answer.
]]
function NetGuard.OnEvent(remoteName: string, handler: (player: Player, ...any) -> ())
	local remote = Remotes.Get(remoteName)
	assert(remote:IsA("RemoteEvent"), string.format("NetGuard: '%s' is not a RemoteEvent", remoteName))

	registered[remoteName] = true

	;(remote :: RemoteEvent).OnServerEvent:Connect(function(player, ...)
		if not consume(player, remoteName) then
			return
		end

		local ok, err = pcall(handler, player, ...)
		if not ok then
			log:Error("handler '%s' errored for %s: %s", remoteName, player.Name, tostring(err))
		end
	end)
end

--[[
	Registers a RemoteFunction handler.

	The handler should return a result table. On rate-limit or error we return a
	structured failure rather than throwing, so the client always gets a shaped
	reply it can branch on instead of an opaque invoke error.
]]
function NetGuard.OnFunction(remoteName: string, handler: (player: Player, ...any) -> any)
	local remote = Remotes.Get(remoteName)
	assert(remote:IsA("RemoteFunction"), string.format("NetGuard: '%s' is not a RemoteFunction", remoteName))

	registered[remoteName] = true

	;(remote :: RemoteFunction).OnServerInvoke = function(player, ...)
		if not consume(player, remoteName) then
			return { Success = false, Error = "RateLimited" }
		end

		local ok, result = pcall(handler, player, ...)
		if not ok then
			log:Error("handler '%s' errored for %s: %s", remoteName, player.Name, tostring(result))
			return { Success = false, Error = "InternalError" }
		end

		return result
	end
end

--[[
	Answers every declared RemoteFunction that nobody registered, so a client
	invoking a not-yet-implemented remote gets a clean refusal instead of
	hanging forever. Call once, after all services have registered.
]]
function NetGuard.SealUnhandled()
	local sealed = {}

	for name, definition in pairs(Remotes.Definitions) do
		if definition.Kind == "Function" and not registered[name] then
			local remote = Remotes.Get(name) :: RemoteFunction
			remote.OnServerInvoke = function()
				return { Success = false, Error = "NotImplemented" }
			end
			table.insert(sealed, name)
		end
	end

	if #sealed > 0 then
		table.sort(sealed)
		log:Info("sealed %d unimplemented remote function(s): %s", #sealed, table.concat(sealed, ", "))
	end
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return NetGuard
