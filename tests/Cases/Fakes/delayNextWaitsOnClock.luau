--[[
    delayNext holds the next call of a method until the fake clock has moved
    that far, and a call after it answers at once
--]]

--!strict
local roblox: any = require("@lune/roblox")

local Environment = require("../../Environment")

local MAP: string = "Daily:1"
local DELAY: number = 3
local JUST_BEFORE: number = 2.9
local COUNT: number = 1 -- Items each read asks for

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.MemoryStoreService
	local map: any = service:GetSortedMap(MAP)
	local descending: any = roblox.Enum.SortDirection.Descending
	local answered: boolean = false

	service.delayNext("GetRangeAsync", DELAY)

	env.clock.task.spawn(function ()
		map:GetRangeAsync(descending, COUNT)
		answered = true
	end)

	env.clock.advance(JUST_BEFORE)
	if answered then
		return false, "the delayed call answered before its delay"
	end

	env.clock.advance(DELAY - JUST_BEFORE)
	if not answered then
		return false, "the delayed call had not answered once its delay passed"
	end

	map:GetRangeAsync(descending, COUNT)

	return true, nil
end
