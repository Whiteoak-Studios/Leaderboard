--[[
    take returns one entry per user and board and leaves the queue empty, so
    a second take returns none
--]]

--!strict
local Environment = require("../../Environment")

local FIRST_USER_ID: number = 1
local SECOND_USER_ID: number = 2
local DAILY: string = "Daily"
local WEEKLY: string = "Weekly"
local AMOUNT: number = 3
local PAIRS: number = 3

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Queue: any = env.require("Queue")
	local queue: any = Queue.new()

	queue:add(FIRST_USER_ID, DAILY, AMOUNT)
	queue:add(FIRST_USER_ID, DAILY, AMOUNT)
	queue:add(FIRST_USER_ID, WEEKLY, AMOUNT)
	queue:add(SECOND_USER_ID, DAILY, AMOUNT)

	local entries: { any } = queue:take()
	if #entries ~= PAIRS then
		return false, `take returned {#entries} entries for {PAIRS} pairs`
	end

	local seen: { [string]: boolean } = {}
	for _, entry: any in entries do
		local pair: string = `{entry.userId} on {entry.board}`
		if seen[pair] then
			return false, `take returned user {pair} twice`
		end

		seen[pair] = true
	end

	local again: { any } = queue:take()
	if #again ~= 0 then
		return false, `a second take returned {#again} entries, where the first left the queue empty`
	end

	return true, nil
end
