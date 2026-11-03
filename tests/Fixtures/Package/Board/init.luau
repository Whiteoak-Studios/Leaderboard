--[[
    A folder module of the fixture package, which reaches a dependency one
    Parent further than the package root does
--]]

--!strict
local Promise: any = require(script.Parent.Parent.Promise)

local Rows = require(script.Rows)

return {
	Promise = Promise,
	Rows = Rows,
}
