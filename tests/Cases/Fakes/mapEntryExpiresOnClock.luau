--[[
    A sorted map entry lives until its expiration passes on the fake clock,
    then leaves every read: peek, GetRangeAsync and UpdateAsync's transform
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local MAP: string = "Hourly:1"
local KEY: string = "1"
local VALUE: number = 40
local REWRITE: number = 1 -- What the write after the expiry stores
local COUNT: number = 1 -- Items the range read asks for
local EXPIRATION: number = 10
local JUST_BEFORE: number = 9.5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.MemoryStoreService
	local map: any = service:GetSortedMap(MAP)

	map:UpdateAsync(KEY, function (): (number, number)
		return VALUE, VALUE
	end, EXPIRATION)

	env.clock.advance(JUST_BEFORE)
	if #service.peek(MAP) ~= 1 then
		return false, "the entry left before its expiration"
	end

	env.clock.advance(EXPIRATION - JUST_BEFORE)
	if #service.peek(MAP) ~= 0 or #map:GetRangeAsync(roblox.Enum.SortDirection.Descending, COUNT) ~= 0 then
		return false, "the entry outlived its expiration"
	end

	local seen: any = false
	map:UpdateAsync(KEY, function (old: any): (number, number)
		seen = old
		return REWRITE, REWRITE
	end, EXPIRATION)

	if seen ~= nil then
		return false, `the transform read the expired value {seen}`
	end

	return true, nil
end
