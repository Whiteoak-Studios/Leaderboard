--[[
    An object of more than MAX_BOARDS boards throws while one of exactly
    MAX_BOARDS builds, a live object past MAX_OBJECTS throws, and a
    destroyed object frees its slot
--]]

--!strict
local Environment = require("../../Environment")

local PERIODS: { string } = { "Hourly", "Daily", "Weekly", "Monthly", "AllTime" }

--[[
    Every period name, then rolling boards up to the given count
--]]

local function boards(count: number): { [string]: any }
	local built: { [string]: any } = {}
	for index: number, name: string in PERIODS do
		if index <= count then
			built[name] = `Slots-{name}-{count}`
		end
	end

	for index: number = #PERIODS + 1, count do
		built[`Rolling{index}`] = { expirySeconds = 3600, key = `Slots-Rolling{index}-{count}` }
	end

	return built
end

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Constants: any = env.require("Constants")
	local Leaderboard: any = env.require("init")

	local over: boolean = pcall(Leaderboard.new, boards(Constants.MAX_BOARDS + 1))
	if over then
		return false, `an object of {Constants.MAX_BOARDS + 1} boards built`
	end

	local objects: { any } = {}
	for index: number = 1, Constants.MAX_OBJECTS do
		local built: boolean, object: any = pcall(Leaderboard.new, boards(Constants.MAX_BOARDS - index + 1))
		if not built then
			return false, `object {index} of {Constants.MAX_OBJECTS} threw: {object}`
		end

		table.insert(objects, object)
	end

	local extra: boolean = pcall(Leaderboard.new, { Daily = "Slots-Extra-Daily" })
	if extra then
		return false, `a live object past {Constants.MAX_OBJECTS} built`
	end

	local destroyed: boolean, reason: any = env.settle(objects[1]:destroy())
	if not destroyed then
		return false, `the destroy's last save rejected: {reason}`
	end

	local rebuilt: boolean, thrown: any = pcall(Leaderboard.new, { Daily = "Slots-Rebuilt-Daily" })
	if not rebuilt then
		return false, `a destroyed object left its slot held: {thrown}`
	end

	return true, nil
end
