--[[
    A tick whose read fails fires nothing and the next tick reads again,
    and a tick whose save fails keeps the amount for the next save, so a
    failure never ends the automation
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Survive-Daily"
local USER: number = 1
local AMOUNT: number = 1
local INTERVAL: number = 90

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY }, { automation = true, interval = INTERVAL })

	local fired: number = 0
	object.updated:Connect(function ()
		fired += 1
	end)

	-- The tick at 90 s fails its read
	env.services.MemoryStoreService.failNext("GetRangeAsync")
	env.clock.advance(INTERVAL)
	if fired ~= 0 then
		return false, "the tick whose read failed fired updated"
	end

	-- The tick at 180 s reads again
	env.clock.advance(INTERVAL)
	if fired ~= 1 then
		return false, `the tick after the failed read fired {fired} times`
	end

	-- The save at 270 s fails, and the one at 450 s writes the amount it kept
	object:increment({ Daily = true }, USER, AMOUNT)
	env.services.DataStoreService.failNext("UpdateAsync")
	env.clock.advance(INTERVAL)
	if env.services.DataStoreService.peek(KEY, USER) ~= nil then
		return false, "the save made to fail wrote the amount"
	end

	env.clock.advance(INTERVAL * 2)

	local record: any = env.services.DataStoreService.peek(KEY, USER)
	if fired ~= 4 or not record or record.total ~= AMOUNT then
		return false, `after the failed save the loop fired {fired} times and saved {record and record.total}`
	end

	env.settle(object:destroy())

	return true, nil
end
