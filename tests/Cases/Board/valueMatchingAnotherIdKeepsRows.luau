--[[
    A stored value equal to another player's user id leaves both rows
    correct on every store, since a row's id and its value never mix
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local LOW_ID: number = 100
local HIGH_ID: number = 200
local AMOUNT: number = 100

type Entry = { name: string, config: any }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Matching-Daily" },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Matching-Wipe" } },
	{ name = "AllTime", config = "Matching-AllTime" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(AMOUNT))
		env.settle(board:update(LOW_ID, Boards.set(HIGH_ID)))
		env.settle(board:update(HIGH_ID, Boards.set(LOW_ID)))

		local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not ok or #rows ~= 2 then
			return false, `{entry.name} read {ok and #rows} rows, not 2`
		end

		if
			rows[1].userId ~= LOW_ID
			or rows[1].value ~= HIGH_ID
			or rows[2].userId ~= HIGH_ID
			or rows[2].value ~= LOW_ID
		then
			return false,
				`{entry.name} read {rows[1].userId} at {rows[1].value} and {rows[2].userId} at {rows[2].value}`
		end
	end

	return true, nil
end
