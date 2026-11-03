--[[
    settle advances the clock until a promise settles and returns its result,
    and fails the case when one is still pending past its bound
--]]

--!strict
local Environment = require("../../Environment")
local Mentions = require("../../Mentions")

local FIXTURE: string = "tests/Fixtures/Package"
local DELAY: number = 5

return function (): (boolean, string | nil)
	local env: any = Environment.new({ root = FIXTURE })
	local Promise: any = env.require("init").Promise
	local start: number = env.clock.now()

	local resolved: { n: number, [number]: any } = table.pack(env.settle(Promise.delay(DELAY):andThen(function ()
		return "first", "second"
	end)))

	if resolved[1] ~= true or resolved[2] ~= "first" or resolved[3] ~= "second" then
		return false, `a resolved promise settled as {resolved[1]}, {resolved[2]}, {resolved[3]}`
	end

	if env.clock.now() - start < DELAY then
		return false, "settle returned before the delay passed"
	end

	local rejected: { n: number, [number]: any } = table.pack(env.settle(Promise.reject("refused")))
	if rejected[1] ~= false or rejected[2] ~= "refused" then
		return false, `a rejected promise settled as {rejected[1]}, {rejected[2]}`
	end

	local ran: boolean, thrown: any = pcall(env.settle, Promise.new(function () end))
	if ran or not Mentions(thrown, "still pending after") then
		return false, `settle passed a promise that never settles: {thrown}`
	end

	return true, nil
end
