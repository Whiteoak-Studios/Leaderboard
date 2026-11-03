--[[
    rerunNext makes the next UpdateAsync on any store re-run its transform
    once on the same value, and refuses a method that is not UpdateAsync
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local MAP: string = "Daily:1"
local VALUE: number = 4
local EXPIRATION: number = 60

return function (): (boolean, string | nil)
	local services: any = Environment.new().services
	local map: any = services.MemoryStoreService:GetSortedMap(MAP)
	local seen: { any } = {}

	services.MemoryStoreService.rerunNext("UpdateAsync")

	map:UpdateAsync("1", function (old: number?): (number, number)
		table.insert(seen, old or 0)
		return VALUE, VALUE
	end, EXPIRATION)

	if #seen ~= 2 or seen[1] ~= 0 or seen[2] ~= 0 then
		return false, `the transform ran {#seen} times`
	end

	if services.MemoryStoreService.peek(MAP)[1].value ~= VALUE then
		return false, "the re-run did not commit once"
	end

	local ran: boolean, thrown: any = pcall(services.MemoryStoreService.rerunNext, "GetRangeAsync")
	if ran or not Mentions(thrown, "rerunNext re-runs a store's UpdateAsync") then
		return false, `rerunNext took GetRangeAsync: {thrown}`
	end

	return true, nil
end
