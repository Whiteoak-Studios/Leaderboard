--[[
    Every row's userId is a number, on the ordered store and the sorted maps
    alike, and it is the id the value was written for
--]]

--!strict
local Environment = require("../../Environment")

local USER: number = 4242
local VALUE: number = 9

local BOARDS: { [string]: any } = {
	AllTime = "Ids-AllTime",
	Daily = "Ids-Daily",
	Wipe = { expirySeconds = 3600, key = "Ids-Wipe" },
}

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new(BOARDS)

	-- The boards' first read, after which the set writes the player's rows
	env.settle(object:getAll("All"))
	env.settle(object:set("All", USER, VALUE))

	local read: boolean, results: any = env.settle(object:getAll("All"))
	if not read or #results ~= 3 then
		return false, `the read gave {read and #results} boards: {results}`
	end

	for _, result: any in results do
		local row: any = result.rows[1]
		if not row or type(row.userId) ~= "number" or row.userId ~= USER then
			return false, `{result.board}'s row has the userId {row and row.userId}, a {row and typeof(row.userId)}`
		end
	end

	return true, nil
end
