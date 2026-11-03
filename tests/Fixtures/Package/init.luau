--[[
    The smallest package the environment cases load: it hands back what its
    requires found at each depth and the globals the fake game gives it
--]]

--!strict
local Promise: any = require(script.Parent.Promise)
local Signal = require(script.Parent.Signal)

local Board = require(script.Board)
local Queue = require(script.Queue)

return {
	Promise = Promise,
	Signal = Signal,
	Board = Board,
	Queue = Queue,
	game = game,
	task = task,
	os = os,
	DateTime = DateTime,
	Enum = Enum,
}
