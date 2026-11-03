--[[
    An ordered store refuses a fraction or an infinity with error 103 and
    keeps what it held, and keeps an integer as large as 2^53 exactly
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local MESSAGE: string = "103: double is not allowed in data stores."
local STORE: string = "AllTime"
local KEY: string = "1"
local HELD: number = 5

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.DataStoreService
	local store: any = service:GetOrderedDataStore(STORE)
	local largest: number = 2 ^ 53

	store:UpdateAsync(KEY, function (): number
		return HELD
	end)

	for _, refused: number in { 1.5, math.huge, -math.huge } do
		Refuses(MESSAGE, function ()
			store:UpdateAsync(KEY, function (): number
				return refused
			end)
		end)
	end

	if service.peekOrdered(STORE, KEY) ~= HELD then
		return false, `a refused value replaced {HELD} with {service.peekOrdered(STORE, KEY)}`
	end

	store:UpdateAsync(KEY, function (): number
		return largest
	end)

	if service.peekOrdered(STORE, KEY) ~= largest then
		return false, "2^53 was not kept exactly"
	end

	return true, nil
end
