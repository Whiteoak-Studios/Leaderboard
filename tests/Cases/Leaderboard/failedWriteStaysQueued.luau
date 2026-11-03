--[[
    A save whose write fails rejects once its other writes have landed,
    keeps the failed amount queued, and the next save writes it once
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Failed-Daily"
local FIRST: number = 1
local SECOND: number = 2
local FIRST_AMOUNT: number = 5
local SECOND_AMOUNT: number = 7

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	object:increment({ Daily = true }, FIRST, FIRST_AMOUNT)
	object:increment({ Daily = true }, SECOND, SECOND_AMOUNT)
	service.failNext("UpdateAsync")

	local saved: boolean = env.settle(object:save())
	if saved then
		return false, "the save resolved with a failed write"
	end

	local landed: number = 0
	for _, userId: number in { FIRST, SECOND } do
		if service.peek(KEY, userId) then
			landed += 1
		end
	end

	if landed ~= 1 then
		return false, `{landed} of the save's 2 writes landed, where only the failed one should not`
	end

	local resaved: boolean, reason: any = env.settle(object:save())
	if not resaved then
		return false, `the next save rejected: {reason}`
	end

	local first: number = service.peek(KEY, FIRST).total
	local second: number = service.peek(KEY, SECOND).total
	if first ~= FIRST_AMOUNT or second ~= SECOND_AMOUNT then
		return false, `after the next save the totals are {first} and {second}, not {FIRST_AMOUNT} and {SECOND_AMOUNT}`
	end

	return true, nil
end
