--[[
    A sorted map key of 129 characters is refused with the real message and
    writes nothing, and one of 128 is written
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local MAP: string = "Daily:1"
local LONGEST: number = 128
local VALUE: number = 7
local EXPIRATION: number = 60

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.MemoryStoreService
	local map: any = service:GetSortedMap(MAP)
	local longest: string = string.rep("k", LONGEST)

	local function total(): (number, number)
		return VALUE, VALUE
	end

	map:UpdateAsync(longest, total, EXPIRATION)

	Refuses("InvalidParameter: The provided key is not valid.", function ()
		map:UpdateAsync(string.rep("k", LONGEST + 1), total, EXPIRATION)
	end)

	local entries: { any } = service.peek(MAP)
	if #entries ~= 1 or entries[1].key ~= longest then
		return false, `the map held {#entries} entries`
	end

	return true, nil
end
