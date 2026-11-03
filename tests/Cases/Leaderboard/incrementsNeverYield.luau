--[[
    Twenty thousand increments with a dictionary naming one board run
    without yielding or touching a store, and the save writes their sum
    to that board alone
--]]

--!strict
local task = require("@lune/task")

local Calls = require("../../Calls")
local Environment = require("../../Environment")

local DAILY: string = "Many-Daily"
local WEEKLY: string = "Many-Weekly"
local CALLS: number = 20000
local USERS: number = 500

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = DAILY, Weekly = WEEKLY })
	local stores: { { any } } = Calls(data, "GetDataStore")
	local maps: { { any } } = Calls(env.services.MemoryStoreService, "GetSortedMap")

	-- A thread that yields hands control back here before it sets finished
	local finished: boolean = false
	task.spawn(function ()
		for call: number = 1, CALLS do
			object:increment({ Daily = true }, call % USERS + 1, 1)
		end

		finished = true
	end)

	if not finished then
		return false, "an increment yielded"
	end

	if #stores > 0 or #maps > 0 then
		return false, `the increments made {#stores + #maps} store calls`
	end

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	for userId: number = 1, USERS do
		local record: any = data.peek(DAILY, userId)
		if not record or record.total ~= CALLS / USERS or data.peek(WEEKLY, userId) then
			return false, `player {userId} saved {record and record.total} to Daily, or something to Weekly`
		end
	end

	return true, nil
end
