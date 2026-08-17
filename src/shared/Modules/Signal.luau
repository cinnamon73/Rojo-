--!strict
--[[
	Signal — minimal Lua event.

	Deliberately not a BindableEvent: those serialize their arguments, which
	would hand every listener a deep copy of the profile instead of the live
	table. Services need the real reference.

	Handlers run in their own coroutine, so one erroring listener cannot stop
	the others or block the firing code.
]]

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, handler)
	return setmetatable({
		_signal = signal,
		_handler = handler,
		Connected = true,
	}, Connection)
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false

	local handlers = self._signal._handlers
	local index = table.find(handlers, self._handler)
	if index then
		table.remove(handlers, index)
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ()): Connection
	table.insert(self._handlers, handler)
	return (Connection.new(self, handler) :: any) :: Connection
end

--[[ Fires once, then disconnects itself before the handler runs. ]]
function Signal:Once(handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

--[[
	Iterates a copy so a handler that disconnects (or connects) during dispatch
	cannot mutate the list we are walking.
]]
function Signal:Fire(...: any)
	local snapshot = table.clone(self._handlers)

	for _, handler in ipairs(snapshot) do
		task.spawn(function(...)
			local ok, err = pcall(handler, ...)
			if not ok then
				warn("[RNGA][Signal] handler error: " .. tostring(err))
			end
		end, ...)
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

return Signal
