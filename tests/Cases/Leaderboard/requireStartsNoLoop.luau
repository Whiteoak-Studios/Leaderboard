--[[
    Requiring the package starts no thread and calls no store, so nothing
    runs until a game builds an object
--]]

--!strict
local Calls = require("../../Calls")
local Environment = require("../../Environment")

local LATER: number = 600 -- Fake seconds, long enough for a loop the require started to come round

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local spawns: { { any } } = Calls(env.clock.task, "spawn")
	local defers: { { any } } = Calls(env.clock.task, "defer")
	local delays: { { any } } = Calls(env.clock.task, "delay")
	local maps: { { any } } = Calls(env.services.MemoryStoreService, "GetSortedMap")
	local stores: { { any } } = Calls(data, "GetDataStore")
	local ordered: { { any } } = Calls(data, "GetOrderedDataStore")

	env.require("init")
	env.clock.advance(LATER)

	local threads: number = #spawns + #defers + #delays
	local calls: number = #maps + #stores + #ordered
	if threads > 0 or calls > 0 then
		return false, `requiring the package started {threads} threads and made {calls} store calls`
	end

	return true, nil
end
