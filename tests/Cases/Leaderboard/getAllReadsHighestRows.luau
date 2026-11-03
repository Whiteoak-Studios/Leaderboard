--[[
    getAll gives each board's highest rows, highest first and at most
    MAX_ROWS, ranked from 1, on the ordered store and the sorted maps alike,
    with the results in the order of the boards' names
--]]

--!strict
local Environment = require("../../Environment")

local USERS: number = 150
local SCALE: number = 10 -- Each player's value is their id times this

local BOARDS: { [string]: any } = {
	Wipe = { expirySeconds = 86400, key = "Highest-Wipe" },
	Daily = "Highest-Daily",
	AllTime = "Highest-AllTime",
}

local ORDER: string = "AllTime, Daily, Wipe"

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new(BOARDS)

	-- The boards' first read, after which each write takes its row
	env.settle(object:getAll("All"))

	for userId: number = 1, USERS do
		local set: boolean, reason: any = env.settle(object:set("All", userId, userId * SCALE))
		if not set then
			return false, `setting player {userId} rejected: {reason}`
		end
	end

	local read: boolean, results: any = env.settle(object:getAll("All"))
	if not read then
		return false, `the read rejected: {results}`
	end

	local names: { string } = {}
	for _, result: any in results do
		table.insert(names, result.board)
	end

	if table.concat(names, ", ") ~= ORDER then
		return false, `the results came as {table.concat(names, ", ")}, not {ORDER}`
	end

	for _, result: any in results do
		if #result.rows ~= Constants.MAX_ROWS then
			return false, `{result.board} gave {#result.rows} rows, not {Constants.MAX_ROWS}`
		end

		for rank: number, row: any in result.rows do
			local userId: number = USERS - rank + 1
			if row.rank ~= rank or row.userId ~= userId or row.value ~= userId * SCALE then
				return false, `{result.board}'s row {rank} is {row.rank}, {row.userId}, {row.value}`
			end
		end
	end

	return true, nil
end
