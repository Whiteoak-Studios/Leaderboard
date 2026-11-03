--[[
    A file directly under the fixture package's root, which reaches a
    dependency at the depth its folder modules do
--]]

--!strict
local Promise: any = require(script.Parent.Parent.Promise)

return {
	Promise = Promise,
}
