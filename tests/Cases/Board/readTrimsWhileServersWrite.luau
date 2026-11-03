--[[
    After a read, a board's map holds at most its rows plus the slack while
    several servers write, and the rows it keeps are the highest
--]]

--!strict
local Boards = require("../../Boards")
local Environment = require("../../Environment")
local Start = require("../../Start")

local KEY: string = "Trim-Daily"
local MAP: string = `{KEY}:{Start.DAY}`
local EACH: number = 60 -- Players each server writes before the first trim
local LATE: number = 40 -- Low players written after it
local AMOUNT: number = 100

return function (): (boolean, string | nil)
	local first: any = Environment.new()
	local keep: number = first.require("Constants").KEPT_ROWS
	local environments: { any } = { first, Environment.new({ server = first }), Environment.new({ server = first }) }
	local boards: { any } = {}

	for index: number, env: any in environments do
		boards[index] = env.require("Board/init").new("Daily", KEY)
		env.settle(boards[index]:read(AMOUNT))
	end

	-- Every server read the board empty, so each writes its players' rows
	for index: number, board: any in boards do
		for offset: number = 1, EACH do
			local userId: number = (index - 1) * EACH + offset
			first.settle(board:update(userId, Boards.set(userId)))
		end
	end

	local written: number = #first.services.MemoryStoreService.peek(MAP)
	if written ~= #boards * EACH then
		return false, `the servers wrote {written} rows, not {#boards * EACH}`
	end

	local ok: boolean, rows: any = first.settle(boards[1]:read(AMOUNT))
	local kept: { any } = first.services.MemoryStoreService.peek(MAP)
	if not ok or #kept ~= keep or kept[keep].value ~= #boards * EACH - keep + 1 then
		return false, `the first trim left {#kept} rows, the lowest at {kept[#kept] and kept[#kept].value}`
	end

	if #rows ~= AMOUNT or rows[1].value ~= #boards * EACH then
		return false, `the trimming read returned {#rows} rows, the highest at {rows[1] and rows[1].value}`
	end

	-- The other servers still count the board as not full, and the first refuses low rows past its cutoff
	for index: number, board: any in boards do
		for offset: number = 1, LATE do
			local userId: number = #boards * EACH + (index - 1) * LATE + offset
			first.settle(board:update(userId, Boards.set(offset)))
		end
	end

	local crowded: number = #first.services.MemoryStoreService.peek(MAP)
	if crowded ~= keep + (#boards - 1) * LATE then
		return false, `the map held {crowded} rows after the late writes, not {keep + (#boards - 1) * LATE}`
	end

	first.settle(boards[2]:read(AMOUNT))
	local trimmed: { any } = first.services.MemoryStoreService.peek(MAP)
	if #trimmed ~= keep or trimmed[keep].value ~= #boards * EACH - keep + 1 then
		return false,
			`the second trim left {#trimmed} rows, the lowest at {trimmed[#trimmed] and trimmed[#trimmed].value}`
	end

	return true, nil
end
