--[[
    A board's top rows in one MemoryStore sorted map per window: the read
    that sets the cutoff and trims past the slack, and the rows' writes
--]]

--!strict
local MemoryStoreService = game:GetService("MemoryStoreService")

local Promise: any = require(script.Parent.Parent.Parent.Promise)

local Constants = require(script.Parent.Parent.Constants)

local KEPT_ROWS: number = Constants.KEPT_ROWS
local MAX_RANGE_READ: number = Constants.MAX_RANGE_READ

export type Row = {
	userId: number,
	value: number,
}

export type Cut = {
	map: string, -- The map the read that set it read
	full: boolean, -- Whether that read kept KEPT_ROWS rows
	cutoff: number, -- The lowest total it kept
	kept: { [number]: boolean }, -- The user ids it kept
}

local TopRows = {}

--[[
    Reads a map's highest rows, keeps the top KEPT_ROWS as the board's cutoff
    and deletes the rest. Resolves with at most the amount of rows asked and
    the cutoff once every trim has settled, and a failed trim only warns
--]]

function TopRows.read(map: string, amount: number): any
	return Promise.try(function (): { any }
		return MemoryStoreService:GetSortedMap(map):GetRangeAsync(Enum.SortDirection.Descending, MAX_RANGE_READ)
	end):andThen(function (items: { any }): any
		local cut: Cut = { map = map, full = #items >= KEPT_ROWS, cutoff = 0, kept = {} }
		local rows: { Row } = {}
		local trims: { any } = {}

		for rank: number, item: any in items do
			local userId: number = tonumber(item.key) :: number

			if rank > KEPT_ROWS then
				local trim: any = TopRows.delete(map, userId):catch(function (reason: any)
					warn(`Leaderboard could not trim {userId} from {map}, so the next read tries again: {reason}`)
				end)

				table.insert(trims, trim)
			else
				cut.kept[userId] = true
				cut.cutoff = item.value

				if rank <= amount then
					table.insert(rows, { userId = userId, value = item.value })
				end
			end
		end

		return Promise.all(trims):andThenReturn(rows, cut)
	end)
end

--[[
    Whether a total belongs on the board: once this server has read it,
    while the window's map is not full, past its cutoff, or for a player
    that read kept
--]]

local function belongs(cut: Cut?, map: string, userId: number, total: number): boolean
	if not cut then
		return false
	end

	return cut.map ~= map or not cut.full or total > cut.cutoff or cut.kept[userId] == true
end

--[[
    Writes a player's row when their total belongs on the board, with the
    total as its value and sort key and the time left in its window as its
    expiry. Always resolves, with whether the row missed: a failed write
    only warns, and the object's next save writes the row again
--]]

function TopRows.write(cut: Cut?, map: string, userId: number, total: number, ends: number): any
	-- A window that has ended takes no row, and a map refuses an expiry that is not positive
	local remaining: number = ends - os.time()
	if remaining <= 0 or not belongs(cut, map, userId, total) then
		return Promise.resolve(false)
	end

	return Promise.try(function ()
		MemoryStoreService:GetSortedMap(map):UpdateAsync(`{userId}`, function (): (number, number)
			return total, total
		end, remaining)
	end)
		:andThenReturn(false)
		:catch(function (reason: any): boolean
			warn(`Leaderboard could not write {userId}'s row to {map}, so the next save writes it again: {reason}`)

			return true
		end)
end

function TopRows.delete(map: string, userId: number): any
	return Promise.try(function ()
		MemoryStoreService:GetSortedMap(map):RemoveAsync(`{userId}`)
	end)
end

return TopRows
