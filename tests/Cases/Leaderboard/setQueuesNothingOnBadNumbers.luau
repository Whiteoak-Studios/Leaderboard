--[[
    set throws on a value that is negative, fractional or not finite and
    queues nothing, so the next save leaves every store empty for the player
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")
local Start = require("../../Start")

local DAILY: string = "Queue-Set-Daily"
local ALL_TIME: string = "Queue-Set-AllTime"
local USER: number = 1

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local maps: any = env.services.MemoryStoreService
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = DAILY, AllTime = ALL_TIME })

	-- A board writes rows only once this server has read it, so a stray write would show in the map
	local read: boolean, reason: any = env.settle(object:getAll("All"))
	if not read then
		return false, `the first read rejected: {reason}`
	end

	local values: { number } = { -1, 1.5, math.huge, -math.huge, 0 / 0 }
	for _, value: number in values do
		local ran: boolean, thrown: any = pcall(object.set, object, "All", USER, value)
		if ran or not Mentions(thrown, tostring(value)) then
			return false, `set took the value {value}, or threw without naming it: {thrown}`
		end
	end

	local saved: boolean, refused: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {refused}`
	end

	local record: any = data.peek(DAILY, USER)
	local highest: number? = data.peekOrdered(ALL_TIME, USER)
	local rows: { any } = maps.peek(`{DAILY}:{Start.DAY}`)
	if record ~= nil or highest ~= nil or #rows ~= 0 then
		local stored: string = `Daily {record and record.total}, AllTime {highest}, {#rows} rows`
		return false, `a refused set was queued or written: {stored}`
	end

	return true, nil
end
