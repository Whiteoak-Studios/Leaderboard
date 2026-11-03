--[[
    A key of 51 characters is refused with the real message on both kinds of
    DataStore and writes nothing, and one of 50 is written
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local MESSAGE: string = "102: Key name exceeds the 50 character limit."
local STORE: string = "Totals"
local ORDERED: string = "AllTime"
local LONGEST: number = 50
local VALUE: number = 1

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.DataStoreService
	local standard: any = service:GetDataStore(STORE)
	local ordered: any = service:GetOrderedDataStore(ORDERED)
	local longest: string = string.rep("k", LONGEST)
	local tooLong: string = string.rep("k", LONGEST + 1)

	local function write(): number
		return VALUE
	end

	standard:UpdateAsync(longest, write)
	ordered:UpdateAsync(longest, write)

	Refuses(MESSAGE, function ()
		standard:UpdateAsync(tooLong, write)
	end)

	Refuses(MESSAGE, function ()
		ordered:UpdateAsync(tooLong, write)
	end)

	if service.peek(STORE, longest) ~= VALUE or service.peekOrdered(ORDERED, longest) ~= VALUE then
		return false, `a {LONGEST}-character key was not written`
	end

	if service.peek(STORE, tooLong) ~= nil or service.peekOrdered(ORDERED, tooLong) ~= nil then
		return false, "a refused key was written"
	end

	return true, nil
end
