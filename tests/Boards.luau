--[[
    What the Board cases share: transforms that add to or set a player's
    total, and a fill that writes numbered players' rows one at a time
--]]

--!strict
local Environment = require("./Environment")

type Environment = Environment.Environment

local Boards = {}

--[[
    A transform adding the amount to the player's total in the current window
--]]

function Boards.add(amount: number): (old: number) -> number
	return function (old: number): number
		return old + amount
	end
end

--[[
    A transform setting the player's total to the value, whatever it was
--]]

function Boards.set(value: number): (old: number) -> number
	return function (): number
		return value
	end
end

--[[
    Writes players 1 to count, each at floor plus their user id, settling
    each update on the environment's clock before the next, and throws if
    one rejects
--]]

function Boards.fill(env: Environment, board: any, count: number, floor: number?)
	for userId: number = 1, count do
		local updated: boolean = env.settle(board:update(userId, Boards.set((floor or 0) + userId)))
		assert(updated, `fill's update of player {userId} rejected`)
	end
end

return Boards
