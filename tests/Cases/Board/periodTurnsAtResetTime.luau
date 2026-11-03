--[[
    A Weekly or Daily board with its own reset time turns there and not on
    its fixed edge: the write after the reset opens an empty map and a fresh
    total, and its row expires at the next reset
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local USER: number = 1
local OPENING: number = 5 -- The first write, in the clock's first period
local HELD: number = 1 -- The write just before the reset
local FRESH: number = 2 -- The first write of the new period
local LATE: number = 3 -- Each write either side of the fixed edge
local EARLY: number = 1 -- Seconds before an edge a write lands
local AMOUNT: number = 100

type Schedule = {
	name: string,
	config: { [string]: any },
	turn: number, -- The first reset after the clock's start
	edge: number, -- The fixed edge after it, which turns nothing here
	nextTurn: number, -- The reset after that
	before: number, -- The period numbers either side of the first reset
	after: number,
}

-- After the clock's start, Wednesday 2026-11-04 12:00 UTC. The Friday 14:00 board resets on Friday 2026-11-06 at
-- 14:00, counting weeks from 1970-01-09 14:00, and Sunday 2026-11-08 00:00 is its fixed edge. The 14:30 board
-- resets on 2026-11-04 at 14:30, counting days from 1970-01-01 14:30, and Thursday's midnight is its fixed edge
local SCHEDULES: { Schedule } = {
	{
		name = "Weekly",
		config = { key = "Reset-Weekly", weekday = "Friday", hour = 14 },
		turn = 1793973600,
		edge = 1794096000,
		nextTurn = 1794578400,
		before = 2964,
		after = 2965,
	},
	{
		name = "Daily",
		config = { key = "Reset-Daily", hour = 14, minute = 30 },
		turn = 1793802600,
		edge = 1793836800,
		nextTurn = 1793889000,
		before = 20760,
		after = 20761,
	},
}

return function (): (boolean, string | nil)
	for _, schedule: Schedule in SCHEDULES do
		local env: any = Environment.new()
		local Board: any = env.require("Board/init")
		local key: string = schedule.config.key

		local built: boolean, board: any = pcall(Board.new, schedule.name, schedule.config)
		if not built then
			return false, `the {schedule.name} board on {key} threw: {board}`
		end

		local maps: any = env.services.MemoryStoreService
		local before: string = `{key}:{schedule.before}`
		local after: string = `{key}:{schedule.after}`

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.add(OPENING)))

		-- Just before the reset the period still holds, and its row expires on it
		env.clock.advance(schedule.turn - EARLY - env.clock.now())
		local held: boolean, heldTotal: any = env.settle(board:update(USER, Boards.add(HELD)))
		local items: { any } = maps.peek(before)

		if not held or heldTotal ~= OPENING + HELD or #items ~= 1 or items[1].expiresAt ~= schedule.turn then
			return false, `{before}'s row expires at {items[1] and items[1].expiresAt}, not {schedule.turn}`
		end

		env.clock.advance(EARLY)
		local read: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not read or #rows ~= 0 then
			return false, `the read at {key}'s reset found {read and #rows} rows in {after}, not an empty map`
		end

		local ok: boolean, total: any = env.settle(board:update(USER, Boards.add(FRESH)))
		local opened: { any } = maps.peek(after)
		if not ok or total ~= FRESH or #opened ~= 1 or opened[1].value ~= FRESH then
			return false, `the total in {after} started at {total}, not from zero`
		end

		if opened[1].expiresAt ~= schedule.nextTurn then
			return false, `{after}'s row expires at {opened[1].expiresAt}, not the next reset, {schedule.nextTurn}`
		end

		if #maps.peek(before) ~= 0 then
			return false, `{before} outlived its period`
		end

		if env.services.DataStoreService.peek(key, USER).window ~= schedule.after then
			return false, `{key}'s total was not kept beside period {schedule.after}`
		end

		-- The fixed edge is no edge here: writes either side of it add to one total in one map
		env.clock.advance(schedule.edge - EARLY - env.clock.now())
		env.settle(board:update(USER, Boards.add(LATE)))
		env.clock.advance(EARLY)

		local reread: boolean, kept: any = env.settle(board:read(AMOUNT))
		if not reread or #kept ~= 1 or kept[1].value ~= FRESH + LATE then
			return false, `the read past {key}'s fixed edge found {reread and #kept} rows, not the period's one row`
		end

		local added: boolean, sum: any = env.settle(board:update(USER, Boards.add(LATE)))
		local same: { any } = maps.peek(after)
		if not added or sum ~= FRESH + LATE + LATE or #same ~= 1 or same[1].value ~= sum then
			return false, `the write past {key}'s fixed edge resolved with {sum}, not the period's running total`
		end

		if same[1].expiresAt ~= schedule.nextTurn or #maps.peek(`{key}:{schedule.after + 1}`) ~= 0 then
			return false, `{key}'s fixed edge turned the period, its row expiring at {same[1].expiresAt}`
		end

		if env.services.DataStoreService.peek(key, USER).window ~= schedule.after then
			return false, `{key}'s total left period {schedule.after} at the fixed edge`
		end

		-- The configuration alone names the same map, as a live check that builds no board reads it
		local totals: any = Board.totalsOf(schedule.name, schedule.config)
		local named: string = totals:map(totals:opens(env.clock.now()))
		if named ~= after then
			return false, `totalsOf named {named}, not {after}`
		end
	end

	return true, nil
end
