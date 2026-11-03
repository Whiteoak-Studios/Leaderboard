--[[
    The Leaderboard object's types: the shapes a game passes and reads, and
    its instance type, its fields and the methods each of its files defines,
    one part per file
--]]

--!strict
local Signal = require(script.Parent.Parent.Parent.Parent.Signal)

local Board = require(script.Parent.Parent.Parent.Board)
local Queue = require(script.Parent.Parent.Parent.Queue)

type Board = Board.Board
type Queue = Queue.Queue

export type Targets = "All" | { [string]: boolean }
export type Range = number | { [string]: number }

--- @interface Automation
--- @within Leaderboard
--- .automation boolean -- Whether the object reads and saves on its own
--- .interval number -- Seconds between reads, required when automation is true
--- .recordCount (number | { [string]: number })? -- The rows each read takes, as getAll's range
--- How an object reads and saves on its own: a read as it is built and one
--- every interval after, every second one also saving

export type Automation = {
	automation: boolean,
	interval: number,
	recordCount: Range?,
}

--- @interface Row
--- @within Leaderboard
--- .rank number -- 1 for the board's highest value
--- .userId number
--- .value number
--- .username string? -- Nil until the name lookup answers for this user
--- .displayName string? -- Nil until the name lookup answers for this user
--- One player's place on a board

export type Row = {
	rank: number,
	userId: number,
	value: number,
	username: string?,
	displayName: string?,
}

--- @interface BoardResult
--- @within Leaderboard
--- .board string -- The board's name, as the game gave it
--- .rows { Row } -- Highest first, at most 100
--- One board's read

export type BoardResult = {
	board: string,
	rows: { Row },
}

--- @prop updated Signal<{ BoardResult }>
--- @within Leaderboard
--- Fires after each automated read with the result of every board that
--- read, in the order of the boards' names. A board whose read failed is
--- left out, and a read where every board failed fires nothing

--- @prop boardUpdated Signal<BoardResult>
--- @within Leaderboard
--- Fires after each automated read once for each board that read

export type Fields = {
	updated: Signal.Signal<{ BoardResult }>,
	boardUpdated: Signal.Signal<BoardResult>,
	_boards: { [string]: Board }, -- Each board by its name
	_names: { string }, -- The boards' names, sorted, the order every result comes in
	_recordCount: { [string]: number }, -- The rows each automated read takes from each board
	_queue: Queue,
	_thread: thread?, -- The automation's loop, nil without one
	_destroyed: boolean,
}

export type Own = {
	increment: (self: Leaderboard, boards: Targets, userId: number, amount: number) -> (),
	set: (self: Leaderboard, boards: Targets, userId: number, value: number | (old: number) -> number) -> any,
	save: (self: Leaderboard) -> any,
	getAll: (self: Leaderboard, boards: Targets, range: Range?) -> any,
	delete: (self: Leaderboard, boards: Targets, userId: number) -> any,
	destroy: (self: Leaderboard) -> any,
	_checkLive: (self: Leaderboard, method: string) -> (),
	_track: (self: Leaderboard, work: any) -> any,
	_pending: (self: Leaderboard) -> { any },
}

export type Write = {
	_write: (self: Leaderboard) -> any,
	_settleAll: (self: Leaderboard, promises: { any }, action: string) -> any,
}

export type Read = {
	_read: (self: Leaderboard, names: { string }, amounts: { [string]: number }) -> any,
	_tick: (self: Leaderboard, saving: boolean) -> (),
	_run: (self: Leaderboard, interval: number) -> (),
}

export type Leaderboard = Fields & Own & Write & Read

return {}
