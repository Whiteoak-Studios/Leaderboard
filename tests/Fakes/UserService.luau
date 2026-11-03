--[[
    A fake UserService whose batched lookup answers only the ids a case gave
    a name, leaving the rest out as the real one does, and takes at most 200
--]]

--!strict
local Faults = require("./Faults")

local MAX_IDS: number = 200 -- Ids one GetUserInfosByUserIdsAsync takes
local METHODS: { string } = { "GetUserInfosByUserIdsAsync" }

export type Names = { [number]: { username: string, displayName: string } }

export type UserInfo = {
	Id: number,
	Username: string,
	DisplayName: string,
}

export type UserService = {
	GetUserInfosByUserIdsAsync: (self: any, userIds: { number }) -> { UserInfo },
	failNext: (method: string, count: number?) -> (),
	delayNext: (method: string, seconds: number) -> (),
	set: (userId: number, username: string, displayName: string) -> (),
}

local UserService = {}

--[[
    Builds a UserService over names two servers can share
--]]

function UserService.new(names: Names, sleep: (seconds: number?) -> number): UserService
	local faults: Faults.Faults = Faults.new("UserService", METHODS, sleep)

	return {
		failNext = faults.failNext,
		delayNext = faults.delayNext,

		GetUserInfosByUserIdsAsync = function (_: any, userIds: { number }): { UserInfo }
			if #userIds > MAX_IDS then
				error(`GetUserInfosByUserIdsAsync takes at most {MAX_IDS} ids, not {#userIds}`, 0)
			end

			faults.spend("GetUserInfosByUserIdsAsync")

			local infos: { UserInfo } = {}
			for _, userId: number in userIds do
				local name: { username: string, displayName: string }? = names[userId]
				if name then
					table.insert(infos, { Id = userId, Username = name.username, DisplayName = name.displayName })
				end
			end

			return infos
		end,

		set = function (userId: number, username: string, displayName: string)
			names[userId] = { username = username, displayName = displayName }
		end,
	}
end

return UserService
