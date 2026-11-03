--[[
    Each tick fires updated once with every board's result in the order of
    their names and boardUpdated once per board, and a board whose read
    fails is left out of both while the rest fire as usual
--]]

--!strict
local Environment = require("../../Environment")

local LOWER: number = 1
local HIGHER: number = 2
local LOWER_VALUE: number = 40
local HIGHER_VALUE: number = 70
local INTERVAL: number = 90
local EVERY: string = "AllTime, Daily, Weekly"
local AFTER_FAILURE: string = "Daily, Weekly"

local BOARDS: { [string]: string } = {
	Weekly = "Signals-Weekly",
	AllTime = "Signals-AllTime",
	Daily = "Signals-Daily",
}

--[[
    The boards a list of results names, in its order
--]]

local function named(results: { any }): string
	local names: { string } = {}
	for _, result: any in results do
		table.insert(names, result.board)
	end

	return table.concat(names, ", ")
end

--[[
    The same names sorted, for boardUpdated, whose firing order is not part
    of its contract
--]]

local function sorted(results: { any }): string
	local copy: { any } = table.clone(results)
	table.sort(copy, function (a: any, b: any): boolean
		return a.board < b.board
	end)

	return named(copy)
end

--[[
    Whether a result holds the two players' rows, the higher first
--]]

local function ranked(result: any): boolean
	local first: any, second: any = result.rows[1], result.rows[2]

	return #result.rows == 2
		and first.userId == HIGHER
		and first.value == HIGHER_VALUE
		and second.userId == LOWER
		and second.value == LOWER_VALUE
end

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new(BOARDS, { automation = true, interval = INTERVAL })

	-- The automation's first read ran as the object was built, so both writes take their rows
	env.settle(object:set("All", LOWER, LOWER_VALUE))
	env.settle(object:set("All", HIGHER, HIGHER_VALUE))

	local lists: { { any } } = {}
	local singles: { any } = {}
	object.updated:Connect(function (results: { any })
		table.insert(lists, results)
	end)
	object.boardUpdated:Connect(function (result: any)
		table.insert(singles, result)
	end)

	env.clock.advance(INTERVAL)
	if #lists ~= 1 or named(lists[1]) ~= EVERY or #singles ~= 3 then
		return false, `the tick fired updated {#lists} times with {lists[1] and named(lists[1])} and {#singles} boards`
	end

	for _, result: any in lists[1] do
		if not ranked(result) then
			return false, `{result.board}'s result held the wrong rows`
		end
	end

	if sorted(singles) ~= EVERY or not (ranked(singles[1]) and ranked(singles[2]) and ranked(singles[3])) then
		return false, `boardUpdated fired for {sorted(singles)}, or with the wrong rows`
	end

	env.services.DataStoreService.failNext("GetSortedAsync")
	env.clock.advance(INTERVAL)

	local after: { any } = table.move(singles, 4, #singles, 1, {})
	if #lists ~= 2 or named(lists[2]) ~= AFTER_FAILURE or sorted(after) ~= AFTER_FAILURE then
		return false, `with AllTime's read failing the tick fired {lists[2] and named(lists[2])} and {sorted(after)}`
	end

	env.settle(object:destroy())

	return true, nil
end
