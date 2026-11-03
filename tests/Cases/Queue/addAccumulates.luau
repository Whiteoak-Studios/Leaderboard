--[[
    Two adds to one user and board queue their sum, and the same user's
    amount on a second board stays apart from it
--]]

--!strict
local Environment = require("../../Environment")

local USER_ID: number = 1
local DAILY: string = "Daily"
local WEEKLY: string = "Weekly"
local FIRST: number = 5
local SECOND: number = 7
local APART: number = 11

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Queue: any = env.require("Queue")
	local queue: any = Queue.new()

	queue:add(USER_ID, DAILY, FIRST)
	queue:add(USER_ID, DAILY, SECOND)
	queue:add(USER_ID, WEEKLY, APART)

	local expected: { [string]: number } = { [DAILY] = FIRST + SECOND, [WEEKLY] = APART }
	local entries: { any } = queue:take()
	if #entries ~= 2 then
		return false, `take returned {#entries} entries for one user on two boards`
	end

	for _, entry: any in entries do
		if entry.userId ~= USER_ID or entry.amount ~= expected[entry.board] then
			return false, `user {entry.userId} on {entry.board} queued {entry.amount}, not {expected[entry.board]}`
		end

		expected[entry.board] = nil -- A board returned twice finds nothing left to match
	end

	return true, nil
end
