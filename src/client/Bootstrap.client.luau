--!strict
--[[
	Bootstrap — client entry point.

	Waits for the server's remote contract, then starts controllers. The client
	owns presentation and input only; it never decides an outcome.

	Profile state arrives via the ProfileUpdated remote and is cached here for
	the UI to read. That cache is a VIEW, not a source of truth — the server can
	contradict it at any time and the client must accept that silently.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local Logger = require(Modules.Logger)
local Remotes = require(Modules.Remotes)
local Signal = require(Modules.Signal)

local log = Logger.new("Client")
local player = Players.LocalPlayer

local Client = {}

--[[ Last profile view pushed by the server, or nil before the first push. ]]
Client.Profile = nil :: any

--[[ Fires with the new profile whenever the server pushes an update. ]]
Client.ProfileChanged = Signal.new()

local function main()
	log:Info("starting client for %s...", player.Name)

	local profileUpdated = Remotes.Get("ProfileUpdated") :: RemoteEvent
	local notify = Remotes.Get("Notify") :: RemoteEvent
	local globalAnnounce = Remotes.Get("GlobalAnnounce") :: RemoteEvent

	profileUpdated.OnClientEvent:Connect(function(profile)
		if type(profile) ~= "table" then
			return
		end

		Client.Profile = profile
		Client.ProfileChanged:Fire(profile)
	end)

	-- Toasts and the global banner are wired to real UI in Phase 8. Logging
	-- them now means the server side is testable before the UI exists.
	notify.OnClientEvent:Connect(function(payload)
		log:Info("notify: %s", tostring(type(payload) == "table" and payload.Message or payload))
	end)

	globalAnnounce.OnClientEvent:Connect(function(payload)
		log:Info("announce: %s", tostring(type(payload) == "table" and payload.Message or payload))
	end)

	-- Controllers start after the remote wiring above, so nothing races on a
	-- remote that has not replicated yet.
	local Controllers = script.Parent:WaitForChild("Controllers")

	require(Controllers.UIController).Start(Client)
	require(Controllers.CombatController).Start(Client)
	require(Controllers.AtmosphereController).Start(Client)
	require(Controllers.FXController).Start(Client)
	require(Controllers.StanceController).Start(Client)
	require(Controllers.AbilityController).Start(Client)
	require(Controllers.ClassSelectController).Start(Client)
	-- Poses the articulated enemy rigs locally; takes no Client handle because
	-- it reads the world rather than any remote.
	require(Controllers.EnemyAnimationController).Start()

	log:Info("client ready")
end

local ok, err = pcall(main)
if not ok then
	log:Error("CLIENT BOOTSTRAP FAILED: %s", tostring(err))
	warn(debug.traceback("client bootstrap failed", 2))
end

return nil
