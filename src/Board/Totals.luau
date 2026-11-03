--[[
    A board's per-player totals in the DataStore its key names, each beside
    the window it counts: a UTC period, or a rolling window from the first write
--]]

--!strict
local Totals = {}
Totals.__index = Totals

local DataStoreService = game:GetService("DataStoreService")

local Promise: any = require(script.Parent.Parent.Parent.Promise)

local Constants = require(script.Parent.Parent.Constants)

local MONTHS_PER_YEAR: number = Constants.MONTHS_PER_YEAR

type Period = {
	length: number,
	start: number,
}

-- Each fixed period's length in seconds, and when its period 0 starts unless a board gives its own: the epoch, or
-- the first Sunday for weeks
local PERIODS: { [string]: Period } = {
	Hourly = { length = Constants.HOUR_SECONDS, start = 0 },
	Daily = { length = Constants.DAY_SECONDS, start = 0 },
	Weekly = { length = Constants.WEEK_SECONDS, start = Constants.WEEK_START },
}

export type Kind = "Hourly" | "Daily" | "Weekly" | "Monthly" | "Rolling"

export type Record = {
	total: number,
	window: number, -- The period number on a periodic board, and the first write's time on a rolling one
}

type Date = {
	year: number,
	month: number,
}

type Fields = {
	_key: string,
	_kind: Kind,
	_expirySeconds: number, -- A rolling window's length, unused by a period
	_start: number, -- When a fixed period's period 0 starts, unused by Monthly and Rolling
}

--[[
    Builds a board's totals. A fixed period's period 0 starts at the given
    start, or at the kind's own when none is given
--]]

function Totals.new(key: string, kind: Kind, expirySeconds: number?, start: number?): Self
	local period: Period? = PERIODS[kind]

	return setmetatable({
		_key = key,
		_kind = kind,
		_expirySeconds = expirySeconds or 0,
		_start = start or period and period.start or 0,
	}, Totals)
end

--[[
    Runs the transform on the player's total in the current window, or on 0
    once the stored total's window has ended. UpdateAsync may run it more
    than once, and the promise resolves with the record that landed
--]]

function Totals.update(self: Self, userId: number, transform: (old: number) -> number): any
	local now: number = os.time()
	local opened: number = self:opens(now)

	return Promise.try(function (): Record
		local store: DataStore = DataStoreService:GetDataStore(self._key)
		local record: Record = store:UpdateAsync(`{userId}`, function (stored: Record?): Record
			if stored and self:ends(stored.window) > now then
				return { total = transform(stored.total), window = stored.window }
			end

			return { total = transform(0), window = opened }
		end)

		return record
	end)
end

function Totals.delete(self: Self, userId: number): any
	return Promise.try(function ()
		DataStoreService:GetDataStore(self._key):RemoveAsync(`{userId}`)
	end)
end

--[[
    The window a write at the given time counts in: the number of the UTC
    period it falls in, or the time itself on a rolling board
--]]

function Totals.opens(self: Self, now: number): number
	local period: Period? = PERIODS[self._kind]
	if period then
		return (now - self._start) // period.length
	end

	if self._kind == "Monthly" then
		-- "!*t" gives the time's UTC date as a table, and stays a literal, since the new checker cannot pick
		-- os.date's table form from a typed local
		local date: Date = os.date("!*t", now)

		return date.year * MONTHS_PER_YEAR + date.month - 1
	end

	return now
end

--[[
    When a window ends: as the period after it starts, or once the rolling
    expiry has passed since its first write
--]]

function Totals.ends(self: Self, window: number): number
	local period: Period? = PERIODS[self._kind]
	if period then
		return self._start + (window + 1) * period.length
	end

	if self._kind == "Monthly" then
		-- December rolls into the next year's January by hand, since there is no month 13
		local following: number = window + 1
		local year: number = following // MONTHS_PER_YEAR
		local month: number = following % MONTHS_PER_YEAR + 1

		return DateTime.fromUniversalTime(year, month, 1).UnixTimestamp
	end

	return window + self._expirySeconds
end

--[[
    The sorted map holding a window's top rows: one per period, named with
    its number, or a rolling board's one map
--]]

function Totals.map(self: Self, window: number): string
	if self._kind == "Rolling" then
		return self._key
	end

	return `{self._key}:{window}`
end

export type Totals = Self
type Self = typeof(setmetatable({} :: Fields, Totals))

return Totals
