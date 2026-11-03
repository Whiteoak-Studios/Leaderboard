--[[
    set throws at the call on a bad value or userId, naming it, and a
    function whose return breaks the same rule rejects, naming the value,
    and leaves every board's stored value as it was
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local DAILY: string = "Refuse-Set-Daily"
local ALL_TIME: string = "Refuse-Set-AllTime"
local USER: number = 1
local STORED: number = 10
local LOWER_BY: number = 25 -- Takes the stored value below zero
local FRACTION: number = 0.5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = DAILY, AllTime = ALL_TIME })

	local stored: boolean, reason: any = env.settle(object:set("All", USER, STORED))
	if not stored then
		return false, `the first set rejected: {reason}`
	end

	local values: { any } = { -1, 1.5, math.huge, 0 / 0, "5" }
	for _, value: any in values do
		local ran: boolean, thrown: any = pcall(object.set, object, "All", USER, value)
		if ran or not Mentions(thrown, tostring(value)) then
			return false, `set took the value {value}, or threw without naming it: {thrown}`
		end
	end

	local userIds: { any } = { 2.5, -math.huge, "1" }
	for _, userId: any in userIds do
		local ran: boolean, thrown: any = pcall(object.set, object, "All", userId, STORED)
		if ran or not Mentions(thrown, tostring(userId)) then
			return false, `set took the userId {userId}, or threw without naming it: {thrown}`
		end
	end

	local transforms: { [string]: (old: number) -> number } = {
		[`{STORED - LOWER_BY}`] = function (old: number): number
			return old - LOWER_BY
		end,

		[`{STORED + FRACTION}`] = function (old: number): number
			return old + FRACTION
		end,
	}

	for named: string, transform: (old: number) -> number in transforms do
		local set: boolean, refused: any = env.settle(object:set("All", USER, transform))
		if set or not Mentions(refused, named) then
			return false, `set's function returning {named} resolved, or rejected without naming it: {refused}`
		end
	end

	local total: number? = service.peek(DAILY, USER).total
	local highest: number? = service.peekOrdered(ALL_TIME, USER)
	if total ~= STORED or highest ~= STORED then
		return false, `a refused set changed the stored values to {total} and {highest}`
	end

	return true, nil
end
