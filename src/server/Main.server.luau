--!strict

-- The `.server.luau` suffix tells Rojo to create this as a Script.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

print("[server]", Config.Greeting)
