--[[
    A board's key is a non-empty string of at most 50 characters, the most
    a DataStore name holds: exactly 50 builds, and 51 or none throws
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local LONGEST: number = 50
local EXPIRY: number = 60

type Entry = { name: string, config: any }

return function (): (boolean, string | nil)
	local Board: any = Environment.new().require("Board/init")
	local longest: string = string.rep("k", LONGEST)
	local over: string = string.rep("k", LONGEST + 1)

	local built: { Entry } = {
		{ name = "Daily", config = longest },
		{ name = "AllTime", config = longest },
		{ name = "Wipe", config = { expirySeconds = EXPIRY, key = longest } },
	}

	for _, entry: Entry in built do
		local ran: boolean, thrown: any = pcall(Board.new, entry.name, entry.config)
		if not ran then
			return false, `{entry.name} with a key of {LONGEST} characters threw: {thrown}`
		end
	end

	local refused: { Entry } = {
		{ name = "Daily", config = over },
		{ name = "AllTime", config = over },
		{ name = "Wipe", config = { expirySeconds = EXPIRY, key = over } },
		{ name = "Weekly", config = "" },
		{ name = "Wipe", config = { expirySeconds = EXPIRY, key = "" } },
		{ name = "Wipe", config = { expirySeconds = EXPIRY, key = 7 } },
		{ name = "Wipe", config = { expirySeconds = EXPIRY } },
	}

	for _, entry: Entry in refused do
		local ran: boolean, thrown: any = pcall(Board.new, entry.name, entry.config)
		if ran then
			return false, `{entry.name} built with the key {entry.config.key or entry.config}`
		end

		if not Mentions(thrown, entry.name) then
			return false, `the key's message did not name the board: {thrown}`
		end
	end

	return true, nil
end
