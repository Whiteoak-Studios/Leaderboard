--[[
    failNext fails the next calls of a method on any store the service made,
    writing nothing, and refuses a method the service does not have
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")
local Refuses = require("../../Refuses")

local MESSAGE: string = "DataStoreService.UpdateAsync failed, as failNext asked"
local STORE: string = "Totals"
local ORDERED: string = "AllTime"
local KEY: string = "1"
local VALUE: number = 2
local FAILURES: number = 2 -- One for each kind of store

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.DataStoreService
	local standard: any = service:GetDataStore(STORE)
	local ordered: any = service:GetOrderedDataStore(ORDERED)

	local function write(): number
		return VALUE
	end

	service.failNext("UpdateAsync", FAILURES)

	Refuses(MESSAGE, function ()
		standard:UpdateAsync(KEY, write)
	end)

	Refuses(MESSAGE, function ()
		ordered:UpdateAsync(KEY, write)
	end)

	if service.peek(STORE, KEY) ~= nil or service.peekOrdered(ORDERED, KEY) ~= nil then
		return false, "a failed UpdateAsync wrote its value"
	end

	standard:UpdateAsync(KEY, write)
	if service.peek(STORE, KEY) ~= VALUE then
		return false, "the call after the failures did not write"
	end

	local ran: boolean, thrown: any = pcall(service.failNext, "UpdateAsyc")
	if ran or not Mentions(thrown, "DataStoreService has no UpdateAsyc") then
		return false, `failNext took a misspelled method: {thrown}`
	end

	return true, nil
end
