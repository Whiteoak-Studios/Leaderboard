--[[
    AllTime's values in the OrderedDataStore its key names, where a player
    keeps their highest value and a lower one is never written
--]]

--!strict
local DataStoreService = game:GetService("DataStoreService")

local Promise: any = require(script.Parent.Parent.Parent.Promise)

local TopRows = require(script.Parent.TopRows)

type Row = TopRows.Row

local Ordered = {}

--[[
    Writes the transform's value when it is higher than the stored one and
    resolves with the value the store keeps. An equal or lower value
    cancels the write, and UpdateAsync may run the transform more than once
--]]

function Ordered.update(key: string, userId: number, transform: (old: number) -> number): any
	return Promise.try(function (): number
		local stored: number = 0
		local store: OrderedDataStore = DataStoreService:GetOrderedDataStore(key)
		-- The transform returns any, since the definitions type its return as number though nil cancels the write
		local written: number? = store:UpdateAsync(`{userId}`, function (old: number?): any
			stored = old or 0
			local value: number = transform(stored)

			if old and value <= old then
				return nil
			end

			return value
		end)

		return written or stored
	end)
end

--[[
    Reads the highest values, at most the amount asked, from the store's
    first page
--]]

function Ordered.read(key: string, amount: number): any
	return Promise.try(function (): { Row }
		local ascending: boolean = false
		local pages: DataStorePages = DataStoreService:GetOrderedDataStore(key):GetSortedAsync(ascending, amount)
		local rows: { Row } = {}

		for _, entry: any in pages:GetCurrentPage() do
			table.insert(rows, { userId = tonumber(entry.key) :: number, value = entry.value })
		end

		return rows
	end)
end

function Ordered.delete(key: string, userId: number): any
	return Promise.try(function ()
		DataStoreService:GetOrderedDataStore(key):RemoveAsync(`{userId}`)
	end)
end

return Ordered
