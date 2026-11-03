--[[
    A file inside the fixture's folder module, which reaches a dependency
    one Parent further than its folder does
--]]

--!strict
local Signal = require(script.Parent.Parent.Parent.Signal)

return {
	Signal = Signal,
}
