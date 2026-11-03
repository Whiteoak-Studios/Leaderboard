--[[
    An object that throws while being built, on its boards or on its
    automation, holds no slot, so MAX_OBJECTS objects still build after
    it, and the one past them throws
--]]

--!strict
local Environment = require("../../Environment")

local INTERVAL: number = 90

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")

	local failing: { [string]: () -> () } = {
		noBoards = function ()
			Leaderboard.new({})
		end,

		noTable = function ()
			Leaderboard.new(nil)
		end,

		emptyKey = function ()
			Leaderboard.new({ Daily = "" })
		end,

		sharedKey = function ()
			Leaderboard.new({ Daily = "Partway-Shared", Weekly = "Partway-Shared" })
		end,

		shortExpiry = function ()
			Leaderboard.new({ Wipe = { expirySeconds = 30, key = "Partway-Wipe" } })
		end,

		badRecordCount = function ()
			local automation: any = { automation = true, interval = INTERVAL, recordCount = 0 }
			Leaderboard.new({ Daily = "Partway-Daily" }, automation)
		end,
	}

	for name: string, build: () -> () in failing do
		local built: boolean = pcall(build)
		if built then
			return false, `the {name} object built`
		end
	end

	for index: number = 1, Constants.MAX_OBJECTS do
		local built: boolean, thrown: any = pcall(Leaderboard.new, { Daily = `Partway-Daily-{index}` })
		if not built then
			return false, `object {index} threw after the failed builds: {thrown}`
		end
	end

	local extra: boolean = pcall(Leaderboard.new, { Daily = "Partway-Extra" })
	if extra then
		return false, `a live object past {Constants.MAX_OBJECTS} built`
	end

	return true, nil
end
