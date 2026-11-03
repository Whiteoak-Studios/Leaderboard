--[[
    A rolling board's expiry is whole seconds from 60 to 3,888,000 inclusive:
    the bounds build, and past either, a fraction or a non-number throws
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Bounds-Wipe"
local SHORTEST: number = 60
local LONGEST: number = 3888000
local FRACTIONAL: number = 60.5

return function (): (boolean, string | nil)
	local Board: any = Environment.new().require("Board/init")

	for _, expirySeconds: number in { SHORTEST, LONGEST } do
		local ran: boolean, thrown: any = pcall(Board.new, "Wipe", { expirySeconds = expirySeconds, key = KEY })
		if not ran then
			return false, `an expiry of {expirySeconds} threw: {thrown}`
		end
	end

	local refused: { any } = { SHORTEST - 1, LONGEST + 1, FRACTIONAL, "60", 0 / 0, math.huge, false }
	for _, expirySeconds: any in refused do
		local ran: boolean, thrown: any = pcall(Board.new, "Wipe", { expirySeconds = expirySeconds, key = KEY })
		if ran then
			return false, `an expiry of {expirySeconds} built`
		end

		if not Mentions(thrown, "Wipe") then
			return false, `the expiry's message did not name the board: {thrown}`
		end
	end

	local _, fraction: any = pcall(Board.new, "Wipe", { expirySeconds = FRACTIONAL, key = KEY })
	if not Mentions(fraction, "whole") then
		return false, `a fractional expiry's message did not say it takes whole seconds: {fraction}`
	end

	return true, nil
end
