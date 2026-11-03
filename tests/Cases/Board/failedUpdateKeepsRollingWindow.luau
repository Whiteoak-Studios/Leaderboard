--[[
    A failed update on a rolling board rejects and leaves the player's
    stored total, its first-write time and their row as they were
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local KEY: string = "Failed-Wipe"
local USER: number = 7
local WINDOW: number = 3600
local FIRST: number = 10
local SECOND: number = 5
local LATER: number = 600
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local board: any = env.require("Board/init").new("Wipe", { expirySeconds = WINDOW, key = KEY })
	local start: number = env.clock.now()

	env.settle(board:read(AMOUNT))
	env.settle(board:update(USER, Boards.add(FIRST)))

	env.clock.advance(LATER)
	env.services.DataStoreService.failNext("UpdateAsync")

	local updated: boolean = env.settle(board:update(USER, Boards.add(SECOND)))

	if updated then
		return false, "the update resolved though its totals write failed"
	end

	local record: any = env.services.DataStoreService.peek(KEY, USER)
	if not record or record.total ~= FIRST or record.window ~= start then
		return false, `the failed update left {record and record.total} from {record and record.window}`
	end

	local items: { any } = env.services.MemoryStoreService.peek(KEY)
	if #items ~= 1 or items[1].value ~= FIRST or items[1].expiresAt ~= start + WINDOW then
		return false, "the failed update changed the player's row"
	end

	-- The next update adds to the kept total, inside the window the first write opened
	local ok: boolean, total: any = env.settle(board:update(USER, Boards.add(SECOND)))

	if not ok or total ~= FIRST + SECOND or env.services.DataStoreService.peek(KEY, USER).window ~= start then
		return false, `the next update resolved with {total}, not {FIRST + SECOND} in the same window`
	end

	return true, nil
end
