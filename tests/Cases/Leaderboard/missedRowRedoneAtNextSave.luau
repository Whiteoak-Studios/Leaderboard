--[[
    A save or set whose row write fails after the total landed resolves,
    and the next save writes that total's row once with nothing scored
    since, while a row skipped before the first read and a delete queue none
--]]

--!strict
local Calls = require("../../Calls")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Missed-Daily"
local MAP: string = `{KEY}:{Start.DAY}`
local EARLY: number = 1
local SCORER: number = 2
local SETTER: number = 3
local DELETED: number = 4
local AMOUNT: number = 5
local VALUE: number = 9

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local maps: any = env.services.MemoryStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })
	local stores: { { any } } = Calls(data, "GetDataStore")

	-- Before the board's first read a save writes no row, which is no miss, so nothing stays queued
	object:increment({ Daily = true }, EARLY, AMOUNT)
	env.settle(object:save())

	local early: number = #stores
	env.settle(object:save())
	if #stores ~= early then
		return false, "a row skipped before the first read was queued again as a miss"
	end

	env.settle(object:getAll("All"))

	-- The totals land and the row writes fail, and the save and the set still resolve
	object:increment({ Daily = true }, SCORER, AMOUNT)
	maps.failNext("UpdateAsync")

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved or #maps.peek(MAP) ~= 0 then
		return false, `the save whose row write failed resolved {saved} with {reason}, or left a row`
	end

	maps.failNext("UpdateAsync")

	local set: boolean, refusal: any = env.settle(object:set({ Daily = true }, SETTER, VALUE))
	if not set or #maps.peek(MAP) ~= 0 then
		return false, `the set whose row write failed resolved {set} with {refusal}, or left a row`
	end

	-- With nothing scored since, the next save writes both rows at the totals that landed
	local resaved: boolean, failure: any = env.settle(object:save())
	if not resaved then
		return false, `the save after the failed rows rejected: {failure}`
	end

	local read: boolean, results: any = env.settle(object:getAll("All"))
	if not read then
		return false, `the read after the redone rows rejected: {results}`
	end

	local rows: { any } = results[1].rows
	local scorer: number = data.peek(KEY, SCORER).total
	local setter: number = data.peek(KEY, SETTER).total
	local first: any, second: any = rows[1], rows[2]
	if
		#rows ~= 2
		or first.userId ~= SETTER
		or first.value ~= VALUE
		or second.userId ~= SCORER
		or second.value ~= AMOUNT
	then
		return false, `the next save left {#rows} rows, where it writes {SETTER} at {VALUE} and {SCORER} at {AMOUNT}`
	end

	if scorer ~= AMOUNT or setter ~= VALUE then
		return false, `the next save moved the totals to {scorer} and {setter}, not {AMOUNT} and {VALUE}`
	end

	-- Once the rows have landed nothing stays queued
	local landed: number = #stores
	env.settle(object:save())
	if #stores ~= landed then
		return false, "a save after the rows landed wrote again with nothing queued"
	end

	-- A delete drops the queued redo, so the next save brings back neither the total nor the row
	object:increment({ Daily = true }, DELETED, AMOUNT)
	maps.failNext("UpdateAsync")
	env.settle(object:save())
	env.settle(object:delete({ Daily = true }, DELETED))
	env.settle(object:save())

	local record: any = data.peek(KEY, DELETED)
	if record ~= nil or #maps.peek(MAP) ~= 2 then
		return false, `the save after the delete brought back the total {record and record.total} or the row`
	end

	return true, nil
end
