--[[
    Two writes to one player both land when UpdateAsync re-runs, forced or
    because the other write landed first, and a re-run never counts twice
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local USER: number = 1
local FORCED: number = 5
local DELAYED: number = 10
local CROSSING: number = 7
local DELAY: number = 5
local AMOUNT: number = 100

type Entry = { name: string, config: string }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Rerun-Daily" },
	{ name = "AllTime", config = "Rerun-AllTime" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local service: any = env.services.DataStoreService
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(AMOUNT))

		-- A forced re-run runs the transform twice on the same value, so the total counts the amount once
		service.rerunNext("UpdateAsync")
		local forced: boolean, total: any = env.settle(board:update(USER, Boards.add(FORCED)))
		if not forced or total ~= FORCED then
			return false, `{entry.name}'s forced re-run resolved with {total}, not {FORCED}`
		end

		-- The delayed write re-runs on the value the crossing write landed
		service.delayNext("UpdateAsync", DELAY)
		local delayed: any = board:update(USER, Boards.add(DELAYED))
		local crossing: any = board:update(USER, Boards.add(CROSSING))

		local landed: boolean, final: any = env.settle(delayed)
		local crossed: boolean, between: any = env.settle(crossing)
		local sum: number = FORCED + DELAYED + CROSSING

		if not landed or not crossed or final ~= sum or between ~= FORCED + CROSSING then
			return false,
				`{entry.name}'s crossing writes resolved with {between} and {final}, not {FORCED + CROSSING} and {sum}`
		end

		local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not ok or #rows ~= 1 or rows[1].value ~= sum then
			return false, `{entry.name}'s row read {ok and rows[1] and rows[1].value}, not {sum}`
		end
	end

	return true, nil
end
