--[[
    Every store keeps the exact integer it is given: ten updates of +5 read
    back 50, and 1 and 1000 read back as themselves
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local STEPPED: number = 1 -- The player the ten updates go to
local SMALL_ID: number = 2
local LARGE_ID: number = 3
local STEP: number = 5
local STEPS: number = 10
local SMALL: number = 1
local LARGE: number = 1000
local AMOUNT: number = 100

type Entry = { name: string, config: any, totals: string? }
type Expected = { userId: number, value: number }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Values-Daily", totals = "Values-Daily" },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Values-Wipe" }, totals = "Values-Wipe" },
	{ name = "AllTime", config = "Values-AllTime" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		local read: boolean = env.settle(board:read(AMOUNT))
		if not read then
			return false, `{entry.name}'s first read rejected`
		end

		local total: any = nil
		for _ = 1, STEPS do
			local updated: boolean, value: any = env.settle(board:update(STEPPED, Boards.add(STEP)))

			if not updated then
				return false, `{entry.name} rejected an update of +{STEP}`
			end

			total = value
		end

		env.settle(board:update(SMALL_ID, Boards.add(SMALL)))
		env.settle(board:update(LARGE_ID, Boards.add(LARGE)))

		if total ~= STEP * STEPS then
			return false, `{entry.name}'s tenth update resolved with {total}, not {STEP * STEPS}`
		end

		if entry.totals then
			local record: any = env.services.DataStoreService.peek(entry.totals, STEPPED)
			if not record or record.total ~= STEP * STEPS then
				return false, `{entry.name}'s totals store held {record and record.total}, not {STEP * STEPS}`
			end
		elseif env.services.DataStoreService.peekOrdered(entry.config, STEPPED) ~= STEP * STEPS then
			return false,
				`{entry.name}'s ordered store held {env.services.DataStoreService.peekOrdered(entry.config, STEPPED)}`
		end

		local expected: { Expected } = {
			{ userId = LARGE_ID, value = LARGE },
			{ userId = STEPPED, value = STEP * STEPS },
			{ userId = SMALL_ID, value = SMALL },
		}

		local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not ok or #rows ~= #expected then
			return false, `{entry.name} read back {ok and #rows} rows, not {#expected}`
		end

		for rank: number, row: Expected in expected do
			if rows[rank].userId ~= row.userId or rows[rank].value ~= row.value then
				local found: string = `{rows[rank].userId} at {rows[rank].value}`
				return false, `{entry.name}'s row {rank} read {found}, not {row.userId} at {row.value}`
			end
		end

		if entry.name == "Daily" and env.services.DataStoreService.peek(entry.totals, STEPPED).window ~= Start.DAY then
			return false, "Daily's total was not kept beside the day it counts"
		end
	end

	return true, nil
end
