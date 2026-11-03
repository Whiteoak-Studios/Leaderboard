--[[
    The live run's own view of the stores, safe to require in Edit: reads,
    writes and deletes straight to each store, MemoryStore pacing, the
    DataStore budgets, the shutdown report and the sweep
--]]

--!strict
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Checks = require(script.Parent.Checks)
local Jobs = require(script.Parent.Jobs)

local ROLLING_EXPIRY: number = Checks.ROLLING_EXPIRY -- How long a row written straight to a map lives
local UNIT_LIMIT: number = 900 -- MemoryStore request units the run spends in any minute, under the 1,000 before users
local UNIT_WINDOW: number = 60 -- The seconds that budget counts over
local REQUEST_UNITS: number = 1 -- What the smallest map request spends: a size, or one entry's read, write or removal
local PACE_POLL: number = 0.25 -- Seconds between looks at the window while it is full
local RETRIES: number = 3 -- Tries a raw request gets, since Studio's stores fail now and then
local RETRY_WAIT: number = 1 -- Seconds between them
local DELETE_DEADLINE: number = 1800 -- Seconds a deletion runs before it stops and reports what is left
local CLOSE_AMOUNT: number = Checks.CLOSE_AMOUNT

type Entry = Checks.Entry

type Spend = {
	at: number,
	units: number,
}

local Stores = {
	REQUEST_UNITS = REQUEST_UNITS,
	UNIT_LIMIT = UNIT_LIMIT,
}

local Spent: { Spend } = {} -- The units spent within the last UNIT_WINDOW, oldest first

--[[
    The units spent within the window, once what has aged out of it is
    dropped
--]]

local function inWindow(): number
	local cutoff: number = os.clock() - UNIT_WINDOW
	while Spent[1] and Spent[1].at <= cutoff do
		table.remove(Spent, 1)
	end

	local total: number = 0
	for _, spend: Spend in Spent do
		total += spend.units
	end

	return total
end

--[[
    Waits until the window has room for units more, then counts them spent,
    since MemoryStore fails a request past its budget rather than queuing it.
    It waits one window at most, which empties it, so a larger spend then goes
--]]

function Stores.spend(units: number)
	local deadline: number = os.clock() + UNIT_WINDOW
	while inWindow() + units > UNIT_LIMIT and os.clock() < deadline do
		task.wait(PACE_POLL)
	end

	table.insert(Spent, { at = os.clock(), units = units })
end

local function readOne(entry: Entry, _: number?): number | nil
	local options: DataStoreGetOptions = Instance.new("DataStoreGetOptions")
	options.UseCache = false

	if entry.store == "map" then
		Stores.spend(REQUEST_UNITS)
		local value: number? = MemoryStoreService:GetSortedMap(entry.name):GetAsync(entry.key)

		return value
	elseif entry.store == "ordered" then
		local value: number? = DataStoreService:GetOrderedDataStore(entry.name):GetAsync(entry.key, options)

		return value
	end

	local record: { total: number }? = DataStoreService:GetDataStore(entry.name):GetAsync(entry.key, options)

	return record and record.total
end

local function setOne(entry: Entry, value: number?)
	assert(value, `A set takes a value, and {entry.key} on {entry.name} was given none`)

	if entry.store == "map" then
		Stores.spend(REQUEST_UNITS)
		MemoryStoreService:GetSortedMap(entry.name):SetAsync(entry.key, value, ROLLING_EXPIRY, value)
	elseif entry.store == "ordered" then
		DataStoreService:GetOrderedDataStore(entry.name):SetAsync(entry.key, value)
	else
		error(`The run fills no totals store, and {entry.name} is one`)
	end
end

local function deleteOne(entry: Entry, _: number?)
	if entry.store == "map" then
		Stores.spend(REQUEST_UNITS)
		MemoryStoreService:GetSortedMap(entry.name):RemoveAsync(entry.key)
	elseif entry.store == "ordered" then
		DataStoreService:GetOrderedDataStore(entry.name):RemoveAsync(entry.key)
	else
		DataStoreService:GetDataStore(entry.name):RemoveAsync(entry.key)
	end
end

--[[
    Runs one request, tried again RETRY_WAIT later up to RETRIES times, and
    gives whether it ran and its result
--]]

local function attempt(request: (Entry, number?) -> any, entry: Entry, value: number?): (boolean, any)
	local ran: boolean, result: any = false, nil
	for _ = 1, RETRIES do
		ran, result = pcall(request, entry, value)
		if ran then
			break
		end

		task.wait(RETRY_WAIT)
	end

	return ran, result
end

--[[
    An entry's number straight from its store: a totals record's total, a
    row's value or an ordered value
--]]

function Stores.read(entry: Entry): (boolean, any)
	return attempt(readOne, entry, nil)
end

--[[
    Writes a value straight to a map row, with the value as its sort key,
    or to an ordered entry
--]]

function Stores.set(entry: Entry, value: number): (boolean, any)
	return attempt(setOne, entry, value)
end

--[[
    Whether every entry holds the value, nil for none, and what each was
    found holding
--]]

function Stores.holds(entries: { Entry }, expected: number?): (boolean, string)
	local all: boolean = true
	local found: { string } = {}

	for _, entry: Entry in entries do
		local read: boolean, value: any = Stores.read(entry)
		all = all and read and value == expected
		table.insert(found, `{entry.board} {entry.store} of {entry.userId} {value}`)
	end

	return all, table.concat(found, ", ")
end

--[[
    Deletes every entry straight from its store, one at a time, so a
    DataStore request waits in Roblox's queue for budget rather than failing,
    and stops at DELETE_DEADLINE, saying how many it removed
--]]

function Stores.delete(entries: { Entry }): (boolean, string)
	local deadline: number = os.clock() + DELETE_DEADLINE
	local removed: number = 0
	local failures: { string } = {}

	for _, entry: Entry in entries do
		if os.clock() >= deadline then
			break
		end

		local done: boolean, reason: any = attempt(deleteOne, entry, nil)
		if done then
			removed += 1
		else
			table.insert(failures, `{entry.store} {entry.name} {entry.key}: {reason}`)
		end
	end

	local line: string = `removed {removed} of {#entries} entries`
	if #failures > 0 then
		line = `{line}, failing on {#failures}, first {failures[1]}`
	end

	return removed == #entries, line
end

--[[
    Every DataStore request budget this server has now, by request type
--]]

function Stores.budgets(): { [string]: number }
	local budgets: { [string]: number } = {}

	for _, kind: Enum.DataStoreRequestType in Enum.DataStoreRequestType:GetEnumItems() do
		local read: boolean, budget: any =
			pcall(DataStoreService.GetRequestBudgetForRequestType, DataStoreService, kind)
		if read then
			budgets[kind.Name] = budget
		end
	end

	return budgets
end

--[[
    Each budget that moved between two readings, as before to after, sorted
    by name
--]]

function Stores.moved(before: { [string]: number }, after: { [string]: number }): string
	local moves: { string } = {}
	for name: string, budget: number in before do
		if after[name] ~= budget then
			table.insert(moves, `{name} {budget} to {after[name]}`)
		end
	end

	table.sort(moves)

	return #moves > 0 and table.concat(moves, ", ") or "none moved"
end

--[[
    Every DataStore budget the server has now, sorted by name, which sizes
    the save benchmark's players before it runs
--]]

function Stores.budgetReport(): (boolean, string)
	local listed: { string } = {}
	for name: string, budget: number in Stores.budgets() do
		table.insert(listed, `{name} {budget}`)
	end

	table.sort(listed)

	return #listed > 0, `the DataStore budgets now: {table.concat(listed, ", ")}`
end

--[[
    The shutdown check, read in Edit once play has stopped: whether the
    amount the planted Script queued reached the totals, the map and the
    ordered store through the package's own close
--]]

function Stores.closeReport(runId: string): (boolean, string)
	local entries: { Entry } = Checks.entries({ Checks.boards(runId, "close") }, Checks.users("close"))
	local landed: boolean, found: string = Stores.holds(entries, CLOSE_AMOUNT)

	return landed, `the close was to save {CLOSE_AMOUNT}, and the stores hold {found}`
end

--[[
    Deletes everything the live checks and the planted Script wrote under
    the run, with the shutdown fleet's players when players is above 0,
    then clears the Script's attributes
--]]

function Stores.sweep(runId: string, players: number): (boolean, string)
	local removed: boolean, line: string = Stores.delete(Checks.written(runId, players))
	Jobs.clear()

	return removed, `the sweep {line}, and cleared the Script's attributes`
end

return Stores
