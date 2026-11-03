--[[
    The reads, merged onto a Leaderboard: each board's highest rows ranked
    and named, and the automation's loop that reads every interval and saves
--]]

--!strict
local Read = {}

local Promise: any = require(script.Parent.Parent.Promise)

local Constants = require(script.Parent.Constants)
local Names = require(script.Parent.Names)
local TopRows = require(script.Parent.Board.TopRows)
local Types = require(script.Parent.Config.Types.Leaderboard)

local READS_PER_SAVE: number = Constants.READS_PER_SAVE

type BoardResult = Types.BoardResult
type Leaderboard = Types.Leaderboard
type Row = Types.Row
type Stored = TopRows.Row -- A row as a board reads it, before its rank and names

--[[
    Reads each named board, then ranks and names the rows of those that read
    and sends the ids without a name to one lookup. Resolves with the results
    in the order of names and the failed boards' reasons, and never rejects
--]]

function Read._read(self: Leaderboard, names: { string }, amounts: { [string]: number }): any
	local found: { [string]: { Stored } } = {}
	local failures: { string } = {}
	local reads: { any } = {}

	for _, name: string in names do
		local read: any = self._boards[name]:read(amounts[name]):andThen(function (rows: { Stored })
			found[name] = rows
		end, function (reason: any)
			table.insert(failures, `Leaderboard could not read board {name}: {reason}`)
		end)

		table.insert(reads, read)
	end

	return Promise.allSettled(reads):andThen(function (): ({ BoardResult }, { string })
		local results: { BoardResult } = {}
		local unnamed: { number } = {}

		for _, name: string in names do
			local rows: { Stored }? = found[name]
			if not rows then
				continue
			end

			local ranked: { Row } = {}
			for rank: number, row: Stored in rows do
				local username: string?, displayName: string? = Names:get(row.userId)
				if username == nil then
					table.insert(unnamed, row.userId)
				end

				table.insert(ranked, {
					rank = rank,
					userId = row.userId,
					value = row.value,
					username = username,
					displayName = displayName,
				})
			end

			table.insert(results, { board = name, rows = ranked })
		end

		Names:request(unnamed)

		return results, failures
	end)
end

--[[
    One automated tick: reads every board and fires the signals with those
    that read, warning for those that failed, and saves when asked. Neither
    failure can reach the loop, which only starts the work
--]]

function Read._tick(self: Leaderboard, saving: boolean)
	self:_read(self._names, self._recordCount):andThen(function (results: { BoardResult }, failures: { string })
		for _, failure: string in failures do
			warn(`{failure}, so this tick leaves it out`)
		end

		if #results == 0 then
			return
		end

		self.updated:Fire(results)
		for _, result: BoardResult in results do
			self.boardUpdated:Fire(result)
		end
	end)

	if saving then
		self:_track(self:_write()):catch(function (reason: any)
			warn(`Leaderboard's automated save failed, and the next one tries again: {reason}`)
		end)
	end
end

--[[
    The automation's loop, the object's own thread until destroy cancels it:
    a read now and one every interval, the first after it and every
    READS_PER_SAVE-th after that saving too
--]]

function Read._run(self: Leaderboard, interval: number)
	local ticks: number = 0
	self:_tick(false)

	while task.wait(interval) do
		ticks += 1
		self:_tick((ticks - 1) % READS_PER_SAVE == 0)
	end
end

return Read
