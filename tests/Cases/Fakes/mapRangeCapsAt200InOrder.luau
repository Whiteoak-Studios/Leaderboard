--[[
    GetRangeAsync refuses a count past 200 and returns at most 200 items,
    ordered by sort key and then by key, in either direction
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local KEY_FORMAT: string = "%03d" -- Zero-pads a key so the keys sort as their numbers do
local SHARING: number = 2 -- Keys that share each sort key, so ties are ordered by key
local EXPIRATION: number = 60
local STORED: number = 250
local MOST: number = 200

return function (): (boolean, string | nil)
	local map: any = Environment.new().services.MemoryStoreService:GetSortedMap("Weekly:1")
	local descending: any = roblox.Enum.SortDirection.Descending

	for index: number = 1, STORED do
		local total: number = math.ceil(index / SHARING)
		map:UpdateAsync(string.format(KEY_FORMAT, index), function (): (number, number)
			return total, total
		end, EXPIRATION)
	end

	Refuses(`GetRangeAsync takes a count of 1 to {MOST}, not {MOST + 1}`, function ()
		map:GetRangeAsync(descending, MOST + 1)
	end)

	local highest: { any } = map:GetRangeAsync(descending, MOST)
	if #highest ~= MOST then
		return false, `a range of {MOST} returned {#highest} items`
	end

	for rank: number, item: any in highest do
		local index: number = STORED + 1 - rank
		if item.key ~= string.format(KEY_FORMAT, index) or item.sortKey ~= math.ceil(index / SHARING) then
			return false, `rank {rank} was {item.key} at {item.sortKey}`
		end
	end

	local lowest: { any } = map:GetRangeAsync(roblox.Enum.SortDirection.Ascending, SHARING)
	if lowest[1].key ~= "001" or lowest[2].key ~= "002" or lowest[1].expiresAt ~= nil then
		return false, `an ascending range began {lowest[1].key}, {lowest[2].key}`
	end

	return true, nil
end
