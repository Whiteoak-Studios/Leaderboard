--[[
    Once a server has read a full board, a new period's map counts as not
    full until it reads that map, so the period's first rows go in
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Turn-Daily"
local TODAY: string = `{KEY}:{Start.DAY}`
local TOMORROW: string = `{KEY}:{Start.DAY + 1}`
local FLOOR: number = 1000
local LOW_PLAYER: number = 9999
local LOW_VALUE: number = 1 -- Under every filled row's value
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local keep: number = env.require("Constants").KEPT_ROWS
	local board: any = env.require("Board/init").new("Daily", KEY)

	env.settle(board:read(AMOUNT))
	Boards.fill(env, board, keep, FLOOR)

	env.settle(board:read(AMOUNT))
	env.settle(board:update(LOW_PLAYER, Boards.set(LOW_VALUE)))

	if #env.services.MemoryStoreService.peek(TODAY) ~= keep then
		return false, "a full board took a row below its cutoff"
	end

	env.clock.advance(Start.TO_MIDNIGHT)
	env.settle(board:update(LOW_PLAYER, Boards.set(LOW_VALUE)))

	local items: { any } = env.services.MemoryStoreService.peek(TOMORROW)
	if #items ~= 1 or items[1].key ~= `{LOW_PLAYER}` then
		return false, `the new day's map held {#items} rows before its first read, not the low player's`
	end

	return true, nil
end
