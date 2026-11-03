--[[
    A read never waits on a name: an unknown id gives two nils at once, and
    asking for it returns at once while its lookup is still waiting
--]]

--!strict
local Environment = require("../../Environment")

local DELAY: number = 5
local USER_ID: number = 1

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.UserService
	local Names: any = env.require("Names")
	service.set(USER_ID, "builderman", "Builder")
	service.delayNext("GetUserInfosByUserIdsAsync", DELAY)

	--[[
	    Runs the call on a thread of its own, which stays parked on the fake
	    clock if the call yields
	--]]

	local function atOnce(call: () -> ()): boolean
		local returned: boolean = false
		env.clock.task.spawn(function ()
			call()
			returned = true
		end)

		return returned
	end

	local username: string?, displayName: string? = "", ""
	local function read()
		username, displayName = Names:get(USER_ID)
	end

	if not atOnce(read) or username ~= nil or displayName ~= nil then
		return false, `get gave {username} and {displayName} for an unknown id, or yielded`
	end

	if not atOnce(function ()
		Names:request({ USER_ID })
	end) then
		return false, "request waited on its lookup"
	end

	if not atOnce(read) or username ~= nil or displayName ~= nil then
		return false, `get gave {username} and {displayName} while the lookup waited, or yielded`
	end

	env.clock.advance(DELAY)
	read()
	if username ~= "builderman" or displayName ~= "Builder" then
		return false, `the request started no lookup that answered, and get gave {username} and {displayName}`
	end

	return true, nil
end
