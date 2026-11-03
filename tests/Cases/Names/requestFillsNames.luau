--[[
    Once a request's lookup has answered, get gives each id the username and
    the display name UserService holds for it
--]]

--!strict
local Environment = require("../../Environment")

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.UserService
	local Names: any = env.require("Names")
	service.set(1, "builderman", "Builder")
	service.set(2, "noob", "Noob")

	Names:request({ 1, 2 })
	env.clock.advance(0)

	local username: string?, displayName: string? = Names:get(1)
	if username ~= "builderman" or displayName ~= "Builder" then
		return false, `id 1 got {username} and {displayName}`
	end

	username, displayName = Names:get(2)
	if username ~= "noob" or displayName ~= "Noob" then
		return false, `id 2 got {username} and {displayName}`
	end

	return true, nil
end
