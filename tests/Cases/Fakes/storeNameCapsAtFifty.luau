--[[
    A store name of 51 characters is refused with the real message on both
    kinds of DataStore, and one of 50 is taken
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local MESSAGE: string = "DataStore name is too long"
local LONGEST: number = 50

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.DataStoreService
	local longest: string = string.rep("s", LONGEST)
	local tooLong: string = string.rep("s", LONGEST + 1)

	service:GetDataStore(longest)
	service:GetOrderedDataStore(longest)

	Refuses(MESSAGE, function ()
		service:GetDataStore(tooLong)
	end)

	Refuses(MESSAGE, function ()
		service:GetOrderedDataStore(tooLong)
	end)

	return true, nil
end
