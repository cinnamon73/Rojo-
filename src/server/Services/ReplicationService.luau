--!strict
--[[
	ReplicationService — pushes a client-safe view of the profile.

	The raw profile is not sent. Two reasons:

	  1. Size. Processed receipt ids, save counters, and internal bookkeeping
	     are irrelevant to the UI and would be replicated on every change.
	  2. Discipline. Sending the whole profile invites client code to treat it
	     as truth. The view is explicitly a snapshot for display.

	Anything the UI needs must be added to BuildView deliberately. If a field is
	missing client-side, that is the correct place to fix it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = require(Modules.Remotes)
local Logger = require(Modules.Logger)
local TableUtil = require(Modules.TableUtil)

local DataService = require(script.Parent.DataService)

local log = Logger.new("Replication")

local ReplicationService = {}

--[[
	The client-facing snapshot. Deep-copied so a client-bound table can never
	alias live server state.
]]
function ReplicationService.BuildView(profile: any): any
	return {
		Currency = TableUtil.DeepCopy(profile.Currency),
		Progression = TableUtil.DeepCopy(profile.Progression),
		Class = profile.Class,
		Boosts = TableUtil.DeepCopy(profile.Boosts),
		Stats = TableUtil.DeepCopy(profile.Stats),
		Zones = TableUtil.DeepCopy(profile.Zones),
		Settings = TableUtil.DeepCopy(profile.Settings),
		Tutorial = TableUtil.DeepCopy(profile.Tutorial),
	}
end

--[[ Sends the current view. No-op if the profile is not loaded. ]]
function ReplicationService.Push(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end

	local remote = Remotes.Get("ProfileUpdated") :: RemoteEvent
	remote:FireClient(player, ReplicationService.BuildView(profile))
end

--[[ One-off toast for a single player. ]]
function ReplicationService.Notify(player: Player, message: string, kind: string?)
	local remote = Remotes.Get("Notify") :: RemoteEvent
	remote:FireClient(player, { Message = message, Kind = kind or "Info" })
end

--[[ Server-wide banner. Reserved for genuinely rare events. ]]
function ReplicationService.Announce(message: string, rarityId: string?)
	local remote = Remotes.Get("GlobalAnnounce") :: RemoteEvent
	remote:FireAllClients({ Message = message, Rarity = rarityId })
end

local started = false

function ReplicationService.Start()
	if started then
		return
	end
	started = true

	-- Push once as soon as data is available, so the HUD populates without the
	-- client having to ask.
	DataService.ProfileLoaded:Connect(function(player)
		ReplicationService.Push(player)
	end)

	log:Info("started")
end

return ReplicationService
