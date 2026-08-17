--!strict
--[[
	Remotes — the single source of truth for the client/server wire contract.

	Every remote in the game is declared here with its kind and a description of
	what it does. The server builds the actual instances at runtime from this
	manifest; the client only ever looks them up by name. Adding a remote means
	adding one entry here, not hunting for where instances get created.

	The folder is built at RUNTIME rather than checked into the Rojo tree on
	purpose: Rojo manages ReplicatedStorage's children, so a checked-in Remotes
	folder would be torn down and rebuilt on every sync while a server is live.

	Direction is documented, not enforced by the engine — a RemoteEvent is
	bidirectional. Treat "C->S" as "the server must validate everything here".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type RemoteKind = "Event" | "Function"

export type RemoteDefinition = {
	Kind: RemoteKind,
	Direction: string,
	Description: string,
	-- Per-player token bucket. nil falls back to GameConfig.Network defaults.
	Burst: number?,
	RefillPerSecond: number?,
}

local Remotes = {}

Remotes.FolderName = "Remotes"

Remotes.Definitions = {
	--========================================================================
	-- Server -> Client (pushes; the client never validates these)
	--========================================================================

	ProfileUpdated = {
		Kind = "Event" :: RemoteKind,
		Direction = "S->C",
		Description = "Pushes a replicated view of the player's profile. Sent on load and after any authoritative change.",
	},

	Notify = {
		Kind = "Event" :: RemoteKind,
		Direction = "S->C",
		Description = "Transient toast for this player: errors, rewards, quest completions.",
	},

	GlobalAnnounce = {
		Kind = "Event" :: RemoteKind,
		Direction = "S->C",
		Description = "Server-wide banner for exceptionally rare drops and boss kills.",
	},

	RollResult = {
		Kind = "Event" :: RemoteKind,
		Direction = "S->C",
		Description = "The authoritative outcome of a roll, sent after the server has already committed it to the profile.",
	},

	--========================================================================
	-- Client -> Server (every one of these is untrusted input)
	--========================================================================

	RollRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Requests a single roll. Server enforces cooldown, computes rarity, and awards the item.",
		Burst = 4,
		RefillPerSecond = 2,
	},

	AutoRollRequest = {
		Kind = "Event" :: RemoteKind,
		Direction = "C->S",
		Description = "Starts or stops server-driven auto-roll, with an optional stop-at-rarity threshold.",
		Burst = 4,
		RefillPerSecond = 1,
	},

	EquipRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Equips or unequips an owned item instance into its slot.",
	},

	SellRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Sells owned item instances. Refuses locked items and anything not actually owned.",
	},

	FavoriteRequest = {
		Kind = "Event" :: RemoteKind,
		Direction = "C->S",
		Description = "Toggles the lock/favorite flag on an owned item instance.",
	},

	SettingsRequest = {
		Kind = "Event" :: RemoteKind,
		Direction = "C->S",
		Description = "Persists a client setting change (volumes, reduced effects, damage numbers).",
	},

	AttackRequest = {
		Kind = "Event" :: RemoteKind,
		Direction = "C->S",
		Description = "Requests a basic attack. Server validates cooldown, range, and target before applying damage.",
		Burst = 10,
		RefillPerSecond = 8,
	},

	AbilityRequest = {
		Kind = "Event" :: RemoteKind,
		Direction = "C->S",
		Description = "Requests a weapon ability. Server validates ownership, cooldown, and cost.",
		Burst = 4,
		RefillPerSecond = 2,
	},

	QuestRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Claims a completed quest reward. Server re-verifies completion before paying out.",
	},

	DailyClaimRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Claims the current daily reward. Server time is authoritative.",
		Burst = 3,
		RefillPerSecond = 1,
	},

	ShopRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Buys a shop entry with in-game currency. Robux purchases go through MarketplaceService instead.",
	},

	ZoneTravelRequest = {
		Kind = "Function" :: RemoteKind,
		Direction = "C->S",
		Description = "Requests travel to a zone. Server re-checks the unlock requirements every time.",
		Burst = 4,
		RefillPerSecond = 1,
	},
} :: { [string]: RemoteDefinition }

--[[
	Creates the remote instances. Server only, idempotent — safe to call twice,
	and safe if another script already built the folder.
]]
function Remotes.Build(): Folder
	assert(RunService:IsServer(), "Remotes.Build must be called on the server")

	local folder = ReplicatedStorage:FindFirstChild(Remotes.FolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Remotes.FolderName
		folder.Parent = ReplicatedStorage
	end

	for name, definition in pairs(Remotes.Definitions) do
		local existing = folder:FindFirstChild(name)
		local expectedClass = if definition.Kind == "Function" then "RemoteFunction" else "RemoteEvent"

		if existing and not existing:IsA(expectedClass) then
			existing:Destroy()
			existing = nil
		end

		if not existing then
			local remote = Instance.new(expectedClass)
			remote.Name = name
			remote.Parent = folder
		end
	end

	return folder :: Folder
end

--[[
	Looks up a remote by name.

	On the client this yields until the instance replicates, so callers do not
	need their own WaitForChild dance. On the server it asserts, because a
	missing remote there means Build() was never run.
]]
function Remotes.Get(name: string): RemoteEvent | RemoteFunction
	local definition = Remotes.Definitions[name]
	assert(definition, string.format("Remotes: unknown remote '%s'", name))

	local folder: Instance?
	if RunService:IsServer() then
		folder = ReplicatedStorage:FindFirstChild(Remotes.FolderName)
		assert(folder, "Remotes: folder missing — call Remotes.Build() during server startup")
	else
		folder = ReplicatedStorage:WaitForChild(Remotes.FolderName, 30)
		assert(folder, "Remotes: folder never replicated to the client")
	end

	local remote = (folder :: Folder):WaitForChild(name, 30)
	assert(remote, string.format("Remotes: '%s' never replicated", name))

	return remote :: any
end

return Remotes
