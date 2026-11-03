--[[
    A failed read rejects on every store rather than resolving with no rows,
    so a store failure never looks like an empty board
--]]

--!strict
local Environment = require("../../Environment")

local AMOUNT: number = 100

type Entry = { name: string, config: any, service: string, method: string }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Unreadable-Daily", service = "MemoryStoreService", method = "GetRangeAsync" },
	{
		name = "Wipe",
		config = { expirySeconds = 3600, key = "Unreadable-Wipe" },
		service = "MemoryStoreService",
		method = "GetRangeAsync",
	},
	{ name = "AllTime", config = "Unreadable-AllTime", service = "DataStoreService", method = "GetSortedAsync" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.services[entry.service].failNext(entry.method)
		if env.settle(board:read(AMOUNT)) then
			return false, `{entry.name}'s read resolved though {entry.method} failed`
		end

		if not env.settle(board:read(AMOUNT)) then
			return false, `{entry.name}'s read after the failure rejected`
		end
	end

	return true, nil
end
