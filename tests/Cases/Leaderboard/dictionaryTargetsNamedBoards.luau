--[[
    A dictionary of boards queues for exactly the boards it names, and
    "All" for every board the object holds
--]]

--!strict
local Environment = require("../../Environment")

local ALL_TIME: string = "Targets-AllTime"
local DAILY: string = "Targets-Daily"
local WEEKLY: string = "Targets-Weekly"
local NAMED: number = 1
local EVERY: number = 2
local NAMED_AMOUNT: number = 5
local EVERY_AMOUNT: number = 2

--[[
    A player's total on a periodic board, or nil when none was saved
--]]

local function total(env: any, key: string, userId: number): number | nil
	local record: any = env.services.DataStoreService.peek(key, userId)

	return record and record.total
end

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ AllTime = ALL_TIME, Daily = DAILY, Weekly = WEEKLY })

	object:increment({ Daily = true, Weekly = true }, NAMED, NAMED_AMOUNT)
	object:increment("All", EVERY, EVERY_AMOUNT)

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	local named: { any } = {
		total(env, DAILY, NAMED),
		total(env, WEEKLY, NAMED),
		env.services.DataStoreService.peekOrdered(ALL_TIME, NAMED),
	}

	if named[1] ~= NAMED_AMOUNT or named[2] ~= NAMED_AMOUNT or named[3] ~= nil then
		return false, `the dictionary saved Daily {named[1]}, Weekly {named[2]} and AllTime {named[3]}`
	end

	local every: { any } = {
		total(env, DAILY, EVERY),
		total(env, WEEKLY, EVERY),
		env.services.DataStoreService.peekOrdered(ALL_TIME, EVERY),
	}

	if every[1] ~= EVERY_AMOUNT or every[2] ~= EVERY_AMOUNT or every[3] ~= EVERY_AMOUNT then
		return false, `"All" saved Daily {every[1]}, Weekly {every[2]} and AllTime {every[3]}`
	end

	return true, nil
end
