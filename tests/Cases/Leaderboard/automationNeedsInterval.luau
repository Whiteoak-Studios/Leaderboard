--[[
    An automation table throws in new when automation is not a boolean, when
    it is true and interval is missing or not a positive number, or when its
    recordCount is not a range, and automation = false needs no interval
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Interval-Daily"
local INTERVAL: number = 90

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")

	local refused: { [string]: any } = {
		noInterval = { automation = true },
		zero = { automation = true, interval = 0 },
		negative = { automation = true, interval = -INTERVAL },
		text = { automation = true, interval = `{INTERVAL}` },
		infinite = { automation = true, interval = math.huge },
		notANumber = { automation = true, interval = 0 / 0 },
		notBoolean = { automation = "true", interval = INTERVAL },
		noAutomation = { interval = INTERVAL },
		overRows = { automation = true, interval = INTERVAL, recordCount = 101 },
		unknownBoard = { automation = true, interval = INTERVAL, recordCount = { Hourly = 5 } },
		notTable = INTERVAL,
	}

	for name: string, automation: any in refused do
		local built: boolean = pcall(Leaderboard.new, { Daily = KEY }, automation)
		if built then
			return false, `the {name} automation built`
		end
	end

	local built: boolean, object: any = pcall(Leaderboard.new, { Daily = KEY }, { automation = false })
	if not built then
		return false, `automation = false with no interval threw: {object}`
	end

	return true, nil
end
