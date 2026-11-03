--[[
    A trim that fails rejects nothing: the read resolves with its rows, and
    the next read trims what the failed one left
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Untrimmed-Daily"
local MAP: string = `{KEY}:{Start.DAY}`
local EXTRA: number = 5 -- Rows past the slack
local FAILING: number = 2 -- Trims that fail
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local keep: number = env.require("Constants").KEPT_ROWS
	local maps: any = env.services.MemoryStoreService
	local board: any = env.require("Board/init").new("Daily", KEY)

	env.settle(board:read(AMOUNT))
	Boards.fill(env, board, keep + EXTRA)

	maps.failNext("RemoveAsync", FAILING)
	local ok: boolean, rows: any = env.settle(board:read(AMOUNT))

	if not ok or #rows ~= AMOUNT or rows[1].value ~= keep + EXTRA then
		return false, `a read whose trims failed resolved {ok} with {ok and #rows} rows`
	end

	if #maps.peek(MAP) ~= keep + FAILING then
		return false, `the map held {#maps.peek(MAP)} rows after {FAILING} failed trims, not {keep + FAILING}`
	end

	env.settle(board:read(AMOUNT))
	if #maps.peek(MAP) ~= keep then
		return false, `the next read left {#maps.peek(MAP)} rows, not {keep}`
	end

	return true, nil
end
