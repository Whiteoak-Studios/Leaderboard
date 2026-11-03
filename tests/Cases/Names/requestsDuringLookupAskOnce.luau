--[[
    Requests made while a lookup waits ask only for the ids it is not asking
    for, and a cached id is never asked for again, so each id goes out once
--]]

--!strict
local Calls = require("../../Calls")
local Environment = require("../../Environment")

local DELAY: number = 5
local USER_IDS: { number } = { 1, 2, 3 }

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.UserService
	local Names: any = env.require("Names")
	for _, userId: number in USER_IDS do
		service.set(userId, `user{userId}`, `User {userId}`)
	end

	local calls: { { any } } = Calls(service, "GetUserInfosByUserIdsAsync")
	service.delayNext("GetUserInfosByUserIdsAsync", DELAY)

	Names:request({ 1, 2 })
	Names:request({ 1, 2 })
	Names:request(USER_IDS)
	env.clock.advance(DELAY)

	Names:request(USER_IDS)
	env.clock.advance(0)

	local asked: { [number]: number } = {}
	for _, call: { any } in calls do
		for _, userId: number in call[2] do
			asked[userId] = (asked[userId] or 0) + 1
		end
	end

	for _, userId: number in USER_IDS do
		if asked[userId] ~= 1 then
			return false, `id {userId} went out {asked[userId] or 0} times`
		end

		local username: string?, displayName: string? = Names:get(userId)
		if username ~= `user{userId}` or displayName ~= `User {userId}` then
			return false, `id {userId} got {username} and {displayName}`
		end
	end

	return true, nil
end
