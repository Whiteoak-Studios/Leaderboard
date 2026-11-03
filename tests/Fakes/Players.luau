--[[
    A fake Players holding the PlayerRemoving signal the package may listen
    on, and remove, which fires it as a player leaving does
--]]

--!strict
local Faults = require("./Faults")

export type Players = {
	PlayerRemoving: any,
	failNext: (method: string, count: number?) -> (),
	delayNext: (method: string, seconds: number) -> (),
	remove: (userId: number) -> (),
}

local Players = {}

--[[
    Builds a Players whose signal comes from the given Signal module. It has
    no method that can fail or delay, so its faults refuse every name
--]]

function Players.new(Signal: any, sleep: (seconds: number?) -> number): Players
	local faults: Faults.Faults = Faults.new("Players", {}, sleep)
	local removing: any = Signal.new()

	return {
		PlayerRemoving = removing,
		failNext = faults.failNext,
		delayNext = faults.delayNext,

		remove = function (userId: number)
			removing:Fire({ UserId = userId })
		end,
	}
end

return Players
