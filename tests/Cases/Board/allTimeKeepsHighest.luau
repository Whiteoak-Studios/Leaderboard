--[[
    AllTime keeps a player's highest value: a lower or equal one is refused
    and the update resolves with what is stored, and a higher one is written
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")

local KEY: string = "Highest-AllTime"
local USER: number = 1
local FIRST: number = 50
local LOWER: number = 30
local HIGHER: number = 80
local AMOUNT: number = 100

type Step = { value: number, kept: number }

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local service: any = env.services.DataStoreService
	local board: any = env.require("Board/init").new("AllTime", KEY)

	local steps: { Step } = {
		{ value = FIRST, kept = FIRST },
		{ value = LOWER, kept = FIRST },
		{ value = FIRST, kept = FIRST },
		{ value = HIGHER, kept = HIGHER },
	}

	for _, step: Step in steps do
		local ok: boolean, total: any = env.settle(board:update(USER, Boards.set(step.value)))

		if not ok or total ~= step.kept or service.peekOrdered(KEY, USER) ~= step.kept then
			return false,
				`writing {step.value} resolved {total} and stored {service.peekOrdered(KEY, USER)}, not {step.kept}`
		end
	end

	local ok: boolean, rows: any = env.settle(board:read(AMOUNT))
	if not ok or #rows ~= 1 or rows[1].value ~= HIGHER then
		return false, "AllTime did not read back the highest value"
	end

	return true, nil
end
