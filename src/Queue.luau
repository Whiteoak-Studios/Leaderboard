--[[
    The amounts waiting to be saved, one per user and board, which a save
    takes out as its writes start and puts back when a write fails
--]]

--!strict
local Queue = {}
Queue.__index = Queue

export type Entry = {
	userId: number,
	board: string,
	amount: number,
}

type Fields = {
	_amounts: { [number]: { [string]: number } }, -- Each user's queued amount per board
}

function Queue.new(): Self
	return setmetatable({
		_amounts = {} :: { [number]: { [string]: number } },
	}, Queue)
end

--[[
    Adds an amount to whatever is already queued for that user and board
--]]

function Queue.add(self: Self, userId: number, board: string, amount: number)
	local boards: { [string]: number } = self._amounts[userId] or {}
	boards[board] = (boards[board] or 0) + amount
	self._amounts[userId] = boards
end

--[[
    Empties the queue and returns one entry per user and board, so an
    amount added from here on waits for the next take
--]]

function Queue.take(self: Self): { Entry }
	local entries: { Entry } = {}
	for userId: number, boards: { [string]: number } in self._amounts do
		for board: string, amount: number in boards do
			table.insert(entries, { userId = userId, board = board, amount = amount })
		end
	end

	self._amounts = {}

	return entries
end

--[[
    Puts a taken entry back, added to whatever has been queued for its
    user and board since the take, so a failed write loses nothing
--]]

function Queue.restore(self: Self, entry: Entry)
	self:add(entry.userId, entry.board, entry.amount)
end

--[[
    Deletes the amount queued for one user and board, and the user with it
    once they have nothing else queued
--]]

function Queue.delete(self: Self, userId: number, board: string)
	local boards: { [string]: number }? = self._amounts[userId]
	if not boards then
		return
	end

	boards[board] = nil

	if next(boards) == nil then
		self._amounts[userId] = nil
	end
end

export type Queue = Self
type Self = typeof(setmetatable({} :: Fields, Queue))

return Queue
