--[[
    close runs every function bound to close on its own thread and passes
    once they return, and fails after 30 s of fake time when one never does
--]]

--!strict
local Environment = require("../../Environment")

local FIXTURE: string = "tests/Fixtures/Package"
local BOUND: number = 2 -- Functions bound to close that return
local SAVE: number = 5
local LIMIT: number = 30

return function (): (boolean, string | nil)
	local env: any = Environment.new({ root = FIXTURE })
	local package: any = env.require("init")
	local saved: number = 0

	for _ = 1, BOUND do
		package.game:BindToClose(function ()
			package.task.wait(SAVE)
			saved += 1
		end)
	end

	local start: number = env.clock.now()
	if not env.close() or saved ~= BOUND then
		return false, `close failed with {saved} of {BOUND} bound functions returned`
	end

	if env.clock.now() - start >= LIMIT then
		return false, "close waited out its limit after every function had returned"
	end

	local hung: any = Environment.new({ root = FIXTURE })
	local hungPackage: any = hung.require("init")

	hungPackage.game:BindToClose(function ()
		hungPackage.task.wait(LIMIT * 2)
	end)

	local hungStart: number = hung.clock.now()
	if hung.close() then
		return false, "close passed with a bound function that never returned"
	end

	if hung.clock.now() - hungStart < LIMIT then
		return false, `close gave up after {hung.clock.now() - hungStart} s, before its limit`
	end

	return true, nil
end
