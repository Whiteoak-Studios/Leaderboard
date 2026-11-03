--[[
    delete removes the player's map entry and totals key, or their AllTime
    entry, and leaves every other player's as it was
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local USER: number = 1
local OTHER: number = 2
local VALUE: number = 5
local OTHER_VALUE: number = 6
local AMOUNT: number = 100

type Entry = { name: string, config: any, key: string, map: string? }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Delete-Daily", key = "Delete-Daily", map = `Delete-Daily:{Start.DAY}` },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Delete-Wipe" }, key = "Delete-Wipe", map = "Delete-Wipe" },
	{ name = "AllTime", config = "Delete-AllTime", key = "Delete-AllTime" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local service: any = env.services.DataStoreService
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.set(VALUE)))
		env.settle(board:update(OTHER, Boards.set(OTHER_VALUE)))

		if not env.settle(board:delete(USER)) then
			return false, `{entry.name}'s delete rejected`
		end

		local map: string? = entry.map
		if map then
			local items: { any } = env.services.MemoryStoreService.peek(map)
			if #items ~= 1 or items[1].key ~= `{OTHER}` then
				return false, `{entry.name}'s map kept {#items} rows after the delete, not the other player's alone`
			end

			if service.peek(entry.key, USER) ~= nil or service.peek(entry.key, OTHER).total ~= OTHER_VALUE then
				return false, `{entry.name}'s delete left the deleted total or took the other one`
			end
		elseif service.peekOrdered(entry.key, USER) ~= nil or service.peekOrdered(entry.key, OTHER) ~= OTHER_VALUE then
			return false, `{entry.name}'s delete left the deleted entry or took the other one`
		end

		local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not ok or #rows ~= 1 or rows[1].userId ~= OTHER then
			return false, `{entry.name} still read the deleted player`
		end
	end

	return true, nil
end
