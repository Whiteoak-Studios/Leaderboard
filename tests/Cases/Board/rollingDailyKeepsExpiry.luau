--[[
    A rolling board named Daily keeps its own expiry when the UTC day turns,
    since only its configuration decides its kind
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Rolling-Daily"
local USER: number = 1
local ADDED: number = 5 -- Each of the two updates, one either side of midnight
local TOTAL: number = ADDED + ADDED
local WINDOW: number = 172800 -- Two days, so the UTC day turns inside it
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local board: any = env.require("Board/init").new("Daily", { expirySeconds = WINDOW, key = KEY })
	local start: number = env.clock.now()

	env.settle(board:read(AMOUNT))
	env.settle(board:update(USER, Boards.add(ADDED)))

	env.clock.advance(Start.TO_MIDNIGHT)
	local ok: boolean, total: any = env.settle(board:update(USER, Boards.add(ADDED)))
	local items: { any } = env.services.MemoryStoreService.peek(KEY)

	if not ok or total ~= TOTAL then
		return false, `the rolling Daily board's total was {total} after the UTC day turned, not {TOTAL}`
	end

	if #items ~= 1 or items[1].value ~= TOTAL or items[1].expiresAt ~= start + WINDOW then
		return false, `the row expires at {items[1] and items[1].expiresAt}, not its own window's end {start + WINDOW}`
	end

	local read: boolean, rows: any = env.settle(board:read(AMOUNT))
	if not read or #rows ~= 1 or rows[1].value ~= TOTAL then
		return false, "the rolling Daily board read a new day's empty map"
	end

	return true, nil
end
