--[[
    A Yearly board throws with a message naming MemoryStore's 45-day limit
    and the windows the package supports, while a rolling one may take the name
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local KEY: string = "Kills-Yearly"
local WORDS: { string } = { "Hourly", "Daily", "Weekly", "Monthly", "AllTime", "45 days", "Yearly" }

return function (): (boolean, string | nil)
	local Board: any = Environment.new().require("Board/init")

	local ran: boolean, thrown: any = pcall(Board.new, "Yearly", KEY)
	if ran then
		return false, "a Yearly board built"
	end

	for _, word: string in WORDS do
		if not Mentions(thrown, word) then
			return false, `Yearly's message did not say {word}: {thrown}`
		end
	end

	local rolling: boolean, reason: any = pcall(Board.new, "Yearly", { expirySeconds = 3600, key = KEY })
	if not rolling then
		return false, `a rolling board named Yearly threw: {reason}`
	end

	return true, nil
end
