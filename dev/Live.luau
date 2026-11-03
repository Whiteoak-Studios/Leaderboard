--[[
    The live checks for the play server only, each proving one behavior on
    the real stores: it builds its objects on a fresh copy of the package and
    says whether it passed and what it wrote and read back
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerPackages = ServerScriptService.ServerPackages

local Leaderboard = require(ServerPackages.Leaderboard)

local Checks = require(script.Parent.Checks)
local Jobs = require(script.Parent.Jobs)
local Stores = require(script.Parent.Stores)

local AWAIT_DEADLINE: number = 60 -- Seconds a check waits on any one call to the package
local VALUE: number = 123456789 -- What the writes check sets, wide enough that any rounding would show
local AMOUNT: number = 7 -- What the other checks add or set
local SECOND_AMOUNT: number = 5 -- What the second copy adds on top in the two-servers check
local INTERVAL: number = 5 -- The automation check's interval, so a read, a save and a read take 10 seconds
local CYCLE_DEADLINE: number = 45 -- Seconds the automation check waits for a tick to show its save
local EXPIRY_GRACE: number = 5 -- Seconds past a rolling window's end before its row must be gone
local READ_POLL: number = 1 -- Seconds between reads while a check waits on the stores
local SETTLE_READS: number = 10 -- Reads a check makes waiting for a write to show
local NAME_READS: number = 15 -- Reads the names check makes waiting on UserService
local WRITTEN_AT: string = "RollingWrittenAt" -- The attribute holding when the rolling check wrote
local SHORTEST_EXPIRY: number = require(ServerPackages.Leaderboard.Constants).MIN_ROLLING_EXPIRY

type Package = typeof(Leaderboard)
type Object = Leaderboard.Leaderboard
type BoardResult = Leaderboard.BoardResult
type BoardConfig = Leaderboard.BoardConfig
type Row = Leaderboard.Row
type Entry = Checks.Entry

local Live = {}

local function await(promise: any): any
	return Jobs.await(promise, AWAIT_DEADLINE)
end

local function finish(objects: { Object }, body: () -> (boolean, string)): (boolean, string)
	return Jobs.finish(objects, AWAIT_DEADLINE, body)
end

local function rowOf(results: { BoardResult }, board: string, userId: number): Row | nil
	for _, result: BoardResult in results do
		if result.board == board then
			for _, row: Row in result.rows do
				if row.userId == userId then
					return row
				end
			end
		end
	end

	return nil
end

--[[
    Asks look every READ_POLL, SETTLE_READS times at most, until it holds,
    since a read right after a write can miss the write, and gives its last
    answer
--]]

local function settle(look: () -> (boolean, string)): (boolean, string)
	local held: boolean, found: string = look()
	for _ = 2, SETTLE_READS do
		if held then
			break
		end

		task.wait(READ_POLL)
		held, found = look()
	end

	return held, found
end

--[[
    A write through each store reads back exact: one value set on a
    periodic board, a rolling board and AllTime, read through the package
    and straight from the totals, the maps and the ordered store
--]]

function Live.writes(runId: string): (boolean, string)
	local Package: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "writes")
	local userId: number = Checks.users("writes")[1]
	local object: Object = Package.new(boards)

	return finish({ object }, function (): (boolean, string)
		await(object:getAll(Checks.maps(boards))) -- Sets each map's cutoff, so the set writes the rows
		await(object:set("All", userId, VALUE))

		local exact: boolean, read: string = settle(function (): (boolean, string)
			local results: { BoardResult } = await(object:getAll("All"))
			local all: boolean = true
			local values: { string } = {}

			for name: string in boards do
				local row: Row? = rowOf(results, name, userId)
				all = all and row ~= nil and row.value == VALUE
				table.insert(values, `{name} {row and row.value}`)
			end

			return all, table.concat(values, ", ")
		end)

		local entries: { Entry } = Checks.entries({ boards }, { userId })
		local stored: boolean, found: string = settle(function (): (boolean, string)
			return Stores.holds(entries, VALUE)
		end)

		return exact and stored, `set {VALUE} for {userId}; getAll read {read}; the stores hold {found}`
	end)
end

--[[
    One full automation cycle: a read as the object is built, a read and a
    save one interval later, and a read after that whose updated and
    boardUpdated carry the queued amount from a map and from AllTime
--]]

function Live.automation(runId: string): (boolean, string)
	local Package: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "automation")
	local userId: number = Checks.users("automation")[1]
	local object: Object = Package.new(boards, { automation = true, interval = INTERVAL })

	return finish({ object }, function (): (boolean, string)
		local started: number = os.clock()
		local ticks: number = 0
		local cycle: number? = nil -- Seconds in when a tick first showed the amount on every board
		local fired: { [string]: boolean } = {} -- Each board whose boardUpdated carried the amount

		-- Both connections are the object's, and its destroy disconnects them
		object.updated:Connect(function (results: { BoardResult })
			ticks += 1

			local every: boolean = true
			for name: string in boards do
				local row: Row? = rowOf(results, name, userId)
				every = every and row ~= nil and row.value == AMOUNT
			end

			if every and not cycle then
				cycle = os.clock() - started
			end
		end)

		object.boardUpdated:Connect(function (result: BoardResult)
			local row: Row? = rowOf({ result }, result.board, userId)
			if row and row.value == AMOUNT then
				fired[result.board] = true
			end
		end)

		object:increment("All", userId, AMOUNT)

		local function done(): boolean
			for name: string in boards do
				if not fired[name] then
					return false
				end
			end

			return cycle ~= nil
		end

		local deadline: number = started + CYCLE_DEADLINE
		while not done() and os.clock() < deadline do
			task.wait(READ_POLL)
		end

		local named: { string } = {}
		for name: string in fired do
			table.insert(named, name)
		end

		table.sort(named)

		local seen: string = cycle and `{string.format("%.1f", cycle)} s in` or `never, in {CYCLE_DEADLINE} s`
		local signals: string = `boardUpdated carried it for {#named > 0 and table.concat(named, ", ") or "no board"}`

		return done(),
			`{ticks} updated fired at {INTERVAL} s; {AMOUNT} for {userId} showed on every board {seen}; {signals}`
	end)
end

--[[
    The rolling check's first half: a row on a 60-second rolling board,
    written now and read back, with the time it was written kept on the
    Script for rollingCheck
--]]

function Live.rollingWrite(runId: string): (boolean, string)
	local Package: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "rolling")
	local userId: number = Checks.users("rolling")[1]
	local object: Object = Package.new(boards)

	return finish({ object }, function (): (boolean, string)
		await(object:getAll("All"))

		local writtenAt: number = os.time()
		await(object:set("All", userId, AMOUNT))
		Jobs.holder:SetAttribute(WRITTEN_AT, writtenAt)

		local entries: { Entry } = Checks.entries({ boards }, { userId })
		local shown: boolean, found: string = settle(function (): (boolean, string)
			return Stores.holds(entries, AMOUNT)
		end)

		local due: number = writtenAt + SHORTEST_EXPIRY + EXPIRY_GRACE
		local window: string = `a {SHORTEST_EXPIRY} s rolling board at {writtenAt}`

		return shown, `set {AMOUNT} for {userId} on {window}, and the stores hold {found}; rollingCheck from {due}`
	end)
end

--[[
    The rolling check's second half: once the window and a grace have
    passed since rollingWrite, waiting out what is left, the board reads no
    row and its map holds none, with no reset call made
--]]

function Live.rollingCheck(runId: string): (boolean, string)
	local writtenAt: any = Jobs.holder:GetAttribute(WRITTEN_AT)
	if type(writtenAt) ~= "number" then
		return false, `rollingWrite has not run on this server, so there is no window to check`
	end

	local due: number = writtenAt + SHORTEST_EXPIRY + EXPIRY_GRACE
	task.wait(math.max(0, due - os.time()))

	local Package: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "rolling")
	local userId: number = Checks.users("rolling")[1]
	local object: Object = Package.new(boards)

	return finish({ object }, function (): (boolean, string)
		local results: { BoardResult } = await(object:getAll("All"))
		local row: Row? = nil
		for name: string in boards do
			row = row or rowOf(results, name, userId)
		end

		local rows: { Entry } = {}
		for _, entry: Entry in Checks.entries({ boards }, { userId }) do
			if entry.store == "map" then
				table.insert(rows, entry)
			end
		end

		local gone: boolean, found: string = Stores.holds(rows, nil)
		local read: string = row and `a row of {row.value}` or "no row"

		return row == nil and gone, `{os.time() - writtenAt} s after the write, getAll read {read} and {found}`
	end)
end

--[[
    The delete removes the player's entry from each store: the totals key
    and the map row of a periodic board, and the AllTime entry, read
    straight from the stores before and after it
--]]

function Live.delete(runId: string): (boolean, string)
	local Package: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "delete")
	local userId: number = Checks.users("delete")[1]
	local object: Object = Package.new(boards)

	return finish({ object }, function (): (boolean, string)
		await(object:getAll(Checks.maps(boards)))
		await(object:set("All", userId, AMOUNT))

		local entries: { Entry } = Checks.entries({ boards }, { userId })
		local stored: boolean, before: string = settle(function (): (boolean, string)
			return Stores.holds(entries, AMOUNT)
		end)

		await(object:delete("All", userId))

		local gone: boolean, after: string = settle(function (): (boolean, string)
			return Stores.holds(entries, nil)
		end)

		return stored and gone, `before the delete the stores held {before}; after it {after}`
	end)
end

--[[
    A total saved by one server is added to by a save on another: two
    copies of the package, standing in for two servers, each read and then
    save an amount for the same player on a rolling board and AllTime
--]]

function Live.twoServers(runId: string): (boolean, string)
	local first: Package = Jobs.copy()
	local second: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "twoServers")
	local userId: number = Checks.users("twoServers")[1]
	local one: Object = first.new(boards)
	local two: Object = second.new(boards)

	return finish({ one, two }, function (): (boolean, string)
		await(one:getAll(Checks.maps(boards)))
		one:increment("All", userId, AMOUNT)
		await(one:save())

		await(two:getAll(Checks.maps(boards)))
		two:increment("All", userId, SECOND_AMOUNT)
		await(two:save())

		local entries: { Entry } = Checks.entries({ boards }, { userId })
		local stored: boolean, found: string = settle(function (): (boolean, string)
			return Stores.holds(entries, AMOUNT + SECOND_AMOUNT)
		end)

		return stored, `one copy saved {AMOUNT} and a second added {SECOND_AMOUNT}; the stores hold {found}`
	end)
end

--[[
    Real names arrive at a later read: two real players' rows, read first
    with no names on a copy whose cache is empty, then read until the
    lookup through UserService has named both
--]]

function Live.names(runId: string): (boolean, string)
	local Package: Package = Jobs.copy()
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "names")
	local users: { number } = Checks.users("names")
	local object: Object = Package.new(boards)

	return finish({ object }, function (): (boolean, string)
		await(object:getAll("All"))
		for rank: number, userId: number in users do
			await(object:set("All", userId, AMOUNT * rank))
		end

		--[[
		    Whether every player has a row, and whether every row is named,
		    with what each row showed
		--]]

		local function look(): (boolean, boolean, string)
			local results: { BoardResult } = await(object:getAll("All"))
			local rows: boolean = true
			local named: boolean = true
			local shown: { string } = {}

			for _, userId: number in users do
				local row: Row? = nil
				for name: string in boards do
					row = row or rowOf(results, name, userId)
				end

				rows = rows and row ~= nil
				named = named and row ~= nil and row.username ~= nil and row.displayName ~= nil
				table.insert(shown, `{userId} {row and row.username} ({row and row.displayName})`)
			end

			return rows, named, table.concat(shown, ", ")
		end

		local firstNamed: boolean = false
		local shown: boolean, first: string = settle(function (): (boolean, string)
			local rows: boolean, named: boolean, line: string = look()
			firstNamed = named

			return rows, line
		end)

		local named: boolean, later: string = false, first
		for _ = 1, NAME_READS do
			task.wait(READ_POLL)

			local _, everyNamed: boolean, line: string = look()
			named, later = everyNamed, line
			if named then
				break
			end
		end

		local opening: string = `the first read with both rows gave {first}{firstNamed and ", named already" or ""}`

		return shown and named, `{opening}; a later read gave {later}`
	end)
end

return Live
