--[[
    A key string is only for Hourly, Daily, Weekly, Monthly and AllTime, and
    any other malformed board throws with a message naming the board
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Kills-1"
local WINDOWS: { string } = { "Hourly", "Daily", "Weekly", "Monthly", "AllTime" }

type Entry = { name: any, config: any, named: string }

return function (): (boolean, string | nil)
	local Board: any = Environment.new().require("Board/init")

	local refused: { Entry } = {
		{ name = "Kills", config = KEY, named = "Kills" },
		{ name = "daily", config = KEY, named = "daily" },
		{ name = "Rolling", config = KEY, named = "Rolling" },
		{ name = "Daily", config = 7, named = "Daily" },
		{ name = "Daily", config = nil, named = "Daily" },
		{ name = "Daily", config = true, named = "Daily" },
		{ name = 1, config = KEY, named = "1" },
	}

	for _, entry: Entry in refused do
		local ran: boolean, thrown: any = pcall(Board.new, entry.name, entry.config)
		if ran then
			return false, `{entry.name} built with {entry.config}`
		end

		if not Mentions(thrown, entry.named) then
			return false, `the message did not name {entry.named}: {thrown}`
		end
	end

	for _, name: string in WINDOWS do
		local ran: boolean, thrown: any = pcall(Board.new, name, `Kills-{name}`)
		if not ran then
			return false, `{name} with a key string threw: {thrown}`
		end
	end

	return true, nil
end
