--[[
    delete removes one user and board and leaves the user's other boards, a
    delete of what holds nothing is harmless, and a user leaves with their last
--]]

--!strict
local Environment = require("../../Environment")

local USER_ID: number = 1
local NOTHING_QUEUED_ID: number = 2
local DAILY: string = "Daily"
local WEEKLY: string = "Weekly"
local MONTHLY: string = "Monthly"
local AMOUNT: number = 5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Queue: any = env.require("Queue")
	local queue: any = Queue.new()

	queue:add(USER_ID, DAILY, AMOUNT)
	queue:add(USER_ID, WEEKLY, AMOUNT)
	queue:delete(USER_ID, DAILY)

	-- The object's delete deletes every board it names, queued or not
	queue:delete(USER_ID, MONTHLY)
	queue:delete(NOTHING_QUEUED_ID, DAILY)

	local entries: { any } = queue:take()
	local entry: any = entries[1]
	if #entries ~= 1 or entry.userId ~= USER_ID or entry.board ~= WEEKLY or entry.amount ~= AMOUNT then
		return false, `after the deletes take held {#entries} entries, the first {entry and entry.board}, not {WEEKLY}`
	end

	-- The queue holds nothing per player beyond what is queued
	queue:add(USER_ID, DAILY, AMOUNT)
	queue:delete(USER_ID, DAILY)
	if queue._amounts[USER_ID] ~= nil then
		return false, "a user whose last queued board was deleted is still held"
	end

	return true, nil
end
