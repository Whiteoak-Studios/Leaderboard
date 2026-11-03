--[[
    An UpdateAsync whose key another write changed during its delay re-runs
    its transform on the new value before it commits, so neither write is lost
--]]

--!strict
local Environment = require("../../Environment")

local STORE: string = "Totals"
local KEY: string = "1"
local DELAYED: number = 1 -- What the delayed write adds
local CROSSING: number = 10 -- What the write landing during the delay adds
local DELAY: number = 5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local store: any = service:GetDataStore(STORE)
	local runs: number = 0
	local committed: any = nil

	service.delayNext("UpdateAsync", DELAY)

	-- The delayed write reads 0, then waits on the clock between its transform and its commit
	env.clock.task.spawn(function ()
		committed = store:UpdateAsync(KEY, function (old: number?): number
			runs += 1
			return (old or 0) + DELAYED
		end)
	end)

	store:UpdateAsync(KEY, function (old: number?): number
		return (old or 0) + CROSSING
	end)

	env.clock.advance(DELAY)

	local sum: number = DELAYED + CROSSING
	if committed ~= sum or service.peek(STORE, KEY) ~= sum then
		return false, `the store held {service.peek(STORE, KEY)}, where both writes add to {sum}`
	end

	if runs ~= 2 then
		return false, `the delayed transform ran {runs} times, not 2`
	end

	return true, nil
end
