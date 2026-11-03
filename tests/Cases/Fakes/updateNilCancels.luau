--[[
    On every store a transform that gives nil cancels its UpdateAsync, which
    then returns nil and leaves what the key held
--]]

--!strict
local Environment = require("../../Environment")

local STORE: string = "Totals"
local ORDERED: string = "AllTime"
local MAP: string = "Daily:1"
local KEY: string = "1"
local VALUE: number = 3
local STORES: number = 3 -- The standard store, the ordered one and the map
local EXPIRATION: number = 60

return function (): (boolean, string | nil)
	local services: any = Environment.new().services
	local standard: any = services.DataStoreService:GetDataStore(STORE)
	local ordered: any = services.DataStoreService:GetOrderedDataStore(ORDERED)
	local map: any = services.MemoryStoreService:GetSortedMap(MAP)

	local function write(): (number, number)
		return VALUE, VALUE
	end

	local function cancel(): nil
		return nil
	end

	standard:UpdateAsync(KEY, write)
	ordered:UpdateAsync(KEY, write)
	map:UpdateAsync(KEY, write, EXPIRATION)

	local standardResult: any = standard:UpdateAsync(KEY, cancel)
	local orderedResult: any = ordered:UpdateAsync(KEY, cancel)
	local mapResult: any = map:UpdateAsync(KEY, cancel, EXPIRATION)

	if standardResult ~= nil or orderedResult ~= nil or mapResult ~= nil then
		return false, "a canceled UpdateAsync returned a value"
	end

	local mapEntry: any = services.MemoryStoreService.peek(MAP)[1]
	local held: { any } = {
		services.DataStoreService.peek(STORE, KEY),
		services.DataStoreService.peekOrdered(ORDERED, KEY),
		mapEntry and mapEntry.value,
	}

	for index: number = 1, STORES do
		if held[index] ~= VALUE then
			return false, `store {index} held {held[index]} after a cancel`
		end
	end

	return true, nil
end
