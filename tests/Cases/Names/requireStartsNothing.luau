--[[
    Requiring the module asks UserService for nothing and starts no thread,
    so no lookup runs until a read requests one
--]]

--!strict
local Calls = require("../../Calls")
local Environment = require("../../Environment")

local LATER: number = 60 -- Fake seconds, long enough for a loop the require started to come round

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local lookups: { { any } } = Calls(env.services.UserService, "GetUserInfosByUserIdsAsync")
	local spawns: { { any } } = Calls(env.clock.task, "spawn")
	local defers: { { any } } = Calls(env.clock.task, "defer")
	local delays: { { any } } = Calls(env.clock.task, "delay")

	env.require("Names")
	env.clock.advance(LATER)

	local threads: number = #spawns + #defers + #delays
	if #lookups > 0 or threads > 0 then
		return false, `requiring Names made {#lookups} lookups and started {threads} threads`
	end

	return true, nil
end
