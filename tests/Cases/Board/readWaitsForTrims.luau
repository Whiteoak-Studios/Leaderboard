--[[
    A read resolves only once its trims have settled, so the map it leaves
    holds the board's rows and slack alone
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Waiting-Daily"
local MAP: string = `{KEY}:{Start.DAY}`
local EXTRA: number = 3
local DELAY: number = 5
local EARLY: number = 1 -- Seconds short of the trim's delay the read is checked
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local keep: number = env.require("Constants").KEPT_ROWS
	local maps: any = env.services.MemoryStoreService
	local board: any = env.require("Board/init").new("Daily", KEY)

	env.settle(board:read(AMOUNT))
	Boards.fill(env, board, keep + EXTRA)

	maps.delayNext("RemoveAsync", DELAY)
	local reading: any = board:read(AMOUNT)

	env.clock.advance(DELAY - EARLY)
	if reading:getStatus() ~= Environment.PENDING then
		return false, `the read settled as {reading:getStatus()} while a trim was still in flight`
	end

	local ok: boolean = env.settle(reading)
	if not ok or #maps.peek(MAP) ~= keep then
		return false, `the read settled {ok} with {#maps.peek(MAP)} rows in the map, not {keep}`
	end

	return true, nil
end
