--[[
    Once the lookup a read started has answered, the next read gives each
    row the names it found, and a row whose id it did not return keeps nils
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Named-Daily"
local NAMED: number = 1
local UNNAMED: number = 2
local LOOKUP: number = 5 -- How long the name lookup takes to answer

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local users: any = env.services.UserService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	-- The board's first read, after which the sets write both rows
	env.settle(object:getAll("All"))
	env.settle(object:set("All", NAMED, NAMED))
	env.settle(object:set("All", UNNAMED, UNNAMED))

	users.set(NAMED, "builderman", "Builder")
	users.delayNext("GetUserInfosByUserIdsAsync", LOOKUP)

	env.settle(object:getAll("All"))
	env.clock.advance(LOOKUP)

	local _, results: any = env.settle(object:getAll("All"))
	local rows: { [number]: any } = {}
	for _, row: any in results[1].rows do
		rows[row.userId] = row
	end

	local named: any, unnamed: any = rows[NAMED], rows[UNNAMED]
	if named.username ~= "builderman" or named.displayName ~= "Builder" then
		return false, `the next read named player {NAMED} {named.username} and {named.displayName}`
	end

	if unnamed.username ~= nil or unnamed.displayName ~= nil then
		return false, `player {UNNAMED}, whom the lookup did not return, read {unnamed.username}`
	end

	return true, nil
end
