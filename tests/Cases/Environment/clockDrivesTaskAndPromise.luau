--[[
    The fake clock moves the package's task, os, DateTime and Promise's
    delays together, and nothing runs until a case advances it
--]]

--!strict
local Environment = require("../../Environment")
local Start = require("../../Start")

local FIXTURE: string = "tests/Fixtures/Package"
local FRAME: number = 1 / 60
local DELAY: number = 1 -- The delayed function's delay
local CANCELED: number = 1.5 -- The canceled function's delay
local WAIT: number = 2 -- The spawned thread's wait
local PROMISE_DELAY: number = 3

return function (): (boolean, string | nil)
	local env: any = Environment.new({ root = FIXTURE })
	local package: any = env.require("init")
	local task: any, os: any = package.task, package.os
	local startTime: number = os.time()
	local log: { string } = {}

	task.spawn(function ()
		local waited: number = task.wait(WAIT)
		table.insert(log, `wait {waited}`)
	end)

	task.delay(DELAY, function ()
		table.insert(log, "delay")
	end)

	task.defer(function ()
		table.insert(log, "defer")
	end)

	task.cancel(task.delay(CANCELED, function ()
		table.insert(log, "canceled")
	end))

	local promised: boolean = false
	package.Promise.delay(PROMISE_DELAY):andThen(function ()
		promised = true
	end)

	if #log ~= 0 then
		return false, `{log[1]} ran before the clock moved`
	end

	env.clock.advance(0)
	if log[1] ~= "defer" or #log ~= 1 then
		return false, "advance(0) did not run only the deferred work"
	end

	env.clock.advance(WAIT)
	if table.concat(log, ", ") ~= `defer, delay, wait {WAIT}` then
		return false, `the clock ran {table.concat(log, ", ")}`
	end

	-- Promise.delay resolves on the first Heartbeat past its time, as on a server
	env.clock.advance(PROMISE_DELAY - WAIT)
	if promised then
		return false, "Promise.delay resolved on the Heartbeat at its time, not after it"
	end

	env.clock.advance(FRAME)
	if not promised then
		return false, "Promise.delay had not resolved a frame after its time"
	end

	if os.time() ~= startTime + PROMISE_DELAY or os.clock() ~= PROMISE_DELAY + FRAME then
		return false, `os moved {os.time() - startTime} s and os.clock read {os.clock()}`
	end

	local day: number = package.DateTime.fromUniversalTime(2026, 11, 4).UnixTimestamp
	if package.DateTime.now().UnixTimestamp ~= os.time() or day ~= startTime - Start.SINCE_MIDNIGHT then
		return false, "DateTime did not read the fake clock"
	end

	if os.date("!*t").hour ~= 12 then
		return false, `os.date read hour {os.date("!*t").hour}`
	end

	return true, nil
end
