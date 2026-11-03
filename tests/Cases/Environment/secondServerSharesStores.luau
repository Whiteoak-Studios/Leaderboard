--[[
    A second server shares the first's stores, names and clock, but loads
    its own modules and keeps its own failures
--]]

--!strict
local Environment = require("../../Environment")

local FIXTURE: string = "tests/Fixtures/Package"
local STORE: string = "Totals"
local MAP: string = "Daily:1"
local KEY: string = "1"
local USER: number = 1
local FIRST: number = 5 -- What the first server writes
local ADDED: number = 1 -- What the second server adds to it
local MAP_VALUE: number = 6
local EXPIRATION: number = 60
local DELAY: number = 1

return function (): (boolean, string | nil)
	local first: any = Environment.new({ root = FIXTURE })
	local second: any = Environment.new({ server = first, root = FIXTURE })

	if second.clock ~= first.clock or second.require("init") == first.require("init") then
		return false, "the second server did not share the clock, or shared the modules"
	end

	first.services.DataStoreService:GetDataStore(STORE):UpdateAsync(KEY, function (): number
		return FIRST
	end)

	second.services.DataStoreService:GetDataStore(STORE):UpdateAsync(KEY, function (old: number): number
		return old + ADDED
	end)

	if first.services.DataStoreService.peek(STORE, KEY) ~= FIRST + ADDED then
		return false, "the servers' totals stores were not one store"
	end

	second.services.MemoryStoreService:GetSortedMap(MAP):UpdateAsync(KEY, function (): (number, number)
		return MAP_VALUE, MAP_VALUE
	end, EXPIRATION)

	second.services.UserService.set(USER, "builderman", "Builder")

	if #first.services.MemoryStoreService.peek(MAP) ~= 1 then
		return false, "the servers' sorted maps were not one map"
	end

	if #first.services.UserService:GetUserInfosByUserIdsAsync({ USER }) ~= 1 then
		return false, "the servers did not share the names"
	end

	first.services.DataStoreService.failNext("RemoveAsync")
	second.services.DataStoreService:GetDataStore(STORE):RemoveAsync(KEY)

	if pcall(first.services.DataStoreService:GetDataStore(STORE).RemoveAsync, nil, KEY) then
		return false, "the first server's failure was spent on the second server's call"
	end

	local fired: boolean = false
	second.require("init").task.delay(DELAY, function ()
		fired = true
	end)

	first.clock.advance(DELAY)
	if not fired then
		return false, "advancing the first server's clock did not move the second's"
	end

	return true, nil
end
