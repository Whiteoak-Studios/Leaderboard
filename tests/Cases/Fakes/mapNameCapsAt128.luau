--[[
    A sorted map name of 129 characters is refused with the real message,
    and one of 128 is taken
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local LONGEST: number = 128

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.MemoryStoreService

	service:GetSortedMap(string.rep("m", LONGEST))

	Refuses("InvalidParameter: The provided sorted map name is not valid.", function ()
		service:GetSortedMap(string.rep("m", LONGEST + 1))
	end)

	return true, nil
end
