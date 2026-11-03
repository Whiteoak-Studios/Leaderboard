--[[
    Boards given as an array, a plain name, an empty dictionary or a name
    holding anything but true throw at every method that takes them, and
    nothing is queued or written
--]]

--!strict
local Environment = require("../../Environment")

local KEY: string = "Shapes-Daily"
local USER: number = 1
local AMOUNT: number = 5

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new({ Daily = KEY })

	local shapes: { [string]: any } = {
		array = { "Daily" },
		name = "Daily",
		empty = {},
		holdsFalse = { Daily = false },
		holdsNumber = { Daily = 1 },
	}

	for shape: string, boards: any in shapes do
		local calls: { [string]: () -> () } = {
			increment = function ()
				object:increment(boards, USER, AMOUNT)
			end,

			set = function ()
				object:set(boards, USER, AMOUNT)
			end,

			getAll = function ()
				object:getAll(boards)
			end,

			delete = function ()
				object:delete(boards, USER)
			end,
		}

		for method: string, call: () -> () in calls do
			local ran: boolean = pcall(call)
			if ran then
				return false, `{method} took boards given as {shape}`
			end
		end
	end

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	local record: any = env.services.DataStoreService.peek(KEY, USER)
	if record ~= nil then
		return false, `a refused call queued or wrote {record.total}`
	end

	return true, nil
end
