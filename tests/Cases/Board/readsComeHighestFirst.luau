--[[
    A read returns a board's rows highest first, with numeric user ids, and
    never more than the amount asked, on every store
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local VALUES: { number } = { 30, 10, 50, 20, 40 } -- Each user id's value, by id
local ORDER: { number } = { 3, 5, 1, 4, 2 } -- The user ids highest first
local FEW: number = 3
local MANY: number = 100

type Entry = { name: string, config: any }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Order-Daily" },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Order-Wipe" } },
	{ name = "AllTime", config = "Order-AllTime" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(MANY))
		for userId: number, value: number in VALUES do
			env.settle(board:update(userId, Boards.set(value)))
		end

		for _, amount: number in { FEW, MANY } do
			local ok: boolean, rows: any = env.settle(board:read(amount))
			local expected: number = math.min(amount, #ORDER)

			if not ok or #rows ~= expected then
				return false, `{entry.name} read {ok and #rows} rows when {amount} were asked, not {expected}`
			end

			for rank: number, row: any in rows do
				if type(row.userId) ~= "number" or row.userId ~= ORDER[rank] or row.value ~= VALUES[ORDER[rank]] then
					return false, `{entry.name}'s row {rank} read {typeof(row.userId)} {row.userId} at {row.value}`
				end
			end
		end
	end

	return true, nil
end
