--[[
    A delete called while a save's write is in flight waits for it, so the
    amount that write puts back when it fails is dropped, and the next save
    brings back neither the player's total nor their row
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Delete-Daily"
local USER: number = 1
local SAVED: number = 10
local IN_FLIGHT: number = 5
local DELAY: number = 10

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	-- The board's first read, after which a save writes the player's row
	env.settle(object:getAll("All"))
	object:increment({ Daily = true }, USER, SAVED)
	env.settle(object:save())

	local _, before: any = env.settle(object:getAll("All"))
	if not data.peek(KEY, USER) or #before[1].rows ~= 1 then
		return false, "the first save left no total or row to delete"
	end

	object:increment({ Daily = true }, USER, IN_FLIGHT)
	data.delayNext("UpdateAsync", DELAY)
	data.failNext("UpdateAsync")

	local save: any = object:save()
	local deleted: any = object:delete({ Daily = true }, USER)

	local saved: boolean = env.settle(save)
	if saved then
		return false, "the save in flight resolved, where its write was made to fail"
	end

	local removed: boolean, reason: any = env.settle(deleted)
	if not removed then
		return false, `the delete rejected: {reason}`
	end

	env.settle(object:save())

	local record: any = data.peek(KEY, USER)
	local _, after: any = env.settle(object:getAll("All"))
	if record ~= nil or #after[1].rows ~= 0 then
		return false, `the save after the delete brought back the total {record and record.total} or the row`
	end

	return true, nil
end
