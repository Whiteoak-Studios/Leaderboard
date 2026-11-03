--[[
    increment throws at the call on an amount that is negative, fractional
    or not finite, and on a userId that is not a whole number, naming the
    value, and queues nothing, while a negative userId passes
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Refuse-Daily"
local USER: number = 1
local TEST_PLAYER: number = -1 -- Studio's test players have negative ids
local AMOUNT: number = 2

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	local amounts: { any } = { -1, 1.5, math.huge, -math.huge, 0 / 0, "5" }
	for _, amount: any in amounts do
		local ran: boolean, thrown: any = pcall(object.increment, object, { Daily = true }, USER, amount)
		if ran or not Mentions(thrown, tostring(amount)) then
			return false, `increment took the amount {amount}, or threw without naming it: {thrown}`
		end
	end

	local userIds: { any } = { 1.5, math.huge, 0 / 0, "1", true }
	for _, userId: any in userIds do
		local ran: boolean, thrown: any = pcall(object.increment, object, { Daily = true }, userId, AMOUNT)
		if ran or not Mentions(thrown, tostring(userId)) then
			return false, `increment took the userId {userId}, or threw without naming it: {thrown}`
		end
	end

	object:increment({ Daily = true }, TEST_PLAYER, AMOUNT)

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	local refused: any = env.services.DataStoreService.peek(KEY, USER)
	if refused ~= nil then
		return false, `a refused increment was queued and saved as {refused.total}`
	end

	local record: any = env.services.DataStoreService.peek(KEY, TEST_PLAYER)
	if not record or record.total ~= AMOUNT then
		return false, `the test player's increment saved {record and record.total}, not {AMOUNT}`
	end

	return true, nil
end
