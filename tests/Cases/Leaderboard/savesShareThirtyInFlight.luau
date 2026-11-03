--[[
    Three objects saving full queues at once keep no more than MAX_IN_FLIGHT
    board writes in flight across them, and still write every entry
--]]

--!strict
local Environment = require("../../Environment")

local KEYS: { string } = { "Pool-Daily-1", "Pool-Daily-2", "Pool-Daily-3" }
local USERS: number = 60
local DELAY: number = 10

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")

	-- Counts the totals writes running at once across every store, each held open by its delay
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

	local objects: { any } = {}
	for _, key: string in KEYS do
		local object: any = Leaderboard.new({ Daily = key })
		for userId: number = 1, USERS do
			object:increment({ Daily = true }, userId, userId)
			service.delayNext("UpdateAsync", DELAY)
		end

		table.insert(objects, object)
	end

	-- Every save starts in the same tick, as automated objects built together save
	local saves: { any } = {}
	for _, object: any in objects do
		table.insert(saves, object:save())
	end

	for index: number, save: any in saves do
		local saved: boolean, reason: any = env.settle(save)
		if not saved then
			return false, `object {index}'s save rejected: {reason}`
		end
	end

	if most ~= Constants.MAX_IN_FLIGHT then
		return false, `three saves kept {most} writes in flight at once, not {Constants.MAX_IN_FLIGHT}`
	end

	for _, key: string in KEYS do
		for userId: number = 1, USERS do
			local record: any = service.peek(key, userId)
			if not record or record.total ~= userId then
				return false, `player {userId}'s total on {key} is {record and record.total}, not {userId}`
			end
		end
	end

	return true, nil
end
