--[[
    A reset time is a weekday for Weekly alone, and a whole hour from 0 to 23
    and minute from 0 to 59 for Weekly or Daily, left out meaning 0 where it
    may be. Any other shape throws in new with a message naming the board
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Reset-Bounds"
local USER: number = 1
local AMOUNT: number = 100
local ROLLING: number = 3600 -- A rolling expiry that builds on its own
local WEEKDAYS: { string } = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

type Refused = { name: string, config: { [string]: any }, says: string? }
type Scheduled = { name: string, config: { [string]: any }, map: string, turn: number }

-- Each refusal's board and configuration, and any text its message holds beside the board's name
local REFUSED: { Refused } = {
	{ name = "Weekly", config = { key = KEY, weekday = "Funday" }, says = "Saturday" },
	{ name = "Weekly", config = { key = KEY, weekday = "friday" } },
	{ name = "Weekly", config = { key = KEY, weekday = 5 } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", hour = -1 } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", hour = 24 } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", hour = 13.5 }, says = "whole" },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", hour = "14" } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", hour = 0 / 0 } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", minute = -1 } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", minute = 60 } },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", minute = 30.5 }, says = "whole" },
	{ name = "Weekly", config = { key = KEY, weekday = "Friday", minute = math.huge } },
	{ name = "Daily", config = { key = KEY, hour = -1 } },
	{ name = "Daily", config = { key = KEY, hour = 24 } },
	{ name = "Daily", config = { key = KEY, hour = 13.5 }, says = "whole" },
	{ name = "Daily", config = { key = KEY, hour = "14" } },
	{ name = "Daily", config = { key = KEY, hour = 14, minute = 60 } },
	{ name = "Daily", config = { key = KEY, hour = 14, minute = 30.5 }, says = "whole" },
	{ name = "Weekly", config = { key = KEY, expirySeconds = ROLLING, weekday = "Friday" }, says = "expirySeconds" },
	{ name = "Weekly", config = { key = KEY, expirySeconds = ROLLING, minute = 30 }, says = "expirySeconds" },
	{ name = "Daily", config = { key = KEY, expirySeconds = ROLLING, hour = 14 }, says = "expirySeconds" },
	{ name = "Wipe", config = { key = KEY, expirySeconds = ROLLING, weekday = "Friday" }, says = "expirySeconds" },
	{ name = "Wipe", config = { key = KEY, expirySeconds = ROLLING, hour = 14 }, says = "expirySeconds" },
	{ name = "Weekly", config = { key = KEY }, says = "weekday" },
	{ name = "Weekly", config = { key = KEY, hour = 14 }, says = "weekday" },
	{ name = "Daily", config = { key = KEY }, says = "hour" },
	{ name = "Daily", config = { key = KEY, minute = 30 }, says = "hour" },
	{ name = "Daily", config = { key = KEY, weekday = "Friday", hour = 14 }, says = "Weekly" },
	{ name = "Hourly", config = { key = KEY, weekday = "Friday" }, says = "Weekly" },
	{ name = "AllTime", config = { key = KEY, weekday = "Friday" }, says = "Weekly" },
	{ name = "Wipe", config = { key = KEY, weekday = "Friday" }, says = "Weekly" },
	{ name = "Hourly", config = { key = KEY, hour = 14 }, says = "Daily" },
	{ name = "Monthly", config = { key = KEY, hour = 14 }, says = "Daily" },
	{ name = "AllTime", config = { key = KEY, minute = 30 }, says = "Daily" },
	{ name = "Wipe", config = { key = KEY, hour = 14, minute = 30 }, says = "Daily" },
}

-- From the clock's start, Wednesday 2026-11-04 12:00 UTC, each board's period ends at its next reset: Friday
-- 2026-11-06 00:00 for a Friday with no hour or minute, Saturday 2026-11-07 23:59 with both at their highest,
-- 14:00 on the start's day for a Daily 14:00 with no minute, and 23:59 for a Daily 23:59
local SCHEDULED: { Scheduled } = {
	{
		name = "Weekly",
		config = { key = "Reset-Friday", weekday = "Friday" },
		map = "Reset-Friday:2964",
		turn = 1793923200,
	},
	{
		name = "Weekly",
		config = { key = "Reset-Saturday", weekday = "Saturday", hour = 23, minute = 59 },
		map = "Reset-Saturday:2964",
		turn = 1794095940,
	},
	{
		name = "Daily",
		config = { key = "Reset-Afternoon", hour = 14 },
		map = "Reset-Afternoon:20760",
		turn = 1793800800,
	},
	{
		name = "Daily",
		config = { key = "Reset-Late", hour = 23, minute = 59 },
		map = "Reset-Late:20760",
		turn = 1793836740,
	},
}

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Board: any = env.require("Board/init")

	for _, entry: Refused in REFUSED do
		local ran: boolean, thrown: any = pcall(Board.new, entry.name, entry.config)
		local shown: string = `{entry.config.weekday} {entry.config.hour} {entry.config.minute}`
		if ran then
			return false, `{entry.name} built with the reset {shown} and expiry {entry.config.expirySeconds}`
		end

		if not Mentions(thrown, entry.name) or (entry.says and not Mentions(thrown, entry.says)) then
			return false, `{entry.name}'s refusal of {shown} did not name the board or {entry.says}: {thrown}`
		end
	end

	-- Every weekday builds with the lowest hour and minute given, as does a Daily 00:00
	for _, weekday: string in WEEKDAYS do
		local config: { [string]: any } = { key = KEY, weekday = weekday, hour = 0, minute = 0 }
		local ran: boolean, thrown: any = pcall(Board.new, "Weekly", config)
		if not ran then
			return false, `a Weekly board on {weekday} 00:00 threw: {thrown}`
		end
	end

	local midnight: boolean, refusal: any = pcall(Board.new, "Daily", { key = KEY, hour = 0, minute = 0 })
	if not midnight then
		return false, `a Daily board at 00:00 threw: {refusal}`
	end

	-- A write at the clock's start expires when the board's period does, at the next reset its schedule gives
	for _, entry: Scheduled in SCHEDULED do
		local ran: boolean, board: any = pcall(Board.new, entry.name, entry.config)
		if not ran then
			return false, `the {entry.name} board on {entry.config.key} threw: {board}`
		end

		env.settle(board:read(AMOUNT))
		local ok: boolean = env.settle(board:update(USER, Boards.add(AMOUNT)))
		local items: { any } = env.services.MemoryStoreService.peek(entry.map)

		if not ok or #items ~= 1 or items[1].expiresAt ~= entry.turn then
			return false, `{entry.map}'s row expires at {items[1] and items[1].expiresAt}, not {entry.turn}`
		end
	end

	-- A table of expirySeconds and no reset time is still a rolling board's, Weekly and Daily included
	for _, name: string in { "Weekly", "Daily" } do
		local key: string = `Reset-Rolling{name}`
		local ran: boolean, board: any = pcall(Board.new, name, { key = key, expirySeconds = ROLLING })
		if not ran then
			return false, `a rolling board named {name} threw: {board}`
		end

		env.settle(board:read(AMOUNT))
		env.settle(board:update(USER, Boards.add(AMOUNT)))
		if #env.services.MemoryStoreService.peek(key) ~= 1 then
			return false, `the rolling board named {name} wrote no row to its one map, {key}`
		end
	end

	return true, nil
end
