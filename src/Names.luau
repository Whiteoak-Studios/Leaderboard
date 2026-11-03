--[[
    The username and display name of every user the package has looked up,
    and the background lookups that ask UserService for the rest in batches
--]]

--!strict
local UserService = game:GetService("UserService")

local MAX_NAME_BATCH: number = require(script.Parent.Constants).MAX_NAME_BATCH

type UserInfo = {
	Id: number,
	Username: string,
	DisplayName: string,
}

local Names = {
	-- Whiteoak TODO: an entry never expires, so a user renamed after their lookup keeps the old name until the
	-- server closes; give each entry an age and ask again past it if that matters
	_names = {} :: { [number]: UserInfo }, -- One entry per user a lookup answered
	_inFlight = {} :: { [number]: true }, -- The ids a lookup is asking for right now
}

--[[
    Gives the username and display name the cache holds for a user, or two
    nils when no lookup has answered for them yet. Never yields
--]]

function Names.get(self: Self, userId: number): (string | nil, string | nil)
	local info: UserInfo? = self._names[userId]

	return info and info.Username, info and info.DisplayName
end

--[[
    Starts one background lookup for the ids the cache holds no name for
    and no lookup is asking for, and returns at once
--]]

function Names.request(self: Self, userIds: { number })
	local wanted: { number } = {}
	for _, userId: number in userIds do
		if not self._names[userId] and not self._inFlight[userId] then
			self._inFlight[userId] = true
			table.insert(wanted, userId)
		end
	end

	if #wanted == 0 then
		return
	end

	task.spawn(self._lookup, self, wanted)
end

--[[
    Asks for the ids a batch at a time and caches what comes back. A failed
    batch caches nothing, and an id left unanswered stays nil, so a later
    request asks for either again
--]]

function Names._lookup(self: Self, userIds: { number })
	for first: number = 1, #userIds, MAX_NAME_BATCH do
		local batch: { number } = table.move(userIds, first, math.min(first + MAX_NAME_BATCH - 1, #userIds), 1, {})

		-- An error here would kill the thread, so the call is caught and the batch warned about
		local success: boolean, result: any = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, batch)
		if success then
			for _, info: UserInfo in result do
				self._names[info.Id] = info
			end
		else
			warn(`Leaderboard could not look up {#batch} names, and a later read asks again: {result}`)
		end

		for _, userId: number in batch do
			self._inFlight[userId] = nil
		end
	end
end

type Self = typeof(Names)

return Names
