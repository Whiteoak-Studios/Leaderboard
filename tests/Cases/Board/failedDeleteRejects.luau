--[[
    delete rejects when either removal fails, on the map or the totals
    store, and a delete after it removes what is left
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Undeleted-Daily"
local MAP: string = `{KEY}:{Start.DAY}`
local ALL_TIME: string = "Undeleted-AllTime"
local USER: number = 1
local VALUE: number = 5
local AMOUNT: number = 100

type Failure = { service: string, label: string }

return function (): (boolean, string | nil)
	local failures: { Failure } = {
		{ service = "MemoryStoreService", label = "map" },
		{ service = "DataStoreService", label = "totals" },
	}

	for _, failure: Failure in failures do
		local env: any = Environment.new()
		local board: any = env.require("Board/init").new("Daily", KEY)

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.add(VALUE)))

		env.services[failure.service].failNext("RemoveAsync")
		if env.settle(board:delete(USER)) then
			return false, `delete resolved though its {failure.label} removal failed`
		end

		if not env.settle(board:delete(USER)) then
			return false, `the delete after a failed {failure.label} removal rejected`
		end

		if #env.services.MemoryStoreService.peek(MAP) ~= 0 or env.services.DataStoreService.peek(KEY, USER) ~= nil then
			return false, `the delete after a failed {failure.label} removal left an entry`
		end
	end

	local env: any = Environment.new()
	local board: any = env.require("Board/init").new("AllTime", ALL_TIME)
	env.settle(board:update(USER, Boards.set(VALUE)))

	env.services.DataStoreService.failNext("RemoveAsync")
	if env.settle(board:delete(USER)) or env.services.DataStoreService.peekOrdered(ALL_TIME, USER) ~= VALUE then
		return false, "AllTime's delete resolved, or removed the entry, though RemoveAsync failed"
	end

	return true, nil
end
