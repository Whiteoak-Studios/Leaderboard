--[[
    A set still in flight when the server closes lands on every board before
    the BindToClose function returns, from a live object and from one the
    game destroyed before the close alike
--]]

--!strict
local Environment = require("../../Environment")

local USER: number = 1
local VALUE: number = 25
local DELAY: number = 10
local WRITES: number = 4 -- Two boards for each of the two objects

type Keys = { Daily: string, AllTime: string }

local KEYS: { [string]: Keys } = {
	live = { Daily = "Closing-Live-Daily", AllTime = "Closing-Live-AllTime" },
	destroyed = { Daily = "Closing-Gone-Daily", AllTime = "Closing-Gone-AllTime" },
}

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local data: any = env.services.DataStoreService
	local Leaderboard: any = env.require("init")

	for _ = 1, WRITES do
		data.delayNext("UpdateAsync", DELAY)
	end

	local sets: { [string]: any } = {}
	for name: string, keys: Keys in KEYS do
		local object: any = Leaderboard.new(keys)
		sets[name] = object:set("All", USER, VALUE)

		-- Only the module's record of writes in flight still holds this object's set at the close
		if name == "destroyed" then
			object:destroy()
		end
	end

	if not env.close() then
		return false, "BindToClose did not return within the 30 s the engine gives it"
	end

	for name: string, keys: Keys in KEYS do
		local daily: any = data.peek(keys.Daily, USER)
		local highest: number? = data.peekOrdered(keys.AllTime, USER)
		if sets[name]:getStatus() ~= Environment.RESOLVED or not daily or daily.total ~= VALUE or highest ~= VALUE then
			local landed: string = `Daily {daily and daily.total} and AllTime {highest}`
			return false, `BindToClose returned with the {name} object's set {sets[name]:getStatus()}, {landed}`
		end
	end

	return true, nil
end
