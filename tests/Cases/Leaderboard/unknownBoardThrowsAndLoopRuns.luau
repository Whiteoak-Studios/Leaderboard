--[[
    A board name the object does not hold throws at the call, alone or
    beside a held one, queuing nothing, and the automation keeps reading
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Unknown-Daily"
local USER: number = 1
local AMOUNT: number = 1
local INTERVAL: number = 90
local TICKS: number = 2

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY }, { automation = true, interval = INTERVAL })

	local reads: number = 0
	object.boardUpdated:Connect(function ()
		reads += 1
	end)

	local ran: boolean, thrown: any = pcall(object.increment, object, { Hourly = true }, USER, AMOUNT)
	if ran or not Mentions(thrown, "Hourly") then
		return false, `increment took a board the object does not hold, or threw without naming it: {thrown}`
	end

	local mixed: boolean = pcall(object.increment, object, { Daily = true, Hourly = true }, USER, AMOUNT)
	if mixed then
		return false, "increment took a dictionary naming a held board and one the object does not hold"
	end

	env.clock.advance(INTERVAL * TICKS)

	if reads ~= TICKS then
		return false, `the automation read {reads} times in {TICKS} intervals after the refused calls`
	end

	-- The tick at the first interval saved, and found nothing queued
	local record: any = env.services.DataStoreService.peek(KEY, USER)
	if record ~= nil then
		return false, `a refused increment was queued and saved as {record.total}`
	end

	env.settle(object:destroy())

	return true, nil
end
