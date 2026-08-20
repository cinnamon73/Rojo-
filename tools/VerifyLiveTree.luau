--[[
	VerifyLiveTree — paste into the Studio command bar (Edit mode).

	WHY THIS EXISTS
	Rojo Connect REPLACES ReplicatedStorage, ServerScriptService and
	StarterPlayerScripts with the connecting person's `src/`. It is not a merge.
	So when one session adds a module and edits an existing file to require it,
	and the other session then connects with a checkout that has neither, the
	live tree ends up holding code that requires modules which are not there.

	That failure is SILENT in Edit mode. Nothing looks wrong. It only surfaces
	when someone presses Play and a service fails to load — and because the
	server Bootstrap requires services in order, ONE missing module stops every
	service after it from starting. That is how "the classes disappeared" with
	nothing in the class system actually touched.

	This script finds it in one command:
	  * every `require(Container.Name)` in the live tree is resolved
	  * every service and controller module is actually loaded, in a clone, to
	    catch errors that only appear at require time
	  * a missing target is reported with the file that wanted it

	RUN IT:
	  * straight after pressing Connect
	  * before disconnecting or handing the Rojo lock over
	  * before stopping a Rojo server — leaving the tree broken with no server
	    running means it cannot repair itself

	Never end a session on a red result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local roots = {
	{ "ReplicatedStorage", ReplicatedStorage },
	{ "ServerScriptService", ServerScriptService },
	{ "StarterPlayerScripts", StarterPlayer:FindFirstChild("StarterPlayerScripts") },
}

-- Containers this codebase requires through, e.g. `require(Modules.Logger)`.
local CONTAINERS = { "Modules", "Config", "Services", "Controllers" }

local containerOf = {}
for _, entry in ipairs(roots) do
	local root = entry[2]
	if root then
		for _, name in ipairs(CONTAINERS) do
			local found = root:FindFirstChild(name, true)
			if found then
				containerOf[name] = found
			end
		end
	end
end

local problems = {}
local checked, requires = 0, 0

for _, entry in ipairs(roots) do
	local label, root = entry[1], entry[2]
	if not root then
		table.insert(problems, string.format("%s is missing entirely", label))
		continue
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			checked += 1
			local source = d.Source
			for container, child in string.gmatch(source, "require%s*%(%s*([%w_]+)%s*%.%s*([%w_]+)") do
				if table.find(CONTAINERS, container) then
					requires += 1
					local parent = containerOf[container]
					if not parent then
						table.insert(problems, string.format(
							"%s requires %s.%s but there is no %s container",
							d:GetFullName(), container, child, container))
					elseif not parent:FindFirstChild(child) then
						table.insert(problems, string.format(
							"MISSING: %s.%s — required by %s",
							container, child, d:GetFullName()))
					end
				end
			end
		end
	end
end

--[[
	Load every service and controller. A require can fail for reasons a text
	scan cannot see: a syntax error, or a module missing further down the chain.

	REQUIRE THE REAL MODULE, NEVER A CLONE. A clone has no parent, so every
	`script.Parent` lookup inside it fails and the module reports an error that
	has nothing to do with the tree. Doing it the clone way reported 7 of 17
	services broken when all 17 were fine.
]]
local loadFailures = {}
for _, name in ipairs({ "Services", "Controllers" }) do
	local parent = containerOf[name]
	if parent then
		for _, m in ipairs(parent:GetChildren()) do
			if m:IsA("ModuleScript") then
				local ok, err = pcall(require, m)
				if not ok then
					table.insert(loadFailures, string.format("%s.%s -> %s", name, m.Name, tostring(err):sub(1, 160)))
				end
			end
		end
	end
end

local lines = {}
table.insert(lines, string.format("scanned %d scripts, %d container requires", checked, requires))
table.insert(lines, "")
if #problems == 0 then
	table.insert(lines, "REQUIRE TARGETS: all present")
else
	table.insert(lines, string.format("REQUIRE TARGETS: %d PROBLEM(S)", #problems))
	for _, p in ipairs(problems) do
		table.insert(lines, "   " .. p)
	end
end
table.insert(lines, "")
if #loadFailures == 0 then
	table.insert(lines, "MODULE LOADS: every service and controller loads")
else
	table.insert(lines, string.format("MODULE LOADS: %d FAILED", #loadFailures))
	for _, f in ipairs(loadFailures) do
		table.insert(lines, "   " .. f)
	end
end
table.insert(lines, "")
if #problems == 0 and #loadFailures == 0 then
	table.insert(lines, "TREE IS COHERENT — safe to hand over or stop the server.")
else
	table.insert(lines, "DO NOT HAND OVER OR STOP THE SERVER.")
	table.insert(lines, "Someone's checkout is missing files the live tree needs. Fix by:")
	table.insert(lines, "  1. git pull on the machine whose Rojo is connected")
	table.insert(lines, "  2. press Connect again to repaint the tree")
	table.insert(lines, "  3. re-run this script until it is clean")
end
return table.concat(lines, "\n")
