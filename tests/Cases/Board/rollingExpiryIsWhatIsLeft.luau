--[[
    A rolling entry expires when its window does: a later write sets the
    expiry to what is left of the window the first write opened
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local KEY: string = "Expiry-Wipe"
local USER: number = 1
local STEP: number = 1 -- Each write inside the first window
local REOPENING: number = 4 -- The write after the window ends
local WINDOW: number = 3600
local LATER: number = 1000
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local board: any = env.require("Board/init").new("Wipe", { expirySeconds = WINDOW, key = KEY })
	local start: number = env.clock.now()

	env.settle(board:read(AMOUNT))
	env.settle(board:update(USER, Boards.add(STEP)))

	local first: { any } = env.services.MemoryStoreService.peek(KEY)
	if #first ~= 1 or first[1].expiresAt ~= start + WINDOW then
		return false, `the first write expires at {first[1] and first[1].expiresAt}, not {start + WINDOW}`
	end

	env.clock.advance(LATER)
	env.settle(board:update(USER, Boards.add(STEP)))

	local later: { any } = env.services.MemoryStoreService.peek(KEY)
	if #later ~= 1 or later[1].value ~= STEP + STEP or later[1].expiresAt ~= start + WINDOW then
		return false, `the later write expires at {later[1] and later[1].expiresAt}, not {start + WINDOW}`
	end

	-- Once the window ends, the next write opens a new one from zero
	env.clock.advance(WINDOW)
	local reopened: number = env.clock.now()
	local ok: boolean, total: any = env.settle(board:update(USER, Boards.add(REOPENING)))
	local record: any = env.services.DataStoreService.peek(KEY, USER)
	local items: { any } = env.services.MemoryStoreService.peek(KEY)

	if not ok or total ~= REOPENING or record.window ~= reopened then
		return false, `the write after the window resolved with {total} in the window from {record.window}`
	end

	if #items ~= 1 or items[1].value ~= REOPENING or items[1].expiresAt ~= reopened + WINDOW then
		return false, `the new window's row expires at {items[1] and items[1].expiresAt}, not {reopened + WINDOW}`
	end

	return true, nil
end
