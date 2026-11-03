--[[
    Each UTC period ends on its own edge: the week at Sunday 00:00 and
    December into January. A new period opens an empty map and a fresh total
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local USER: number = 1
local OPENING: number = 5 -- The first write, in the clock's first period
local HELD: number = 1 -- The write just before an edge
local FRESH: number = 2 -- The first write of the new period
local EARLY: number = 1 -- Seconds before an edge the held write lands
local AMOUNT: number = 100

type Period = { name: string, turns: { number }, periods: { number } }

-- Each board's period edges after the clock's start, Wednesday 2026-11-04 12:00 UTC, and the period numbers
-- between them. The week turns on Sunday 2026-11-08, and the month on 2026-12-01 and again on 2027-01-01
local PERIODS: { Period } = {
	{ name = "Hourly", turns = { 1793797200 }, periods = { 498276, 498277 } },
	{ name = "Daily", turns = { 1793836800 }, periods = { Start.DAY, Start.DAY + 1 } },
	{ name = "Weekly", turns = { 1794096000 }, periods = { 2965, 2966 } },
	{ name = "Monthly", turns = { 1796083200, 1798761600 }, periods = { 24322, 24323, 24324 } },
}

return function (): (boolean, string | nil)
	for _, entry: Period in PERIODS do
		local env: any = Environment.new()
		local key: string = `Period-{entry.name}`
		local board: any = env.require("Board/init").new(entry.name, key)

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.add(OPENING)))

		for index: number, turn: number in entry.turns do
			local before: string = `{key}:{entry.periods[index]}`
			local after: string = `{key}:{entry.periods[index + 1]}`

			-- Just before the edge the period still holds, and its row expires on the edge
			env.clock.advance(turn - EARLY - env.clock.now())
			local held: boolean = env.settle(board:update(USER, Boards.add(HELD)))
			local items: { any } = env.services.MemoryStoreService.peek(before)

			if not held or #items ~= 1 or items[1].expiresAt ~= turn then
				return false, `{before}'s row expires at {items[1] and items[1].expiresAt}, not {turn}`
			end

			env.clock.advance(EARLY)
			local read: boolean, rows: any = env.settle(board:read(AMOUNT))
			if not read or #rows ~= 0 then
				return false, `{entry.name}'s new period read {read and #rows} rows from {after}, not an empty map`
			end

			local ok: boolean, total: any = env.settle(board:update(USER, Boards.add(FRESH)))
			local opened: { any } = env.services.MemoryStoreService.peek(after)
			if not ok or total ~= FRESH or #opened ~= 1 or opened[1].value ~= FRESH then
				return false, `{entry.name}'s total in {after} started at {total}, not from zero`
			end

			if #env.services.MemoryStoreService.peek(before) ~= 0 then
				return false, `{before} outlived its period`
			end

			if env.services.DataStoreService.peek(key, USER).window ~= entry.periods[index + 1] then
				return false, `{entry.name}'s total was not kept beside period {entry.periods[index + 1]}`
			end
		end
	end

	return true, nil
end
