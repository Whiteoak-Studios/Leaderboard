--[[
    The batched user lookup answers the ids it holds a name for and leaves
    the rest out, and refuses more than 200 ids in one call
--]]

--!strict
local Environment = require("../../Environment")
local Refuses = require("../../Refuses")

local FIRST: number = 1
local SECOND: number = 2
local UNNAMED: number = 3 -- An id no name was set for
local FIRST_USERNAME: string = "builderman"
local SECOND_DISPLAY_NAME: string = "Noob"
local MOST: number = 200

return function (): (boolean, string | nil)
	local service: any = Environment.new().services.UserService
	service.set(FIRST, FIRST_USERNAME, "Builder")
	service.set(SECOND, "noob", SECOND_DISPLAY_NAME)

	local infos: { any } = service:GetUserInfosByUserIdsAsync({ FIRST, SECOND, UNNAMED })
	if #infos ~= 2 or infos[1].Username ~= FIRST_USERNAME or infos[2].DisplayName ~= SECOND_DISPLAY_NAME then
		return false, `the lookup answered {#infos} ids`
	end

	local tooMany: { number } = table.create(MOST + 1, FIRST)
	Refuses(`GetUserInfosByUserIdsAsync takes at most {MOST} ids, not {MOST + 1}`, function ()
		service:GetUserInfosByUserIdsAsync(tooMany)
	end)

	return true, nil
end
