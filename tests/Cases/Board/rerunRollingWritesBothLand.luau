--[[
    Two writes to one player on a rolling board both land when UpdateAsync
    re-runs, and every re-run keeps the window the first write opened
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local KEY: string = "Rerun-Wipe"
local WINDOW: number = 3600
local USER: number = 1
local FIRST: number = 3
local FORCED: number = 5
local DELAYED: number = 10
local CROSSING: number = 7
local LATER: number = 600 -- Inside the window, so a re-run that opened a new one would show
local DELAY: number = 5
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local board: any = env.require("Board/init").new("Wipe", { expirySeconds = WINDOW, key = KEY })
	local start: number = env.clock.now()

	env.settle(board:read(AMOUNT))
	env.settle(board:update(USER, Boards.add(FIRST)))
	env.clock.advance(LATER)

	-- A forced re-run runs the transform twice on the same value, so the total counts the amount once
	service.rerunNext("UpdateAsync")
	local forced: boolean, total: any = env.settle(board:update(USER, Boards.add(FORCED)))
	if not forced or total ~= FIRST + FORCED then
		return false, `the forced re-run resolved with {total}, not {FIRST + FORCED}`
	end

	-- The delayed write re-runs on the value the crossing write landed
	service.delayNext("UpdateAsync", DELAY)
	local delayed: any = board:update(USER, Boards.add(DELAYED))
	local crossing: any = board:update(USER, Boards.add(CROSSING))

	local landed: boolean, final: any = env.settle(delayed)
	local crossed: boolean, between: any = env.settle(crossing)
	local sum: number = FIRST + FORCED + DELAYED + CROSSING

	if not landed or not crossed or final ~= sum or between ~= sum - DELAYED then
		return false, `the crossing writes resolved with {between} and {final}, not {sum - DELAYED} and {sum}`
	end

	local record: any = service.peek(KEY, USER)
	if not record or record.window ~= start then
		return false, `the re-runs moved the window from the first write's {start} to {record and record.window}`
	end

	local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
	if not ok or #rows ~= 1 or rows[1].value ~= sum then
		return false, `the row read {ok and rows[1] and rows[1].value}, not {sum}`
	end

	return true, nil
end
