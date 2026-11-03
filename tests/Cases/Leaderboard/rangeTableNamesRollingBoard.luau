--[[
    A range table naming a rolling board cuts that board's rows and leaves
    the rest at MAX_ROWS, in getAll and in the automation's recordCount,
    and a range outside 1 to MAX_ROWS or naming no board throws
--]]

--!strict
local Environment = require("../../Environment")

local USERS: number = 10
local CUT: number = 3
local NUMBERED: number = 4
local INTERVAL: number = 90

local BOARDS: { [string]: any } = {
	Daily = "Range-Daily",
	Wipe = { expirySeconds = 3600, key = "Range-Wipe" },
}

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")
	local object: any =
		Leaderboard.new(BOARDS, { automation = true, interval = INTERVAL, recordCount = { Wipe = CUT } })

	-- The automation's first read ran as the object was built, so every write takes its row
	for userId: number = 1, USERS do
		env.settle(object:set("All", userId, userId))
	end

	local read: boolean, results: any = env.settle(object:getAll("All", { Wipe = CUT }))
	if not read or #results[1].rows ~= USERS or #results[2].rows ~= CUT then
		return false, `getAll with a range table gave {read and #results[1].rows} and {read and #results[2].rows} rows`
	end

	local numbered: boolean, single: any = env.settle(object:getAll({ Daily = true }, NUMBERED))
	if not numbered or #single ~= 1 or #single[1].rows ~= NUMBERED then
		return false, `getAll of Daily with a range of {NUMBERED} gave {numbered and #single[1].rows} rows`
	end

	local seen: { [string]: number } = {}
	object.boardUpdated:Connect(function (result: any)
		seen[result.board] = #result.rows
	end)

	env.clock.advance(INTERVAL)
	if seen.Daily ~= USERS or seen.Wipe ~= CUT then
		return false, `the automation read {seen.Daily} Daily rows and {seen.Wipe} Wipe rows`
	end

	local ranges: { any } = { 0, Constants.MAX_ROWS + 1, 2.5, "10", { Nope = CUT }, { Wipe = 0 }, { Wipe = true } }
	for _, range: any in ranges do
		local ran: boolean = pcall(object.getAll, object, "All", range)
		if ran then
			return false, `getAll took the range {range}`
		end
	end

	env.settle(object:destroy())

	return true, nil
end
