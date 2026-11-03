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
local WINDOWS: { string } = Constants.WINDOWS

type Cut = TopRows.Cut
type Kind = Totals.Kind
type Record = Totals.Record
type Row = TopRows.Row
type Totals = Totals.Totals

export type BoardConfig = string | {
	expirySeconds: number,
	key: string,
}

type Fields = {
	_key: string,
	_totals: Totals?, -- Every board's totals and windows but AllTime's, which keeps only highest values
	_cut: Cut?, -- The cutoff this server's last read set, nil until it first reads the board
}

--[[
    Builds a board once its configuration validates. A key string builds
    the period its name gives, or AllTime, and a table builds a rolling
    board whatever its name
--]]

function Board.new(name: string, config: BoardConfig): Self
	Board.validate(name, config)

	local key: string = Board.keyOf(config)
	local totals: Totals? = nil
	if type(config) == "table" then
		totals = Totals.new(key, "Rolling", config.expirySeconds)
	elseif name ~= "AllTime" then
		totals = Totals.new(key, name :: Kind) -- One of WINDOWS, as validate checked
	end

	return setmetatable({
		_key = key,
		_totals = totals,
		_cut = nil :: Cut?,
	}, Board)
end

--[[
    Throws, naming the board, unless its configuration is one the package
    builds: a key string for a period or AllTime, or a rolling board's
    expiry and key, the key at most MAX_KEY_LENGTH characters
--]]

function Board.validate(name: string, config: BoardConfig)
	assert(type(name) == "string", `A board's name is a string, and {name} is a {typeof(name)}`)
	assert(
		type(config) == "string" or type(config) == "table",
		`Board {name} takes a key string or a table of expirySeconds and key, not a {typeof(config)}`
	)

	local bounds: string = `a whole number of seconds from {MIN_ROLLING_EXPIRY} to {MAX_ROLLING_EXPIRY}`

	if type(config) == "table" then
		-- Whole seconds, since each row's expiry is what is left of the window and a map takes whole seconds
		local expirySeconds: any = config.expirySeconds
		assert(
			type(expirySeconds) == "number"
				and expirySeconds % 1 == 0
				and expirySeconds >= MIN_ROLLING_EXPIRY
				and expirySeconds <= MAX_ROLLING_EXPIRY,
			`Board {name}'s expirySeconds is {expirySeconds}, where a rolling board takes {bounds}`
		)
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
