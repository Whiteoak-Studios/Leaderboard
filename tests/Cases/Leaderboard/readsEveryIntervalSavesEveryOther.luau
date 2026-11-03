--[[
    At interval = 90 the automation reads as the object is built and every
    90 s after, and saves every second tick, at 90, 270 and 450 s
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Cadence-Daily"
local USER: number = 1
local INTERVAL: number = 90
local STEP: number = 10 -- An increment every step, so every save has an amount to write
local LAST: number = 450
local READS: string = "0, 90, 180, 270, 360, 450"
local SAVES: string = "90, 270, 450"

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local start: number = env.clock.now()
	local reads: { number } = {}
	local saves: { number } = {}

	--[[
	    Records when the clock stands as each read or totals write is made
	--]]

	local function record(holder: any, getter: string, method: string, times: { number })
		local get: any = holder[getter]

		holder[getter] = function (self: any, name: string): any
			local store: any = get(self, name)
			local call: any = store[method]

			store[method] = function (...: any): ...any
				table.insert(times, math.round(env.clock.now() - start))

				return call(...)
			end

			return store
		end
	end

	record(env.services.MemoryStoreService, "GetSortedMap", "GetRangeAsync", reads)
	record(env.services.DataStoreService, "GetDataStore", "UpdateAsync", saves)

	local object: any = Leaderboard.new({ Daily = KEY }, { automation = true, interval = INTERVAL })
	for _ = 1, LAST / STEP do
		object:increment({ Daily = true }, USER, 1)
		env.clock.advance(STEP)
	end

	if table.concat(reads, ", ") ~= READS then
		return false, `the automation read at {table.concat(reads, ", ")} s, not {READS}`
	end

	if table.concat(saves, ", ") ~= SAVES then
		return false, `the automation saved at {table.concat(saves, ", ")} s, not {SAVES}`
	end

	env.settle(object:destroy())

	return true, nil
end
