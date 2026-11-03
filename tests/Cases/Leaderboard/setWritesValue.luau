--[[
    set writes the value itself, and neither the module nor an object has
    SetValues: a number replaces a periodic board's total, a function is
    given the stored one, and AllTime keeps the higher value
--]]

--!strict
local Environment = require("../../Environment")

local DAILY: string = "Set-Daily"
local ALL_TIME: string = "Set-AllTime"
local USER: number = 1
local FIRST: number = 50
local LOWER: number = 20
local ADDED: number = 30

type Step = { value: any, daily: number, allTime: number }

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = DAILY, AllTime = ALL_TIME })

	if Leaderboard.SetValues ~= nil or object.SetValues ~= nil then
		return false, "SetValues still exists"
	end

	-- Each step's value, and what Daily and AllTime then hold
	local steps: { Step } = {
		{ value = FIRST, daily = FIRST, allTime = FIRST },
		{ value = LOWER, daily = LOWER, allTime = FIRST },
		{
			value = function (old: number): number
				return old + ADDED
			end,
			daily = LOWER + ADDED,
			allTime = FIRST + ADDED,
		},
	}

	for step: number, expected: Step in steps do
		local set: boolean, reason: any = env.settle(object:set("All", USER, expected.value))
		if not set then
			return false, `set {step} rejected: {reason}`
		end

		local daily: number = service.peek(DAILY, USER).total
		local allTime: number? = service.peekOrdered(ALL_TIME, USER)
		if daily ~= expected.daily or allTime ~= expected.allTime then
			return false, `after set {step} Daily holds {daily} and AllTime {allTime}`
		end
	end

	return true, nil
end
