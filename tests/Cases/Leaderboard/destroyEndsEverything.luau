--[[
    destroy cancels the automation, so nothing reads after it, disconnects
    every subscriber of both signals, and every method called afterwards
    throws, destroy included
--]]

--!strict
local Calls = require("../../Calls")
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Destroy-Daily"
local USER: number = 1
local AMOUNT: number = 1
local INTERVAL: number = 90
local LATER: number = 10 -- Intervals the clock runs on after the destroy

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY }, { automation = true, interval = INTERVAL })
	local reads: { { any } } = Calls(env.services.MemoryStoreService, "GetSortedMap")

	local fired: number = 0
	object.updated:Connect(function ()
		fired += 1
	end)
	object.boardUpdated:Connect(function ()
		fired += 1
	end)

	env.clock.advance(INTERVAL)
	if #reads ~= 1 or fired ~= 2 then
		return false, `before the destroy the loop read {#reads} times and fired {fired} times`
	end

	local destroyed: boolean, reason: any = env.settle(object:destroy())
	if not destroyed then
		return false, `the destroy's last save rejected: {reason}`
	end

	local subscribers: number = #object.updated:GetConnections() + #object.boardUpdated:GetConnections()
	if subscribers > 0 then
		return false, `{subscribers} subscribers are still connected after the destroy`
	end

	env.clock.advance(INTERVAL * LATER)
	if #reads ~= 1 or fired ~= 2 then
		return false, `after the destroy the loop read {#reads - 1} more times`
	end

	local calls: { [string]: () -> () } = {
		increment = function ()
			object:increment("All", USER, AMOUNT)
		end,

		set = function ()
			object:set("All", USER, AMOUNT)
		end,

		save = function ()
			object:save()
		end,

		getAll = function ()
			object:getAll("All")
		end,

		delete = function ()
			object:delete("All", USER)
		end,

		destroy = function ()
			object:destroy()
		end,
	}

	for method: string, call: () -> () in calls do
		local ran: boolean, thrown: any = pcall(call)
		if ran or not Mentions(thrown, "destroyed") then
			return false, `{method} on a destroyed object did not throw that it was destroyed: {thrown}`
		end
	end

	return true, nil
end
