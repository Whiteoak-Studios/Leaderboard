--[[
    An amount queued while a save is in flight survives that save's failed
    write: the restored entry adds to it, so the next take holds both
--]]

--!strict
local Environment = require("../../Environment")

local USER_ID: number = 1
local BOARD: string = "Daily"
local TAKEN: number = 5
local NEWER: number = 7

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Queue: any = env.require("Queue")
	local queue: any = Queue.new()

	queue:add(USER_ID, BOARD, TAKEN)
	local taken: { any } = queue:take()

	queue:add(USER_ID, BOARD, NEWER)
	queue:restore(taken[1])

	local entries: { any } = queue:take()
	local entry: any = entries[1]
	if #entries ~= 1 or entry.userId ~= USER_ID or entry.board ~= BOARD or entry.amount ~= TAKEN + NEWER then
		return false,
			`the next take held {#entries} entries, the first {entry and entry.amount}, not one of {TAKEN + NEWER}`
	end

	return true, nil
end
