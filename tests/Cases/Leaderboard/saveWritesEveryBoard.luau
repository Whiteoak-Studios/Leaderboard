--[[
    After save on an object of every kind of board, each board reads back
    the amount queued for it, from "All" and from a dictionary alike
--]]

--!strict
local Environment = require("../../Environment")

local USER: number = 1
local TO_ALL: number = 3
local TO_SOME: number = 2

local BOARDS: { [string]: any } = {
	AllTime = "Every-AllTime",
	Daily = "Every-Daily",
	Weekly = "Every-Weekly",
	Wipe = { expirySeconds = 86400, key = "Every-Wipe" },
}

local EXPECTED: { [string]: number } = {
	AllTime = TO_ALL,
	Daily = TO_ALL + TO_SOME,
	Weekly = TO_ALL,
	Wipe = TO_ALL + TO_SOME,
}

return function (): (boolean, string | nil)
	local env: any = Environment.new()
	local Leaderboard: any = env.require("init")
	local object: any = Leaderboard.new(BOARDS)

	-- The boards' first read, after which a save writes their rows
	env.settle(object:getAll("All"))

	object:increment("All", USER, TO_ALL)
	object:increment({ Daily = true, Wipe = true }, USER, TO_SOME)

	local saved: boolean, reason: any = env.settle(object:save())
	if not saved then
		return false, `the save rejected: {reason}`
	end

	local read: boolean, results: any = env.settle(object:getAll("All"))
	if not read or #results ~= 4 then
		return false, `the read after the save gave {read and #results} boards: {results}`
	end

	for _, result: any in results do
		local row: any = result.rows[1]
		if not row or row.userId ~= USER or row.value ~= EXPECTED[result.board] then
			return false, `{result.board} read back {row and row.value}, not {EXPECTED[result.board]}`
		end
	end

	return true, nil
end
