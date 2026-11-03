--[[
    GetSortedAsync refuses a page past 100 entries, and a page of 100 over
    120 entries holds the 100 highest, in order, with more left to read
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local SCALE: number = 10 -- Each player's value is their id times this

return function (): (boolean, string | nil)
	local store: any = Environment.new().services.DataStoreService:GetOrderedDataStore("AllTime")
	local stored: number = 120
	local pageSize: number = 100
	local descending: boolean = false -- GetSortedAsync's first argument is whether it sorts ascending
	local ascending: boolean = true

	for userId: number = 1, stored do
		store:UpdateAsync(userId, function (): number
			return userId * SCALE
		end)
	end

	Refuses("GetSortedAsync takes a page size of 1 to 100, not 101", function ()
		store:GetSortedAsync(descending, pageSize + 1)
	end)

	local pages: any = store:GetSortedAsync(descending, pageSize)
	local page: { { key: string, value: number } } = pages:GetCurrentPage()

	if #page ~= pageSize or pages.IsFinished then
		return false, `a page held {#page} entries, finished: {pages.IsFinished}`
	end

	for rank: number, row: { key: string, value: number } in page do
		local userId: number = stored + 1 - rank
		if row.key ~= `{userId}` or row.value ~= userId * SCALE then
			return false, `rank {rank} was {row.key} at {row.value}`
		end
	end

	local lowest: { key: string, value: number } = store:GetSortedAsync(ascending, pageSize):GetCurrentPage()[1]
	if lowest.key ~= "1" then
		return false, `an ascending page began at {lowest.key}`
	end

	return true, nil
end
