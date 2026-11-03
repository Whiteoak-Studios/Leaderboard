--[[
    new throws on a Yearly board with a message naming MemoryStore's 45-day
    limit, and the failed object holds no slot
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local LIMIT: string = "a MemoryStore entry lives at most 45 days"

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")

	local built: boolean, thrown: any = pcall(Leaderboard.new, { Yearly = "Slot-Yearly", Daily = "Slot-Daily" })
	if built or not Mentions(thrown, LIMIT) then
		return false, `a Yearly board built, or threw without naming the limit: {thrown}`
	end

	for index: number = 1, Constants.MAX_OBJECTS do
		local rebuilt: boolean, failure: any = pcall(Leaderboard.new, { Daily = `Slot-Daily-{index}` })
		if not rebuilt then
			return false, `object {index} threw after the Yearly one: {failure}`
		end
	end

	return true, nil
end
