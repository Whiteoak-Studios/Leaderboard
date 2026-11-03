--[[
    A failed totals write rejects and writes nothing, on every store, so the
    caller keeps the amount queued and no row runs ahead of its total
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local USER: number = 1
local VALUE: number = 5
local AMOUNT: number = 100

type Entry = { name: string, config: any, key: string }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Failing-Daily", key = "Failing-Daily" },
	{ name = "Wipe", config = { expirySeconds = 3600, key = "Failing-Wipe" }, key = "Failing-Wipe" },
	{ name = "AllTime", config = "Failing-AllTime", key = "Failing-AllTime" },
}

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local env: any = Environment.new()
		local service: any = env.services.DataStoreService
		local board: any = env.require("Board/init").new(entry.name, entry.config)

		env.settle(board:read(AMOUNT))
		service.failNext("UpdateAsync")

		local updated: boolean = env.settle(board:update(USER, Boards.add(VALUE)))

		if updated then
			return false, `{entry.name} resolved an update whose write failed`
		end

		if service.peek(entry.key, USER) ~= nil or service.peekOrdered(entry.key, USER) ~= nil then
			return false, `{entry.name} stored a value from a failed write`
		end

		local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
		if not ok or #rows ~= 0 then
			return false, `{entry.name} showed a row for a failed write`
		end
	end

	return true, nil
end
