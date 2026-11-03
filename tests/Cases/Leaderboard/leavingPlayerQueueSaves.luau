--[[
    A player who leaves before a save keeps their queued amounts, and the
    save writes them to every board they were queued for
--]]

--!strict
local Environment = require("../../Environment")

local DAILY: string = "Leaving-Daily"
local ALL_TIME: string = "Leaving-AllTime"
local USER: number = 7
local AMOUNT: number = 4
local LATER: number = 5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = DAILY, AllTime = ALL_TIME })

	object:increment("All", USER, AMOUNT)
	env.services.Players.remove(USER)
	env.clock.advance(LATER)

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	local record: any = service.peek(DAILY, USER)
	local highest: number? = service.peekOrdered(ALL_TIME, USER)
	if not record or record.total ~= AMOUNT or highest ~= AMOUNT then
		return false, `the leaving player's save wrote {record and record.total} and {highest}, not {AMOUNT}`
	end

	return true, nil
end
