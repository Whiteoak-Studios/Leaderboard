--[[
    At shutdown the one BindToClose function destroys every live object and
    returns only once their last saves have landed on every board, a rolling
    one included, and throws nothing
--]]

--!strict
local Environment = require("../../Environment")

local DAILY: string = "Shutdown-Daily"
local ALL_TIME: string = "Shutdown-AllTime"
local WIPE: string = "Shutdown-Wipe"
local USER: number = 1
local AMOUNT: number = 6
local DELAY: number = 5
local WRITES: number = 3

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({
		Daily = DAILY,
		AllTime = ALL_TIME,
		Wipe = { expirySeconds = 3600, key = WIPE },
	})

	object:increment("All", USER, AMOUNT)
	for _ = 1, WRITES do
		data.delayNext("UpdateAsync", DELAY)
	end

	if not env.close() then
		return false, "BindToClose did not return within the 30 s the engine gives it"
	end

	local daily: any = data.peek(DAILY, USER)
	local wipe: any = data.peek(WIPE, USER)
	local highest: number? = data.peekOrdered(ALL_TIME, USER)
	if not daily or daily.total ~= AMOUNT or not wipe or wipe.total ~= AMOUNT or highest ~= AMOUNT then
		local landed: string = `Daily {daily and daily.total}, Wipe {wipe and wipe.total}, AllTime {highest}`
		return false, `BindToClose returned before the last save landed: {landed}`
	end

	local ran: boolean = pcall(object.increment, object, "All", USER, AMOUNT)
	if ran then
		return false, "the object took an increment after the shutdown destroyed it"
	end

	return true, nil
end
