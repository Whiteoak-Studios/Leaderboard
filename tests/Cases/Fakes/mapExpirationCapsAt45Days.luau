--[[
    A sorted map entry may live 3,888,000 seconds, 45 days, and no more, and
    an expiration of none is refused too
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local MAP: string = "Rolling"
local KEY: string = "1"
local REFUSED_KEY: string = "2"
local VALUE: number = 1
local LONGEST: number = 3888000

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local map: any = env.services.MemoryStoreService:GetSortedMap(MAP)

	local function total(): (number, number)
		return VALUE, VALUE
	end

	map:UpdateAsync(KEY, total, LONGEST)

	for _, refused: number in { LONGEST + 1, 0 } do
		Refuses(`The expiration {refused} is outside the 0 to {LONGEST} seconds an entry lives`, function ()
			map:UpdateAsync(REFUSED_KEY, total, refused)
		end)
	end

	local entries: { any } = env.services.MemoryStoreService.peek(MAP)
	if #entries ~= 1 or entries[1].expiresAt ~= env.clock.now() + LONGEST then
		return false, `the map held {#entries} entries`
	end

	return true, nil
end
