--[[
    A failed batch caches nothing and the other batches still cache, and the
    next request asks for the failed batch's ids again and fills them
--]]

--!strict
local Environment = require("../../Environment")

local IDS: number = 250 -- Two batches, so one can fail beside one that answers

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.UserService
	local Names: any = env.require("Names")

	local userIds: { number } = {}
	for userId: number = 1, IDS do
		service.set(userId, `user{userId}`, `User {userId}`)
		table.insert(userIds, userId)
	end

	--[[
	    Counts the ids get gives no name for, and fails the case on a wrong
	    name
	--]]

	local function missing(): number
		local count: number = 0
		for _, userId: number in userIds do
			local username: string?, displayName: string? = Names:get(userId)

			if username == nil and displayName == nil then
				count += 1
			else
				assert(username == `user{userId}` and displayName == `User {userId}`, `id {userId} got {username}`)
			end
		end

		return count
	end

	service.failNext("GetUserInfosByUserIdsAsync")
	Names:request(userIds)
	env.clock.advance(0)

	local afterFailure: number = missing()
	if afterFailure == 0 or afterFailure == IDS then
		return false, `{afterFailure} of {IDS} ids had no name after one batch failed`
	end

	Names:request(userIds)
	env.clock.advance(0)

	local afterRetry: number = missing()
	if afterRetry ~= 0 then
		return false, `{afterRetry} ids still had no name after the next request`
	end

	return true, nil
end
