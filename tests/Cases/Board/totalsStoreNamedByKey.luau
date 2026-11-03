--[[
    A board's key names every store it writes: the totals DataStore, the
    sorted map beside it, and AllTime's OrderedDataStore
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local USER: number = 1
local VALUE: number = 3
local AMOUNT: number = 100

type Entry = { name: string, config: any, key: string, map: string? }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Kills-Daily-1", key = "Kills-Daily-1", map = `Kills-Daily-1:{Start.DAY}` },
	{
		name = "Wipe",
		config = { expirySeconds = 3600, key = "Kills-Wipe-1" },
		key = "Kills-Wipe-1",
		map = "Kills-Wipe-1",
	},
	{ name = "AllTime", config = "Kills-AllTime-1", key = "Kills-AllTime-1" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local service: any = env.services.DataStoreService
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.add(VALUE)))

		if entry.map then
			local record: any = service.peek(entry.key, USER)
			if not record or record.total ~= VALUE then
				return false, `{entry.name}'s total was not in the DataStore named {entry.key}`
			end

			if #env.services.MemoryStoreService.peek(entry.map) ~= 1 then
				return false, `{entry.name}'s row was not in the map named {entry.map}`
			end
		elseif service.peekOrdered(entry.key, USER) ~= VALUE or service.peek(entry.key, USER) ~= nil then
			return false, `{entry.name}'s value was not in the OrderedDataStore named {entry.key} alone`
		end
	end

	return true, nil
end
