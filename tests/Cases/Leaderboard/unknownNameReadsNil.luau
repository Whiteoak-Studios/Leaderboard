--[[
    A read resolves without waiting on the name lookup it starts, and a row
    whose name the cache does not hold yet has nil names
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Unnamed-Daily"
local USER: number = 1
local VALUE: number = 10
local LOOKUP: number = 30 -- How long the name lookup takes to answer

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local users: any = env.services.UserService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	-- The board's first read, after which the set writes the player's row
	env.settle(object:getAll("All"))
	env.settle(object:set("All", USER, VALUE))

	users.set(USER, "builderman", "Builder")
	users.delayNext("GetUserInfosByUserIdsAsync", LOOKUP)

	local read: any = object:getAll("All")
	if read:getStatus() ~= Environment.RESOLVED then
		return false, `the read was {read:getStatus()} while the name lookup was in flight`
	end

	local _, results: any = env.settle(read)
	local row: any = results[1].rows[1]
	if row.userId ~= USER or row.username ~= nil or row.displayName ~= nil then
		return false, `the row read {row.userId}, {row.username} and {row.displayName} before the lookup answered`
	end

	return true, nil
end
