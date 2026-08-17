--!strict
--[[
	Logger — leveled logging with a consistent prefix.

	Every service creates its own scoped logger so output is greppable:
		local log = Logger.new("DataService")
		log:Info("loaded profile for %s", player.Name)
		--> [RNGA][DataService] loaded profile for hawkwonder

	Warn/Error always print. Info/Debug respect GameConfig.Debug so we can
	silence the console in production without deleting call sites.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local PREFIX = "[RNGA]"

export type Logger = {
	Info: (self: Logger, message: string, ...any) -> (),
	Debug: (self: Logger, message: string, ...any) -> (),
	Warn: (self: Logger, message: string, ...any) -> (),
	Error: (self: Logger, message: string, ...any) -> (),
}

local Logger = {}
Logger.__index = Logger

--[[
	Formats lazily: if the level is disabled we never pay for string.format.
	Guarded because a bad format string should never take down a caller.
]]
local function format(scope: string, message: string, ...: any): string
	local args = table.pack(...)
	if args.n == 0 then
		return string.format("%s[%s] %s", PREFIX, scope, message)
	end

	local ok, formatted = pcall(string.format, message, ...)
	if not ok then
		formatted = message .. " <malformed log args>"
	end

	return string.format("%s[%s] %s", PREFIX, scope, formatted)
end

function Logger.new(scope: string): Logger
	local self = setmetatable({}, Logger)
	self._scope = scope
	return (self :: any) :: Logger
end

function Logger:Info(message: string, ...: any)
	if not GameConfig.Debug.LogInfo then
		return
	end
	print(format(self._scope, message, ...))
end

function Logger:Debug(message: string, ...: any)
	if not GameConfig.Debug.LogVerbose then
		return
	end
	print(format(self._scope, message, ...))
end

function Logger:Warn(message: string, ...: any)
	warn(format(self._scope, message, ...))
end

--[[
	Deliberately warn() rather than error() — a logged error should never
	unwind the caller's stack. Call error() explicitly when you want that.
]]
function Logger:Error(message: string, ...: any)
	warn(format(self._scope, "ERROR: " .. message, ...))
end

return Logger
