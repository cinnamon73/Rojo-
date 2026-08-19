--!strict
--[[
	DevRigDump — exports the live R15 skeleton to a local tool over HTTP.

	This exists so animation work can happen in Blender against the REAL rig
	instead of guessed proportions. It measures what the engine actually built:
	part sizes, every joint's attachment offsets, and where the class weapon
	welds into the right hand.

	SAFETY: gated on PlaceId == 0, which is only ever true for an unpublished
	local .rbxlx opened as a file. It cannot run in the real game, published or
	in Team Create, no matter how it is synced.

	It also drives the class pick itself so the dump needs no clicking.
]]

local RunService = game:GetService("RunService")

--[[
	Opt-in, not automatic. Gated three ways: Studio only, unpublished local
	file only (PlaceId 0), and only when a marker named RIGDUMP is dropped in
	ServerStorage. Without the marker this file does nothing, so nobody else
	testing a local copy gets a class silently picked for them.

	To use it:  Instance.new("Folder", game.ServerStorage).Name = "RIGDUMP"
]]
if not RunService:IsStudio() or game.PlaceId ~= 0 then
	return
end

if not game:GetService("ServerStorage"):FindFirstChild("RIGDUMP") then
	return
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ENDPOINT = "http://127.0.0.1:8787/dump"
local CLASS = "Berserker"

local function comps(cf: CFrame): { number }
	return { cf:GetComponents() }
end

local function dump(character: Model, tool: Instance?): { [string]: any }
	local parts: { [string]: any } = {}
	local joints: { any } = {}

	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			parts[d.Name] = { Size = { d.Size.X, d.Size.Y, d.Size.Z } }
		elseif d.ClassName == "AnimationConstraint" or d:IsA("Motor6D") then
			local a0 = (d :: any).Attachment0
			local a1 = (d :: any).Attachment1
			if a0 and a1 and a0.Parent and a1.Parent then
				table.insert(joints, {
					Name = d.Name,
					Class = d.ClassName,
					Parent = a0.Parent.Name,
					Child = a1.Parent.Name,
					A0 = comps(a0.CFrame),
					A1 = comps(a1.CFrame),
				})
			end
		end
	end

	local weapon: { any } = {}
	local grip = nil
	if tool then
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") and handle then
				table.insert(weapon, {
					Name = d.Name,
					Size = { d.Size.X, d.Size.Y, d.Size.Z },
					-- Every weapon part expressed in HANDLE space, so Blender can
					-- rebuild the whole weapon around the grip point.
					RelHandle = comps(handle.CFrame:Inverse() * d.CFrame),
				})
			end
		end
		local rightHand = character:FindFirstChild("RightHand")
		local weld = rightHand and rightHand:FindFirstChild("RightGrip")
		if weld and weld:IsA("Weld") then
			grip = { C0 = comps(weld.C0), C1 = comps(weld.C1), Part0 = weld.Part0 and weld.Part0.Name }
		end
	end

	return {
		Parts = parts,
		Joints = joints,
		Weapon = weapon,
		Grip = grip,
		Archetype = tool and tool:GetAttribute("Archetype") or nil,
	}
end

task.spawn(function()
	local player = Players.PlayerAdded:Wait()
	if not player then
		return
	end

	-- Give the profile time to load, then pick the class ourselves.
	task.wait(4)

	local ok, err = pcall(function()
		local ClassService = require(script.Parent.Services.ClassService)
		ClassService.Select(player, CLASS)
	end)
	if not ok then
		warn("[RigDump] class select failed: " .. tostring(err))
	end

	local deadline = os.clock() + 20
	local character, tool
	repeat
		task.wait(0.5)
		character = player.Character
		tool = character and character:FindFirstChildOfClass("Tool")
	until (character and tool) or os.clock() > deadline

	if not character then
		warn("[RigDump] no character to measure")
		return
	end

	local payload = dump(character, tool)
	local sent, sendErr = pcall(function()
		HttpService:PostAsync(ENDPOINT, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson)
	end)

	if sent then
		print(string.format("[RigDump] sent %d joints, %d weapon parts", #payload.Joints, #payload.Weapon))
	else
		warn("[RigDump] POST failed: " .. tostring(sendErr))
	end
end)
