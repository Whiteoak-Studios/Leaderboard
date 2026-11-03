--[[
    A sorted map takes a value of 32 kB as JSON and refuses one byte more,
    keeping the value it held
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local MAP: string = "Daily:1"
local KEY: string = "1"
local SORT_KEY: number = 1
local EXPIRATION: number = 60
local LIMIT: number = 32 * 1024
local QUOTES: number = 2 -- What JSON adds around a string

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.MemoryStoreService
	local map: any = service:GetSortedMap(MAP)
	local largest: string = string.rep("v", LIMIT - QUOTES)

	map:UpdateAsync(KEY, function (): (string, number)
		return largest, SORT_KEY
	end, EXPIRATION)

	Refuses(`The value for {KEY} is {LIMIT + 1} bytes, past the {LIMIT} a sorted map holds`, function ()
		map:UpdateAsync(KEY, function (): (string, number)
			return `{largest}v`, SORT_KEY
		end, EXPIRATION)
	end)

	if service.peek(MAP)[1].value ~= largest then
		return false, "a refused value replaced the one the map held"
	end

	return true, nil
end
