--!strict

-- The `.client.luau` suffix tells Rojo to create this as a LocalScript.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Config)

print("[client]", Config.Greeting)
