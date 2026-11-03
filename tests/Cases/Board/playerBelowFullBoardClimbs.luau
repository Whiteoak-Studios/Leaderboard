--[[
    A player below a full board keeps adding to their total across updates
    and two servers, and their row appears once the total passes the cutoff
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local FLOOR: number = 1000 -- The filled rows hold FLOOR + 1 up, so the cutoff is FLOOR + 1
local CLIMBER: number = 9999
local STEP: number = 300
local BELOW: number = 3 -- Updates that leave the climber under the cutoff
local AMOUNT: number = 100

type Entry = { name: string, config: any, key: string, map: string }

local BOARDS: { Entry } = {
	{ name = "Daily", config = "Climb-Daily", key = "Climb-Daily", map = `Climb-Daily:{Start.DAY}` },
	{ name = "Wipe", config = { expirySeconds = 86400, key = "Climb-Wipe" }, key = "Climb-Wipe", map = "Climb-Wipe" },
}

--[[
    Whether the map holds a row for the player
--]]

local function listed(items: { any }, userId: number): boolean
	for _, item: any in items do
		if item.key == `{userId}` then
			return true
		end
	end

	return false
end

return function (): (boolean, string | nil)
	for _, entry: Entry in BOARDS do
		local first: any = Environment.new()
		local second: any = Environment.new({ server = first })
		local keep: number = first.require("Constants").KEPT_ROWS
		local servers: { any } = {
			first.require("Board/init").new(entry.name, entry.config),
			second.require("Board/init").new(entry.name, entry.config),
		}

		first.settle(servers[1]:read(AMOUNT))
		Boards.fill(first, servers[1], keep, FLOOR)

		first.settle(servers[1]:read(AMOUNT))
		second.settle(servers[2]:read(AMOUNT))

		for step: number = 1, BELOW do
			local ok: boolean, total: any = first.settle(servers[step % #servers + 1]:update(CLIMBER, Boards.add(STEP)))

			if not ok or total ~= STEP * step then
				return false, `{entry.name}'s climber reached {total} on update {step}, not {STEP * step}`
			end

			if listed(first.services.MemoryStoreService.peek(entry.map), CLIMBER) then
				return false, `{entry.name} took the climber's row at {total}, under the cutoff {FLOOR + 1}`
			end
		end

		local ok: boolean, total: any =
			first.settle(servers[(BELOW + 1) % #servers + 1]:update(CLIMBER, Boards.add(STEP)))
		if
			not ok
			or total ~= STEP * (BELOW + 1)
			or not listed(first.services.MemoryStoreService.peek(entry.map), CLIMBER)
		then
			return false, `{entry.name} left the climber off at {total}, past the cutoff {FLOOR + 1}`
		end

		local record: any = first.services.DataStoreService.peek(entry.key, CLIMBER)
		if record.total ~= STEP * (BELOW + 1) then
			return false, `{entry.name}'s totals store held {record.total} for the climber`
		end
	end

	return true, nil
end
