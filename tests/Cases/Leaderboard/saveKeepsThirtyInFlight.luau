--[[
    A save of more entries than MAX_IN_FLIGHT keeps exactly that many board
    writes in flight at its busiest, and still writes every entry
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Pool-Daily"
local USERS: number = 60
local DELAY: number = 10

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")

	-- Counts the totals writes running at once, each held open by its delay
	local inFlight: number = 0
	local most: number = 0
	local getDataStore: any = service.GetDataStore

	service.GetDataStore = function (self: any, name: string): any
		local store: any = getDataStore(self, name)
		local update: any = store.UpdateAsync

		store.UpdateAsync = function (...: any): (any, any)
			inFlight += 1
			most = math.max(most, inFlight)

			local ran: boolean, value: any, info: any = pcall(update, ...)
			inFlight -= 1
			if not ran then
				error(value, 0)
			end

			return value, info
		end

		return store
	end

	local object: any = Leaderboard.new({ Daily = KEY })
	for userId: number = 1, USERS do
		object:increment({ Daily = true }, userId, userId)
		service.delayNext("UpdateAsync", DELAY)
	end

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	if most ~= Constants.MAX_IN_FLIGHT then
		return false, `the save kept {most} writes in flight at once, not {Constants.MAX_IN_FLIGHT}`
	end

	for userId: number = 1, USERS do
		local record: any = service.peek(KEY, userId)
		if not record or record.total ~= userId then
			return false, `player {userId}'s total is {record and record.total}, not {userId}`
		end
	end

	return true, nil
end
