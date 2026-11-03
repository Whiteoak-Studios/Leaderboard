--[[
    An amount queued while a save's write is in flight stays queued through
    that save, and the next save adds it to the total
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "During-Daily"
local USER: number = 1
local BEFORE: number = 5
local DURING: number = 3
local DELAY: number = 10

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	object:increment({ Daily = true }, USER, BEFORE)
	service.delayNext("UpdateAsync", DELAY)

	local save: any = object:save()
	object:increment({ Daily = true }, USER, DURING)

	local saved: boolean, reason: any = env.settle(save)
	local record: any = service.peek(KEY, USER)
	if not saved or not record or record.total ~= BEFORE then
		return false, `the save in flight settled {saved} with {reason}, saving {record and record.total}`
	end

	local resaved: boolean = env.settle(object:save())
	local total: number = service.peek(KEY, USER).total
	if not resaved or total ~= BEFORE + DURING then
		return false, `the next save left the total at {total}, not {BEFORE + DURING}`
	end

	return true, nil
end
