--[[
    A server writes no row for a board until its own first read of it, and
    a failed read does not count, though the player's total lands each time
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local USER: number = 1
local OTHER: number = 2
local FIRST: number = 5
local LATER: number = 1 -- Each later update of the reading server's player
local OTHER_VALUE: number = 3
local AMOUNT: number = 100

type Entry = { name: string, config: any, key: string, map: string }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Unread-Daily", key = "Unread-Daily", map = `Unread-Daily:{Start.DAY}` },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Unread-Wipe" }, key = "Unread-Wipe", map = "Unread-Wipe" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local first: any = Environment.new()
		local second: any = Environment.new({ server = first })
		local maps: any = first.services.MemoryStoreService
		local reader: any = first.require("Board/init").new(entry.name, entry.config)
		local writer: any = second.require("Board/init").new(entry.name, entry.config)

		local ok: boolean, total: any = first.settle(reader:update(USER, Boards.add(FIRST)))
		if not ok or total ~= FIRST or #maps.peek(entry.map) ~= 0 then
			return false, `{entry.name} wrote a row before its first read`
		end

		maps.failNext("GetRangeAsync")
		if first.settle(reader:read(AMOUNT)) then
			return false, `{entry.name}'s read resolved though GetRangeAsync failed`
		end

		first.settle(reader:update(USER, Boards.add(LATER)))
		if #maps.peek(entry.map) ~= 0 then
			return false, `{entry.name} counted a failed read as its first`
		end

		-- One server's read does not let another write
		first.settle(reader:read(AMOUNT))
		second.settle(writer:update(OTHER, Boards.add(OTHER_VALUE)))
		if #maps.peek(entry.map) ~= 0 then
			return false, `{entry.name} took a row from a server that never read it`
		end

		local wrote: boolean, now: any = first.settle(reader:update(USER, Boards.add(LATER)))
		local items: { any } = maps.peek(entry.map)
		local expected: number = FIRST + LATER + LATER
		if not wrote or now ~= expected or #items ~= 1 or items[1].value ~= expected then
			return false, `{entry.name}'s first row after the read was {items[1] and items[1].value}, not {expected}`
		end

		if first.services.DataStoreService.peek(entry.key, OTHER).total ~= OTHER_VALUE then
			return false, `{entry.name} lost the unread server's total`
		end
	end

	return true, nil
end
