--[[
    A store holds a copy of what it is given, so a caller changing a result,
    or a transform changing the table it read and then canceling, alters
    nothing
--]]

--!strict
local Environment = require("../../Environment")

local STORE: string = "Totals"
local KEY: string = "1"
local GIVEN: number = 1
local CALLER_CHANGE: number = 99 -- What the caller writes into the result it got
local TRANSFORM_CHANGE: number = 50 -- What the canceling transform writes into the table it read

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.DataStoreService
	local store: any = service:GetDataStore(STORE)

	local result: any = store:UpdateAsync(KEY, function (): { total: number }
		return { total = GIVEN }
	end)
	result.total = CALLER_CHANGE

	store:UpdateAsync(KEY, function (old: { total: number }): nil
		old.total = TRANSFORM_CHANGE
		return nil
	end)

	if service.peek(STORE, KEY).total ~= GIVEN then
		return false, `the store held {service.peek(STORE, KEY).total}, where it was given {GIVEN}`
	end

	return true, nil
end
