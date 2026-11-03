--[[
    validateAll validates every board and throws when two share a key,
    naming both, whatever their kinds
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Same-Key"

return function (): (boolean, string | nil)
	local Board: any = Environment.new().require("Board/init")

	local shared: { { [string]: any } } = {
		{ Daily = KEY, Weekly = KEY },
		{ Daily = KEY, Wipe = { expirySeconds = 60, key = KEY } },
		{ AllTime = KEY, Monthly = KEY },
	}

	for _, boards: { [string]: any } in shared do
		local ran: boolean, thrown: any = pcall(Board.validateAll, boards)
		local message: string = tostring(thrown)
		local names: { string } = {}
		for name: string in boards do
			table.insert(names, name)
		end

		if ran then
			return false, `{table.concat(names, " and ")} shared a key and validateAll passed`
		end

		if not Mentions(message, names[1]) or not Mentions(message, names[2]) then
			return false, `the shared key's message named only one board: {message}`
		end
	end

	if not pcall(Board.validateAll, { Daily = "Kills-Daily", Weekly = "Kills-Weekly", AllTime = "Kills-AllTime" }) then
		return false, "validateAll refused boards with distinct keys"
	end

	if pcall(Board.validateAll, { Daily = "Kills-Daily", Hourly = "" }) then
		return false, "validateAll passed a board validate refuses"
	end

	return true, nil
end
