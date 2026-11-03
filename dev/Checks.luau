--[[
    The boards and players every live check and benchmark writes under a
    run, Frontier Zero's three objects' boards, and the entries they leave
    in each store, safe to require in Edit
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerPackages = ServerScriptService.ServerPackages

local Board = require(ServerPackages.Leaderboard.Board)
local Constants = require(ServerPackages.Leaderboard.Constants)
local Totals = require(ServerPackages.Leaderboard.Board.Totals)

local ROLLING_EXPIRY: number = 3600 -- Each rolling board's window but the rolling check's, short so a stray row goes
local BASE_USER: number = 2000000000 -- The benchmarks' players count up from it, ten digits as most real ids have
local CLOSE_AMOUNT: number = 7 -- What the shutdown check queues
local CLOSE_FLEET: string = "B3close" -- The label in the keys of the fleet the planted Script queues for the close
local WINDOWS: { string } = Constants.WINDOWS

type BoardConfig = Board.BoardConfig
type Totals = Totals.Totals
type Weekday = Board.Weekday

-- A Weekly or Daily board's reset time UTC, with a weekday only on a Weekly one
type Reset = {
	weekday: Weekday?,
	hour: number,
	minute: number?,
}

type Check = {
	boards: { string }, -- A window's name takes a key or its resets entry, and any other name builds a rolling board
	users: { number },
	expirySeconds: number?, -- The rolling boards' window, ROLLING_EXPIRY when nil
	resets: { [string]: Reset }?, -- The boards that turn at their own reset time, by name
}

type Store = "totals" | "map" | "ordered"

export type Entry = {
	store: Store,
	name: string, -- The DataStore, sorted map or OrderedDataStore
	key: string,
	board: string,
	userId: number,
}

-- Every check's boards and the players it writes, which the sweep deletes; each benchmark deletes its own
local CHECKS: { [string]: Check } = {
	writes = {
		boards = { "Daily", "Weekly", "Wipe", "AllTime" },
		users = { 1001 },
		resets = { Daily = { hour = 14, minute = 30 }, Weekly = { weekday = "Friday", hour = 14 } },
	},
	automation = { boards = { "Daily", "AllTime" }, users = { 1002 } },
	rolling = { boards = { "Wipe" }, users = { 1003 }, expirySeconds = Constants.MIN_ROLLING_EXPIRY },
	delete = { boards = { "Daily", "AllTime" }, users = { 1004 } },
	twoServers = { boards = { "Wipe", "AllTime" }, users = { 1005 } },
	names = { boards = { "Wipe" }, users = { 1, 156 } },
	close = { boards = { "Wipe", "AllTime" }, users = { 1006 } },
	queue = { boards = { "Daily" }, users = { 1007 } },
	trims = { boards = { "Trim" }, users = {} },
}

-- Frontier Zero's 13 boards for one fleet, as its three objects hold them, each to the slot that names its store.
-- Built shared, boards on the same slot in different objects share one store, so a fill writes each slot once
local FLEET: { { [string]: string } } = {
	{ AllTime = "A", Daily = "D", Weekly = "W", KillsWipe = "R1", DeathsWipe = "R2" },
	{ AllTime = "A", Daily = "D", Weekly = "W", PlayTimeWipe = "R1" },
	{ AllTime = "A", ResourcesWipe = "R1", RaidDamageWipe = "R2", BaseValueWipe = "R3" },
}

local Checks = {
	CLOSE_AMOUNT = CLOSE_AMOUNT,
	ROLLING_EXPIRY = ROLLING_EXPIRY,
}

--[[
    A board's configuration under a key: its key and reset time when it has
    one, the key itself for a window, or a rolling board's expiry and key
--]]

local function configOf(name: string, key: string, expirySeconds: number, reset: Reset?): BoardConfig
	if reset then
		return { key = key, weekday = reset.weekday, hour = reset.hour, minute = reset.minute }
	end

	if table.find(WINDOWS, name) then
		return key
	end

	return { expirySeconds = expirySeconds, key = key }
end

--[[
    The boards one check builds, each keyed by the run, the check and its
    name
--]]

function Checks.boards(runId: string, check: string): { [string]: BoardConfig }
	local plan: Check = CHECKS[check]
	local resets: { [string]: Reset } = plan.resets or {}
	local boards: { [string]: BoardConfig } = {}

	for _, name: string in plan.boards do
		boards[name] = configOf(name, `{runId}-{check}-{name}`, plan.expirySeconds or ROLLING_EXPIRY, resets[name])
	end

	return boards
end

function Checks.users(check: string): { number }
	return CHECKS[check].users
end

--[[
    Frontier Zero's three objects' boards under the run and a label, the
    boards on one slot sharing its store when shared
--]]

function Checks.fleet(runId: string, label: string, shared: boolean): { { [string]: BoardConfig } }
	local objects: { { [string]: BoardConfig } } = {}

	for index: number, slots: { [string]: string } in FLEET do
		local boards: { [string]: BoardConfig } = {}
		for name: string, slot: string in slots do
			local key: string = shared and `{runId}-{label}-{slot}` or `{runId}-{label}-{index}{slot}`
			boards[name] = configOf(name, key, ROLLING_EXPIRY)
		end

		table.insert(objects, boards)
	end

	return objects
end

--[[
    The fleet the planted Script queues for the server's close, each
    object's boards on stores of their own
--]]

function Checks.closeFleet(runId: string): { { [string]: BoardConfig } }
	local shared: boolean = false

	return Checks.fleet(runId, CLOSE_FLEET, shared)
end

--[[
    The first count of the benchmarks' players
--]]

function Checks.span(count: number): { number }
	local users: { number } = {}
	for index: number = 1, count do
		table.insert(users, BASE_USER + index)
	end

	return users
end

--[[
    The boards whose rows live in a map, as the targets of a read that sets
    their cutoffs
--]]

function Checks.maps(boards: { [string]: BoardConfig }): { [string]: boolean }
	local targets: { [string]: boolean } = {}
	for name: string, config: BoardConfig in boards do
		if type(config) == "table" or name ~= "AllTime" then
			targets[name] = true
		end
	end

	return targets
end

--[[
    The sorted map holding a board's rows now, named as the package names it
--]]

function Checks.mapName(board: string, config: BoardConfig): string
	-- Callers pass only boards with a map, which every board but AllTime's key string has
	local totals: Totals = Board.totalsOf(board, config) :: Totals

	return totals:map(totals:opens(os.time()))
end

--[[
    Everything the players can hold on the boards, once each: an AllTime
    board's ordered entry, and any other board's totals key and map row
--]]

function Checks.entries(objects: { { [string]: BoardConfig } }, users: { number }): { Entry }
	local seen: { [string]: boolean } = {}
	local entries: { Entry } = {}

	local function add(store: Store, name: string, board: string)
		for _, userId: number in users do
			local id: string = `{store} {name} {userId}`
			if not seen[id] then
				seen[id] = true
				table.insert(entries, { store = store, name = name, key = `{userId}`, board = board, userId = userId })
			end
		end
	end

	for _, boards: { [string]: BoardConfig } in objects do
		for board: string, config: BoardConfig in boards do
			if type(config) == "string" and board == "AllTime" then
				add("ordered", config, board)
			else
				add("totals", Board.keyOf(config), board)
				add("map", Checks.mapName(board, config), board)
			end
		end
	end

	return entries
end

--[[
    Every entry the live checks and the planted Script can write under the
    run, and the close fleet's for that many players when players is above 0
--]]

function Checks.written(runId: string, players: number): { Entry }
	local entries: { Entry } = {}

	for check: string, plan: Check in CHECKS do
		for _, entry: Entry in Checks.entries({ Checks.boards(runId, check) }, plan.users) do
			table.insert(entries, entry)
		end
	end

	if players > 0 then
		for _, entry: Entry in Checks.entries(Checks.closeFleet(runId), Checks.span(players)) do
			table.insert(entries, entry)
		end
	end

	return entries
end

return Checks
