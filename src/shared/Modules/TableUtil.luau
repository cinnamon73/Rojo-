--!strict
--[[
	TableUtil — small table helpers used across the data layer.

	Reconcile is the important one: it grafts newly-added schema fields onto an
	existing saved profile without touching values the player already has. That
	is what lets us add a field to the default profile and have every returning
	player pick it up on their next load, with no migration step.
]]

local TableUtil = {}

--[[
	Recursive copy. Keys are copied by value (we never use table keys in the
	profile schema), values are copied deeply so mutating a copy can never
	write through to the original.
]]
function TableUtil.DeepCopy<T>(source: T): T
	if type(source) ~= "table" then
		return source
	end

	local copy = {}
	for key, value in pairs(source :: any) do
		copy[key] = TableUtil.DeepCopy(value)
	end

	return (copy :: any) :: T
end

--[[
	Fill in anything `target` is missing from `template`, recursively.

	Rules:
	  - key absent in target        -> deep-copied from template
	  - both are tables             -> recurse
	  - target has a value          -> left completely alone

	It never deletes keys. A field removed from the schema lingers in saved data
	as harmless dead weight; that is intentional, because deleting on load makes
	rollbacks destructive.
]]
function TableUtil.Reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, templateValue in pairs(template) do
		local targetValue = target[key]

		if targetValue == nil then
			target[key] = TableUtil.DeepCopy(templateValue)
		elseif type(templateValue) == "table" and type(targetValue) == "table" then
			TableUtil.Reconcile(targetValue, templateValue)
		end
	end

	return target
end

--[[ Number of keys in a dictionary (# only works on arrays). ]]
function TableUtil.Count(source: { [any]: any }): number
	local count = 0
	for _ in pairs(source) do
		count += 1
	end
	return count
end

--[[ Array of a dictionary's keys, order unspecified. ]]
function TableUtil.Keys(source: { [any]: any }): { any }
	local keys = {}
	for key in pairs(source) do
		table.insert(keys, key)
	end
	return keys
end

--[[
	Shallow read-only wrapper. Used on config tables so a stray write from
	gameplay code fails loudly at the assignment instead of silently corrupting
	shared state for every player on the server.
]]
function TableUtil.Freeze<T>(source: T & { [any]: any }, name: string?): T
	local label = name or "table"

	return (setmetatable({}, {
		__index = source,
		__newindex = function(_, key)
			error(string.format("attempt to modify read-only %s (key: %s)", label, tostring(key)), 2)
		end,
		__len = function()
			return #(source :: any)
		end,
		__iter = function()
			return pairs(source :: any)
		end,
	}) :: any) :: T
end

return TableUtil
