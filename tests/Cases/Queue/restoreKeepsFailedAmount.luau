--[[
    A failed write loses nothing: an entry restored with nothing queued for
    its user and board since the take comes back whole at the next take
--]]

--!strict
local Environment = require("../../Environment")

local USER_ID: number = 1
local BOARD: string = "Daily"
local AMOUNT: number = 5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Queue: any = env.require("Queue")
	local queue: any = Queue.new()

	queue:add(USER_ID, BOARD, AMOUNT)
	queue:restore(queue:take()[1])

	local entries: { any } = queue:take()
	local entry: any = entries[1]
	if #entries ~= 1 or entry.userId ~= USER_ID or entry.board ~= BOARD or entry.amount ~= AMOUNT then
		return false, `the next take held {#entries} entries, the first {entry and entry.amount}, not one of {AMOUNT}`
	end

	return true, nil
end
