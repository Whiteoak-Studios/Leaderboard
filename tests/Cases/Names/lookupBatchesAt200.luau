--[[
    A request for 450 ids goes out in three calls, none over the 200 ids one
    GetUserInfosByUserIdsAsync takes, and every id gets its name
--]]

--!strict
local Calls = require("../../Calls")
local Environment = require("../../Environment")

local IDS: number = 450
local MOST: number = 200
local BATCHES: number = 3

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.UserService
	local Names: any = env.require("Names")

	local userIds: { number } = {}
	for userId: number = 1, IDS do
		service.set(userId, `user{userId}`, `User {userId}`)
		table.insert(userIds, userId)
	end

	local calls: { { any } } = Calls(service, "GetUserInfosByUserIdsAsync")
	Names:request(userIds)
	env.clock.advance(0)

	if #calls ~= BATCHES then
		return false, `{IDS} ids went out in {#calls} calls`
	end

	for _, call: { any } in calls do
		local batch: { number } = call[2]
		if #batch > MOST then
			return false, `a call asked for {#batch} ids`
		end
	end

	for _, userId: number in userIds do
		local username: string?, displayName: string? = Names:get(userId)
		if username ~= `user{userId}` or displayName ~= `User {userId}` then
			return false, `id {userId} got {username} and {displayName}`
		end
	end

	return true, nil
end
