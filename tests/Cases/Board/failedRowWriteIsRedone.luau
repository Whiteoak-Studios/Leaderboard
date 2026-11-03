--[[
    A failed write to the top rows after the total landed still resolves,
    and the player's next update writes their row
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local USER: number = 1
local FIRST: number = 5
local SECOND: number = 2
local AMOUNT: number = 100

type Entry = { name: string, config: any, key: string, map: string }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Redone-Daily", key = "Redone-Daily", map = `Redone-Daily:{Start.DAY}` },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Redone-Wipe" }, key = "Redone-Wipe", map = "Redone-Wipe" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local maps: any = env.services.MemoryStoreService
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(AMOUNT))
		maps.failNext("UpdateAsync")

		local updated: boolean, total: any = env.settle(board:update(USER, Boards.add(FIRST)))
		if not updated or total ~= FIRST or env.services.DataStoreService.peek(entry.key, USER).total ~= FIRST then
			return false, `{entry.name} resolved {updated} with {total} when only its row write failed`
		end

		if #maps.peek(entry.map) ~= 0 then
			return false, `{entry.name} holds a row its failed write never landed`
		end

		local ok: boolean, later: any = env.settle(board:update(USER, Boards.add(SECOND)))
		local items: { any } = maps.peek(entry.map)
		if not ok or later ~= FIRST + SECOND or #items ~= 1 or items[1].value ~= FIRST + SECOND then
			return false,
				`{entry.name}'s next update left the row at {items[1] and items[1].value}, not {FIRST + SECOND}`
		end
	end

	return true, nil
end
