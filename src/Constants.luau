--[[
    The constants Leaderboard's own correctness needs: the Roblox limits its
    stores hold it to, its bounds on objects, boards and rows, its windows
    and how often its automation saves
--]]

--!strict
local MAX_OBJECTS: number = 3 -- The live Leaderboard objects one server holds
local MAX_BOARDS: number = 7 -- The boards one object holds
local MAX_ROWS: number = 100 -- The rows a board shows and a read returns, at most
local SLACK_ROWS: number = 20 -- The rows a board's map keeps past MAX_ROWS
local KEPT_ROWS: number = MAX_ROWS + SLACK_ROWS -- The rows a read leaves in a board's map, the board's and the slack
local MAX_RANGE_READ: number = 200 -- The most items one GetRangeAsync returns
local MIN_ROLLING_EXPIRY: number = 60 -- A rolling board's shortest expiry, in seconds
local MAX_ROLLING_EXPIRY: number = 3888000 -- A rolling board's longest expiry, the 45 days a map entry lives
local MAX_KEY_LENGTH: number = 50 -- The longest board key, the most characters a DataStore name holds
local MAX_IN_FLIGHT: number = 30 -- The most board writes a server's saves keep in flight, its request queue's length
local READS_PER_SAVE: number = 2 -- The automated reads to each automated save, the first save one interval in
local MAX_NAME_BATCH: number = 200 -- The most ids one GetUserInfosByUserIdsAsync takes
local HOUR_SECONDS: number = 3600 -- The seconds in an Hourly board's period
local DAY_SECONDS: number = 86400 -- The seconds in a Daily board's period
local WEEK_SECONDS: number = 604800 -- The seconds in a Weekly board's period
local WEEK_START: number = 259200 -- When week 0 starts, Sunday 1970-01-04 00:00 UTC
local MONTHS_PER_YEAR: number = 12 -- A Monthly board's period number is year * MONTHS_PER_YEAR + month - 1

local WINDOWS: { string } = { "Hourly", "Daily", "Weekly", "Monthly", "AllTime" } -- The names a key string builds

return {
	MAX_OBJECTS = MAX_OBJECTS,
	MAX_BOARDS = MAX_BOARDS,
	MAX_ROWS = MAX_ROWS,
	SLACK_ROWS = SLACK_ROWS,
	KEPT_ROWS = KEPT_ROWS,
	MAX_RANGE_READ = MAX_RANGE_READ,
	MIN_ROLLING_EXPIRY = MIN_ROLLING_EXPIRY,
	MAX_ROLLING_EXPIRY = MAX_ROLLING_EXPIRY,
	MAX_KEY_LENGTH = MAX_KEY_LENGTH,
	MAX_IN_FLIGHT = MAX_IN_FLIGHT,
	READS_PER_SAVE = READS_PER_SAVE,
	MAX_NAME_BATCH = MAX_NAME_BATCH,
	HOUR_SECONDS = HOUR_SECONDS,
	DAY_SECONDS = DAY_SECONDS,
	WEEK_SECONDS = WEEK_SECONDS,
	WEEK_START = WEEK_START,
	MONTHS_PER_YEAR = MONTHS_PER_YEAR,
	WINDOWS = WINDOWS,
}
