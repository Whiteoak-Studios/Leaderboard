--[[
    Twenty thousand adds over a few users and boards finish without yielding,
    and take returns each user and board's exact sum
--]]

--!strict
local task = require("@lune/task")

local Environment = require("../../Environment")

local ADDS: number = 20000
local USER_IDS: { number } = { 1, 2 }
local BOARDS: { string } = { "Daily", "Weekly" }

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Queue: any = env.require("Queue")
	local queue: any = Queue.new()

	local rounds: number = ADDS // (#USER_IDS * #BOARDS)
	local expected: { [string]: number } = {}
	local finished: boolean = false

	-- A spawned thread runs until it yields, so one that yields returns here unfinished
	task.spawn(function ()
		for round: number = 1, rounds do
			for _, userId: number in USER_IDS do
				for _, board: string in BOARDS do
					local pair: string = `{userId} on {board}`
					expected[pair] = (expected[pair] or 0) + round
					queue:add(userId, board, round)
				end
			end
		end

		finished = true
	end)

	if not finished then
		return false, `the {ADDS} adds yielded before they finished`
	end

	local entries: { any } = queue:take()
	if #entries ~= #USER_IDS * #BOARDS then
		return false, `take returned {#entries} entries for {#USER_IDS * #BOARDS} pairs`
	end

	for _, entry: any in entries do
		local pair: string = `{entry.userId} on {entry.board}`
		if entry.amount ~= expected[pair] then
			return false, `user {pair} queued {entry.amount}, not {expected[pair]}`
		end

		expected[pair] = nil -- A pair returned twice finds nothing left to match
	end

	return true, nil
end
