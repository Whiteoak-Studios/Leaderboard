--[[
    One board, a window over one stat: AllTime's highest values in an
    ordered store, or a period's or rolling window's top rows over totals
--]]

--!strict
local Board = {}
Board.__index = Board

local Constants = require(script.Parent.Constants)
local Ordered = require(script.Ordered)
local TopRows = require(script.TopRows)
local Totals = require(script.Totals)

local MAX_KEY_LENGTH: number = Constants.MAX_KEY_LENGTH
local MIN_ROLLING_EXPIRY: number = Constants.MIN_ROLLING_EXPIRY
local MAX_ROLLING_EXPIRY: number = Constants.MAX_ROLLING_EXPIRY
local MINUTE_SECONDS: number = Constants.MINUTE_SECONDS
local HOUR_SECONDS: number = Constants.HOUR_SECONDS
local DAY_SECONDS: number = Constants.DAY_SECONDS
local WEEK_START: number = Constants.WEEK_START
local MAX_HOUR: number = Constants.MAX_HOUR
local MAX_MINUTE: number = Constants.MAX_MINUTE
local WINDOWS: { string } = Constants.WINDOWS
local WEEKDAYS: { string } = Constants.WEEKDAYS

type Cut = TopRows.Cut
type Kind = Totals.Kind
type Record = Totals.Record
type Row = TopRows.Row
type Totals = Totals.Totals

export type Weekday = "Sunday" | "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday"

export type BoardConfig = string | {
	expirySeconds: number,
	key: string,
} | {
	key: string,
	weekday: Weekday,
	hour: number?, -- UTC, 0 when nil
	minute: number?, -- 0 when nil
} | {
	key: string,
	hour: number, -- UTC
	minute: number?, -- 0 when nil
}

-- Every table shape read as one, each field nil where its shape has none, since the checker reads no field
-- that one member of a union lacks
type TableConfig = {
	key: string,
	expirySeconds: number?,
	weekday: Weekday?,
	hour: number?,
	minute: number?,
}

type Fields = {
	_key: string,
	_totals: Totals?, -- Every board's totals and windows but AllTime's, which keeps only highest values
	_cut: Cut?, -- The cutoff this server's last read set, nil until it first reads the board
}

--[[
    Builds a board once its configuration validates. A key string builds
    the period its name gives, or AllTime, a table of expirySeconds builds
    a rolling board whatever its name, and a table of weekday or hour builds
    a Weekly or Daily board that turns at that weekday, hour and minute UTC
--]]

function Board.new(name: string, config: BoardConfig): Self
	Board.validate(name, config)

	return setmetatable({
		_key = Board.keyOf(config),
		_totals = Board.totalsOf(name, config),
		_cut = nil :: Cut?,
	}, Board)
end

--[[
    Whether a value a game passed is a whole number from lowest to highest
--]]

local function whole(value: unknown, lowest: number, highest: number): boolean
	return type(value) == "number" and value % 1 == 0 and value >= lowest and value <= highest
end

--[[
    Throws, naming the board, unless its configuration is one the package
    builds: a key string for a period or AllTime, a rolling board's expiry
    and key, a Weekly board's key and weekday with an hour and minute it
    may leave out, or a Daily board's key and hour with a minute it may
    leave out, the key at most MAX_KEY_LENGTH characters
--]]

function Board.validate(name: string, config: BoardConfig)
	assert(type(name) == "string", `A board's name is a string, and {name} is a {typeof(name)}`)

	local shapes: string = "a key string, a table of expirySeconds and key, or a table of key and reset time"
	assert(type(config) == "string" or type(config) == "table", `Board {name} takes {shapes}, not a {typeof(config)}`)

	local bounds: string = `a whole number of seconds from {MIN_ROLLING_EXPIRY} to {MAX_ROLLING_EXPIRY}`

	if type(config) == "table" then
		local given: TableConfig = config :: TableConfig
		local expirySeconds: any = given.expirySeconds
		local weekday: any = given.weekday
		local hour: any = given.hour
		local minute: any = given.minute
		local reset: boolean = weekday ~= nil or hour ~= nil or minute ~= nil
		local scheduled: boolean = name == "Weekly" or name == "Daily"

		assert(
			expirySeconds == nil or not reset,
			`Board {name} holds expirySeconds beside weekday, hour or minute, but a rolling board has no reset time`
		)

		if expirySeconds ~= nil or not (reset or scheduled) then
			-- Whole seconds, since each row's expiry is what is left of the window and a map takes whole seconds
			assert(
				whole(expirySeconds, MIN_ROLLING_EXPIRY, MAX_ROLLING_EXPIRY),
				`Board {name}'s expirySeconds is {expirySeconds}, where a rolling board takes {bounds}`
			)
		else
			local days: string = table.concat(WEEKDAYS, ", ")
			local otherwise: string = "or expirySeconds and key for a rolling board"

			assert(
				weekday == nil or name == "Weekly",
				`Board {name} takes a weekday only when named Weekly, since only a week turns on one`
			)
			assert(scheduled, `Board {name} takes an hour or minute only when named Weekly or Daily`)
			assert(name ~= "Weekly" or weekday ~= nil, `Board Weekly's table takes a key and weekday, {otherwise}`)
			assert(name ~= "Daily" or hour ~= nil, `Board Daily's table takes a key and hour, {otherwise}`)
			assert(
				weekday == nil or table.find(WEEKDAYS, weekday),
				`Board {name}'s weekday is {weekday}, where a weekday is one of {days}`
			)
			assert(
				hour == nil or whole(hour, 0, MAX_HOUR),
				`Board {name}'s hour is {hour}, where an hour is whole, from 0 to {MAX_HOUR}, or nil for 0`
			)
			assert(
				minute == nil or whole(minute, 0, MAX_MINUTE),
				`Board {name}'s minute is {minute}, where a minute is whole, from 0 to {MAX_MINUTE}, or nil for 0`
			)
		end
	else
		local windows: string = table.concat(WINDOWS, ", ")
		local rolling: string = `a table of expirySeconds and key builds a rolling board, taking {bounds}`
		local limit: string = "a MemoryStore entry lives at most 45 days"
		assert(
			name ~= "Yearly",
			`Board Yearly cannot be built, since {limit}. A key string builds {windows}, and {rolling}`
		)
		assert(
			table.find(WINDOWS, name),
			`Board {name} takes a key string only when named {windows}, and otherwise {rolling}`
		)
	end

	local key: any = Board.keyOf(config)
	assert(
		type(key) == "string" and #key > 0 and #key <= MAX_KEY_LENGTH,
		`Board {name}'s key is {key}, where a key is a string of 1 to {MAX_KEY_LENGTH} characters`
	)
end

--[[
    Validates every board of an object, and throws when two share a key,
    since a key names each of its board's stores
--]]

function Board.validateAll(boards: { [string]: BoardConfig })
	local owners: { [string]: string } = {}

	for name: string, config: BoardConfig in boards do
		Board.validate(name, config)

		local key: string = Board.keyOf(config)
		local owner: string? = owners[key]
		assert(owner == nil, `Boards {owner} and {name} share the key {key}, where each board needs its own`)

		owners[key] = name
	end
end

--[[
    The key a board's configuration names its stores with
--]]

function Board.keyOf(config: BoardConfig): string
	if type(config) == "table" then
		return config.key
	end

	return config
end

--[[
    The totals a configuration validate passed builds, without a board:
    none for AllTime, a rolling window's, a period's from the kind's own
    start, or a Weekly or Daily table's from its reset time
--]]

function Board.totalsOf(name: string, config: BoardConfig): Totals?
	if type(config) == "string" then
		if name == "AllTime" then
			return nil
		end

		return Totals.new(config, name :: Kind) -- One of WINDOWS, as validate checked
	end

	local given: TableConfig = config :: TableConfig
	if given.expirySeconds then
		return Totals.new(given.key, "Rolling", given.expirySeconds)
	end

	local hour: number = given.hour or 0
	local minute: number = given.minute or 0
	local sinceMidnight: number = hour * HOUR_SECONDS + minute * MINUTE_SECONDS

	-- Day 0 starts on the epoch's day at the reset time
	if name == "Daily" then
		return Totals.new(given.key, "Daily", nil, sinceMidnight)
	end

	-- A weekday validate found, whose index less one is its days after Sunday
	local days: number = (table.find(WEEKDAYS, given.weekday :: Weekday) :: number) - 1

	return Totals.new(given.key, "Weekly", nil, WEEK_START + days * DAY_SECONDS + sinceMidnight)
end

--[[
    Adds to a player's total through the transform, which is given their
    total in the current window and may run more than once. Resolves with
    the new total once it has landed and its row has been tried, and beside
    it whether the row missed, which AllTime's never does. Rejects when the
    total fails to land
--]]

function Board.update(self: Self, userId: number, transform: (old: number) -> number): any
	local totals: Totals? = self._totals
	if not totals then
		return Ordered.update(self._key, userId, transform)
	end

	return totals:update(userId, transform):andThen(function (record: Record): any
		local map: string = totals:map(record.window)
		local ends: number = totals:ends(record.window)

		return TopRows.write(self._cut, map, userId, record.total, ends)
			:andThen(function (missed: boolean): (number, boolean)
				return record.total, missed
			end)
	end)
end

--[[
    Reads the board's highest rows, highest first and at most the amount
    asked. A read also sets the cutoff the board's writes check and trims
    its map, and resolves once its trims have settled
--]]

function Board.read(self: Self, amount: number): any
	local totals: Totals? = self._totals
	if not totals then
		return Ordered.read(self._key, amount)
	end

	local map: string = totals:map(totals:opens(os.time()))

	return TopRows.read(map, amount):andThen(function (rows: { Row }, cut: Cut): { Row }
		self._cut = cut

		return rows
	end)
end

--[[
    Deletes the player's total and then their row in the current window,
    or their AllTime entry, and rejects if either deletion fails
--]]

function Board.delete(self: Self, userId: number): any
	local totals: Totals? = self._totals
	if not totals then
		return Ordered.delete(self._key, userId)
	end

	local map: string = totals:map(totals:opens(os.time()))

	return totals:delete(userId):andThen(function (): any
		return TopRows.delete(map, userId)
	end)
end

export type Board = Self
type Self = typeof(setmetatable({} :: Fields, Board))

return Board
