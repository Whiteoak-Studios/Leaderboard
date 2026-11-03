--[[
    An id the lookup does not return stays nil, and the next request asks
    for it again and fills it once UserService holds a name for it
--]]

--!strict
local Environment = require("../../Environment")

local USER_ID: number = 1

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.UserService
	local Names: any = env.require("Names")

	Names:request({ USER_ID })
	env.clock.advance(0)

	local username: string?, displayName: string? = Names:get(USER_ID)
	if username ~= nil or displayName ~= nil then
		return false, `an id the lookup left out got {username} and {displayName}`
	end

	service.set(USER_ID, "builderman", "Builder")
	Names:request({ USER_ID })
	env.clock.advance(0)

	username, displayName = Names:get(USER_ID)
	if username ~= "builderman" or displayName ~= "Builder" then
		return false, `the next request did not ask again, and get gave {username} and {displayName}`
	end

	return true, nil
end
