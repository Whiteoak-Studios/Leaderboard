--[[
    The shutdown save writes rows too: once every board has been read, the
    BindToClose function returns only after a rolling board's and Daily's
    rows have landed at the queued amount, and throws nothing
--]]

--!strict
local Environment = require("../../Environment")
local Start = require("../../Start")

local DAILY: string = "Shutdown-Rows-Daily"
local WIPE: string = "Shutdown-Rows-Wipe"
local USER: number = 1
local AMOUNT: number = 6
local DELAY: number = 5
local WRITES: number = 2 -- One write per board on each store

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local maps: any = env.services.MemoryStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({
		Daily = DAILY,
		Wipe = { expirySeconds = 3600, key = WIPE },
	})

	-- A board writes rows only once this server has read it
	local read: boolean, reason: any = env.settle(object:getAll("All"))
	if not read then
		return false, `the first read rejected: {reason}`
	end

	object:increment("All", USER, AMOUNT)
	for _ = 1, WRITES do
		data.delayNext("UpdateAsync", DELAY)
		maps.delayNext("UpdateAsync", DELAY)
	end

	if not env.close() then
		return false, "BindToClose threw, or did not return within the 30 s the engine gives it"
	end

	local named: { [string]: string } = { Daily = `{DAILY}:{Start.DAY}`, Wipe = WIPE }
	for board: string, map: string in named do
		local rows: { any } = maps.peek(map)
		if #rows ~= 1 or rows[1].key ~= `{USER}` or rows[1].value ~= AMOUNT then
			local landed: string = `{#rows} rows, the first at {rows[1] and rows[1].value}`
			return false, `BindToClose returned before {board}'s row landed: {landed}`
		end
	end

	return true, nil
end
