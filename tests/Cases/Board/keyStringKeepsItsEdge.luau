--[[
    A Weekly key string still turns on Sunday 00:00 UTC and a Daily one at
    00:00, on the period numbers they always had, and a table set to that
    same edge turns with them, on the same numbers
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local USER: number = 1
local OPENING: number = 5 -- The first write, in the clock's first period
local HELD: number = 1 -- The write just before the edge
local FRESH: number = 2 -- The first write of the new period
local EARLY: number = 1 -- Seconds before the edge the held write lands
local AMOUNT: number = 100

type Entry = { name: string, key: string, config: any }

type Edge = {
	turn: number, -- The edge after the clock's start
	nextTurn: number, -- The edge after that
	before: number, -- The period numbers either side of the first edge
	after: number,
}

local ENTRIES: { Entry } = {
	{ name = "Weekly", key = "Edge-Weekly", config = "Edge-Weekly" },
	{ name = "Weekly", key = "Edge-Sunday", config = { key = "Edge-Sunday", weekday = "Sunday" } },
	{ name = "Daily", key = "Edge-Daily", config = "Edge-Daily" },
	{ name = "Daily", key = "Edge-Midnight", config = { key = "Edge-Midnight", hour = 0 } },
}

-- After the clock's start, Wednesday 2026-11-04 12:00 UTC, the week turns on Sunday 2026-11-08 and the next
-- Sunday, its weeks counted from 1970-01-04, and the day turns at Thursday's midnight and Friday's
local EDGES: { [string]: Edge } = {
	Weekly = { turn = 1794096000, nextTurn = 1794700800, before = 2965, after = 2966 },
	Daily = { turn = 1793836800, nextTurn = 1793923200, before = Start.DAY, after = Start.DAY + 1 },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in ENTRIES do
		local edge: Edge = EDGES[entry.name]
		local env: any = Environment.new()
		local built: boolean, board: any = pcall(env.require("Board/init").new, entry.name, entry.config)
		if not built then
			return false, `the {entry.name} board on {entry.key} threw: {board}`
		end

		local maps: any = env.services.MemoryStoreService
		local before: string = `{entry.key}:{edge.before}`
		local after: string = `{entry.key}:{edge.after}`

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.add(OPENING)))

		-- Just before the edge the period still holds, and its row expires on the edge
		env.clock.advance(edge.turn - EARLY - env.clock.now())
		local held: boolean = env.settle(board:update(USER, Boards.add(HELD)))
		local items: { any } = maps.peek(before)

		if not held or #items ~= 1 or items[1].expiresAt ~= edge.turn then
			return false, `{before}'s row expires at {items[1] and items[1].expiresAt}, not {edge.turn}`
		end

		env.clock.advance(EARLY)
		local read: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not read or #rows ~= 0 then
			return false, `the read at {entry.key}'s edge found {read and #rows} rows in {after}, not an empty map`
		end

		local ok: boolean, total: any = env.settle(board:update(USER, Boards.add(FRESH)))
		local opened: { any } = maps.peek(after)
		if not ok or total ~= FRESH or #opened ~= 1 or opened[1].value ~= FRESH then
			return false, `the total in {after} started at {total}, not from zero`
		end

		if opened[1].expiresAt ~= edge.nextTurn then
			return false, `{after}'s row expires at {opened[1].expiresAt}, not the next edge, {edge.nextTurn}`
		end

		if #maps.peek(before) ~= 0 then
			return false, `{before} outlived its period`
		end

		if env.services.DataStoreService.peek(entry.key, USER).window ~= edge.after then
			return false, `{entry.key}'s total was not kept beside period {edge.after}`
		end
	end

	return true, nil
end
