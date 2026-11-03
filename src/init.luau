--[[
    The Leaderboard object a game builds: up to seven boards over the stores,
    the queue its saves write, its reads and automation, and the one shutdown
    that saves every object before the server closes
--]]

--!strict
local Leaderboard = {}
Leaderboard.__index = Leaderboard

local Promise: any = require(script.Parent.Promise)
local Signal = require(script.Parent.Signal)

local Board = require(script.Board)
local Constants = require(script.Constants)
local Queue = require(script.Queue)
local Read = require(script.Read)
local Types = require(script.Config.Types.Leaderboard)
local Validate = require(script.Validate)
local Write = require(script.Write)

local MAX_OBJECTS: number = Constants.MAX_OBJECTS
local MAX_BOARDS: number = Constants.MAX_BOARDS

--- @class Leaderboard
--- Time-windowed global leaderboards on the server. An object holds up to
--- seven boards, queues increments in memory, saves them to the stores and
--- reads each board's highest rows, by hand or on its automation

--- @type BoardConfig string | { expirySeconds: number, key: string } | { key: string, weekday: Weekday, hour: number?, minute: number? } | { key: string, hour: number, minute: number? }
--- @within Leaderboard
--- A board's storage. A key string builds the window a board named Hourly,
--- Daily, Weekly, Monthly or AllTime keeps, a week from Sunday 00:00 UTC
--- and a day from 00:00, and a table of `expirySeconds` and `key` builds a
--- rolling board of any name, its window `expirySeconds` from each player's
--- first write. Weekly also takes `{ key, weekday, hour?, minute? }` and Daily
--- `{ key, hour, minute? }`, turning at that time UTC. A weekday is "Sunday"
--- to "Saturday", an hour 0 to 23 and a minute 0 to 59, whole, 0 if left out

export type BoardConfig = Board.BoardConfig
export type Automation = Types.Automation
export type BoardResult = Types.BoardResult
export type Leaderboard = Types.Leaderboard
export type Row = Types.Row

type Board = Board.Board
type Fields = Types.Fields
type Range = Types.Range
type Self = Types.Leaderboard
type Targets = Types.Targets

local Live: { [Self]: true } = {} -- Every object built and not yet destroyed, which BindToClose destroys
local InFlight: { [any]: Self } = {} -- A promise settling with each save, set and delete in flight, to its object

--- Builds an object over its boards and, given an automation that is on,
--- starts its loop, whose first read runs at once. Throws on no boards, more
--- than 7, a board's configuration `Board` refuses, two boards sharing a
--- key, an automation it cannot run, or a fourth live object, and an object
--- that throws holds no slot
--- @function new
--- @within Leaderboard
--- @param boards { [string]: BoardConfig } -- Each board's name to its storage
--- @param automation Automation? -- How the object reads and saves on its own, or nil for neither
--- @return Leaderboard

function Leaderboard.new(boards: { [string]: BoardConfig }, automation: Automation?): Self
	local live: number = 0
	for _ in Live do
		live += 1
	end

	if live >= MAX_OBJECTS then
		error(`Leaderboard.new found {MAX_OBJECTS} live objects, the most a server holds; destroy one first`, 0)
	end

	local given: unknown = boards
	if type(given) ~= "table" then
		error(`Leaderboard.new takes its boards as a dictionary by name, not a {typeof(given)}`, 0)
	end

	local names: { string } = {}
	for name: string in boards do
		table.insert(names, name)
	end

	if #names == 0 or #names > MAX_BOARDS then
		error(`Leaderboard.new takes 1 to {MAX_BOARDS} boards, not {#names}`, 0)
	end

	Board.validateAll(boards)
	table.sort(names)

	-- settings stays any, since neither checker reads a field off a value refined only to a table
	local settings: any = automation
	local automated: boolean = false
	local recordCount: unknown = nil

	if settings ~= nil then
		if type(settings) ~= "table" then
			error(`Leaderboard.new takes its automation as a table, not a {typeof(settings)}`, 0)
		end

		if type(settings.automation) ~= "boolean" then
			error(`Leaderboard.new's automation.automation is a boolean, not {settings.automation}`, 0)
		end

		local interval: unknown = settings.interval
		if settings.automation and not (type(interval) == "number" and interval > 0 and interval < math.huge) then
			error(`Leaderboard.new's automation.interval is a positive number of seconds, not {interval}`, 0)
		end

		automated = settings.automation
		recordCount = settings.recordCount
	end

	local amounts: { [string]: number } =
		Validate.amounts(names, "Leaderboard.new's automation.recordCount", recordCount)

	local built: { [string]: Board } = {}
	for name: string, config: BoardConfig in boards do
		built[name] = Board.new(name, config)
	end

	local fields: Fields = {
		updated = Signal.new() :: Signal.Signal<{ BoardResult }>,
		boardUpdated = Signal.new() :: Signal.Signal<BoardResult>,
		_boards = built,
		_names = names,
		_recordCount = amounts,
		_queue = Queue.new(),
		_thread = nil :: thread?,
		_destroyed = false,
	}

	local object: Self = setmetatable(fields, Leaderboard) :: any
	if automated then
		object._thread = task.spawn(object._run, object, settings.interval)
	end

	Live[object] = true

	return object
end

--- Adds an amount to each named board's queue for the player, for the
--- next save to write. It never yields and touches no store, so it is safe
--- thousands of times a frame, and it throws on a board the object does not
--- hold or a bad number, queuing nothing
--- @method increment
--- @within Leaderboard
--- @param boards "All" | { [string]: true } -- Every board, or a dictionary holding true for each board it targets
--- @param userId number -- A whole number; a negative one passes, as Studio's test players have
--- @param amount number -- A whole, non-negative number

function Leaderboard.increment(self: Self, boards: Targets, userId: number, amount: number)
	self:_checkLive("increment")

	local names: { string } = Validate.targets("increment", self._names, boards)
	Validate.userId("increment", userId)
	Validate.count("increment", "an amount", amount)

	for _, name: string in names do
		self._queue:add(userId, name, amount)
	end
end

--- Writes the value straight to each named board, as a number or as a
--- function given the player's stored value. An `AllTime` board keeps the
--- higher value. A bad number throws at the call, and a function whose
--- return breaks the same rule rejects that board's write. A row whose
--- write fails once the value has landed waits for the next save
--- @method set
--- @within Leaderboard
--- @param boards "All" | { [string]: true } -- Every board, or a dictionary holding true for each board it targets
--- @param userId number -- A whole number; a negative one passes, as Studio's test players have
--- @param value number | (old: number) -> number -- A whole, non-negative number, or a function returning one
--- @return Promise<()> -- Resolves once every write has landed, and rejects once all settle if one failed

function Leaderboard.set(self: Self, boards: Targets, userId: number, value: number | (old: number) -> number): any
	self:_checkLive("set")

	local names: { string } = Validate.targets("set", self._names, boards)
	Validate.userId("set", userId)

	local transform: (old: number) -> number
	if type(value) == "function" then
		local given: (old: number) -> number = value

		-- Runs inside each store's UpdateAsync, so a bad return fails that write rather than the call
		transform = function (old: number): number
			local returned: number = given(old)
			Validate.count("set", "a value", returned)

			return returned
		end
	else
		local fixed: number = value
		Validate.count("set", "a value", fixed)

		transform = function (): number
			return fixed
		end
	end

	local writes: { any } = {}
	for _, name: string in names do
		-- A value that landed with its row missed queues 0, so the next save writes the row
		local write: any = self._boards[name]:update(userId, transform):andThen(function (_: number, missed: boolean?)
			if missed then
				self._queue:add(userId, name, 0)
			end
		end)
		table.insert(writes, write)
	end

	return self:_track(self:_settleAll(writes, `set {userId}'s value`))
end

--- Writes everything queued to the stores, taking the queue as its writes
--- start, with at most 30 board writes in flight across every object's
--- saves on the server. A write that fails puts its amount back in the
--- queue, and an amount queued while the save runs waits for the next one
--- @method save
--- @within Leaderboard
--- @return Promise<()> -- Resolves once every write has landed, and rejects once all settle if one failed

function Leaderboard.save(self: Self): any
	self:_checkLive("save")

	return self:_track(self:_write())
end

--- Reads each named board's highest rows, highest first, with each row's
--- names from the cache, nil for a user it does not hold yet. It never
--- waits on a name: the ids it lacks go to one background lookup, and a
--- later read has them
--- @method getAll
--- @within Leaderboard
--- @param boards "All" | { [string]: true } -- Every board, or a dictionary holding true for each board it targets
--- @param range (number | { [string]: number })? -- Rows from 1 to 100, for every board or by name; 100 by default
--- @return Promise<{ BoardResult }> -- In the order of the boards' names, rejecting if any board's read fails

function Leaderboard.getAll(self: Self, boards: Targets, range: Range?): any
	self:_checkLive("getAll")
	local names: { string } = Validate.targets("getAll", self._names, boards)
	local amounts: { [string]: number } = Validate.amounts(self._names, "Leaderboard:getAll's range", range)

	return self:_read(names, amounts):andThen(function (results: { BoardResult }, failures: { string }): any
		if #failures > 0 then
			return Promise.reject(table.concat(failures, "; "))
		end

		return results
	end)
end

--- Takes a player off each named board: waits for this object's writes in
--- flight to settle, then deletes the player's queued amount and their
--- stored entries, so no failed write's amount can bring them back
--- @method delete
--- @within Leaderboard
--- @param boards "All" | { [string]: true } -- Every board, or a dictionary holding true for each board it targets
--- @param userId number -- A whole number
--- @return Promise<()> -- Resolves once every removal has landed, and rejects once all settle if one failed

function Leaderboard.delete(self: Self, boards: Targets, userId: number): any
	self:_checkLive("delete")
	local names: { string } = Validate.targets("delete", self._names, boards)
	Validate.userId("delete", userId)

	local function deleteQueued()
		for _, name: string in names do
			self._queue:delete(userId, name)
		end
	end

	-- Deleted now, so a save starting while the delete waits cannot take the amount, and again once the
	-- writes in flight settle, since a failed one puts its amount back
	deleteQueued()

	local work: any = Promise.allSettled(self:_pending()):andThen(function (): any
		deleteQueued()

		local removals: { any } = {}
		for _, name: string in names do
			local removal: any = self._boards[name]:delete(userId)
			table.insert(removals, removal)
		end

		return self:_settleAll(removals, `delete {userId}`)
	end)

	return self:_track(work)
end

--- Ends the object: cancels its automation at once, disconnects every
--- subscriber of its signals and frees its slot, then makes a last save once
--- its writes in flight have settled. Every method called afterwards throws
--- @method destroy
--- @within Leaderboard
--- @return Promise<()> -- The last save's

function Leaderboard.destroy(self: Self): any
	self:_checkLive("destroy")

	self._destroyed = true
	Live[self] = nil

	if self._thread then
		task.cancel(self._thread)
	end

	self.updated:DisconnectAll()
	self.boardUpdated:DisconnectAll()

	-- The last save waits out the writes in flight, so an amount a failed one puts back goes with it
	local work: any = Promise.allSettled(self:_pending()):andThen(function (): any
		return self:_write()
	end)

	return self:_track(work)
end

--[[
    Throws, naming the call, once the object has been destroyed
--]]

function Leaderboard._checkLive(self: Self, method: string)
	if self._destroyed then
		error(`Leaderboard:{method} was called on a destroyed object`, 0)
	end
end

--[[
    Holds a write in flight until it settles, so a delete, a last save and
    the shutdown can wait on it, and hands the caller a promise of its own,
    since canceling the one the write runs on would close it mid-write
--]]

function Leaderboard._track(self: Self, work: any): any
	-- What InFlight holds never rejects, since allSettled warns of every rejected promise it is handed, even
	-- one another handler has caught
	local done: any = work:catch(function () end)
	InFlight[done] = self

	done:finally(function ()
		InFlight[done] = nil
	end)

	return Promise.new(function (resolve: any, reject: any)
		work:andThen(resolve, reject)
	end)
end

--[[
    Every save, set and delete this object still has in flight
--]]

function Leaderboard._pending(self: Self): { any }
	local works: { any } = {}
	for work: any, owner: Self in InFlight do
		if owner == self then
			table.insert(works, work)
		end
	end

	return works
end

-- The server's close destroys every live object and returns once every write in flight has settled
game:BindToClose(function ()
	for object: Self in Live do
		object:destroy():catch(function (reason: any)
			warn(`Leaderboard's last save at shutdown failed: {reason}`)
		end)
	end

	local works: { any } = {}
	for work: any in InFlight do
		table.insert(works, work)
	end

	Promise.allSettled(works):await()
end)

local _: Types.Own, _: Types.Write, _: Types.Read = Leaderboard, Write, Read

-- The saves and the reads are a sibling each, merged onto the class, and a name defined twice is a bug
local parts: { any } = { Write, Read }

for _, part: any in parts do
	for name: string, method: any in part do
		assert(Leaderboard[name] == nil, `Leaderboard.{name} is defined twice`)
		Leaderboard[name] = method
	end
end

return Leaderboard
