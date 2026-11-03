--[[
    The benchmarks for the play server only: a map's size while copies of
    the package write, the cost of reading and saving Frontier Zero's
    boards, and the queue's speed, each deleting what it wrote
--]]

--!strict
local MemoryStoreService = game:GetService("MemoryStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerPackages = ServerScriptService.ServerPackages

local Leaderboard = require(ServerPackages.Leaderboard)

local Checks = require(script.Parent.Checks)
local Constants = require(ServerPackages.Leaderboard.Constants)
local Jobs = require(script.Parent.Jobs)
local Stores = require(script.Parent.Stores)

local KEPT_ROWS: number = Constants.KEPT_ROWS
local MAX_RANGE_READ: number = Constants.MAX_RANGE_READ
local MAX_IN_FLIGHT: number = Constants.MAX_IN_FLIGHT
local REQUEST_UNITS: number = Stores.REQUEST_UNITS
local READ_UNITS: number = 2 * MAX_RANGE_READ - KEPT_ROWS -- A read's units at most, the items it takes and its trims
local AWAIT_DEADLINE: number = 1200 -- Seconds a save or read may wait on Studio's budgets before the run fails
local AMOUNT: number = 1 -- What each increment of the save and queue benchmarks adds
local TRIM_COPIES: number = 3 -- Copies of the package standing in for servers while the map is trimmed
local TRIM_PLAYERS: number = 100 -- Players each copy saves in the first burst, enough that one read cannot trim it all
local TRIM_READS: number = 10 -- Reads made at most while the trims bring the map down
local TRIM_ROUNDS: number = 2 -- Rounds of every copy reading and writing once the map is down
local RISERS: number = 10 -- Players each copy lifts past the cutoff in a round
local BOOST: number = 1000 -- What lifts them, above any total the burst wrote
local FILL_ROWS: number = Constants.MAX_ROWS -- The rows the read benchmark fills each board with
local QUEUE_CALLS: number = 10000 -- The increments the queue benchmark makes in one frame
local MILLISECONDS: number = 1e3 -- In a second
local MICROSECONDS: number = 1e6 -- In a second
local PERCENT: number = 100
local CCU: number = 2000 -- Frontier Zero's launch goal
local READ_INTERVAL: number = 90 -- Seconds between Frontier Zero's automated reads
local MINUTE: number = 60
local SERVER_SIZES: { number } = { 150, 40 } -- A full Frontier Zero server, and the small one its estimates take
local UNITS_BASE: number = 1000 -- MemoryStore's request units a minute before users
local UNITS_PER_USER: number = 120 -- And what each concurrent user adds
local LIST_BASE: number = 5 -- A server's ordered list budget a minute before players
local LIST_PER_PLAYER: number = 2 -- And what each player adds

type Package = typeof(Leaderboard)
type Object = Leaderboard.Leaderboard
type BoardResult = Leaderboard.BoardResult
type BoardConfig = Leaderboard.BoardConfig
type Entry = Checks.Entry

local Bench = {}

local function await(promise: any): any
	return Jobs.await(promise, AWAIT_DEADLINE)
end

local function finish(objects: { Object }, body: () -> (boolean, string)): (boolean, string)
	return Jobs.finish(objects, AWAIT_DEADLINE, body)
end

--[[
    Builds one object over each board table on a single fresh copy of the
    package
--]]

local function build(objects: { { [string]: BoardConfig } }): { Object }
	local Package: Package = Jobs.copy()
	local built: { Object } = {}
	for _, boards: { [string]: BoardConfig } in objects do
		table.insert(built, Package.new(boards))
	end

	return built
end

local function seconds(started: number): string
	return string.format("%.2f", os.clock() - started)
end

--[[
    The map's size while servers write: copies of the package each save
    players into an unread map, as every server does at a period's first
    writes, then one copy reads until its trims bring the map to KEPT_ROWS,
    and in rounds every copy lifts players past the cutoff while it is read
--]]

function Bench.trims(runId: string): (boolean, string)
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "trims")
	local users: { number } = Checks.span(TRIM_COPIES * TRIM_PLAYERS)
	local map: MemoryStoreSortedMap = MemoryStoreService:GetSortedMap(Checks.mapName("Trim", boards.Trim))

	local function sizeOf(): number
		Stores.spend(REQUEST_UNITS)

		return map:GetSizeAsync()
	end

	-- Each copy of the package stands in for a server, with its own cutoff
	local objects: { Object } = {}
	for _ = 1, TRIM_COPIES do
		table.insert(objects, build({ boards })[1])
	end

	local passed: boolean, line: string = finish(objects, function (): (boolean, string)
		-- 1) Every copy reads the empty map, so each of its writes belongs, as at a period's first writes
		for _, object: Object in objects do
			Stores.spend(REQUEST_UNITS)
			await(object:getAll("All"))
		end

		-- 2) The burst, one copy's save after another's
		for index: number, object: Object in objects do
			for rank: number = 1, TRIM_PLAYERS do
				object:increment("All", users[(index - 1) * TRIM_PLAYERS + rank], rank)
			end

			Stores.spend(TRIM_PLAYERS)
			await(object:save())
		end

		-- 3) One copy reads until the trims bring the map down
		local sizes: { number } = { sizeOf() }
		for _ = 1, TRIM_READS do
			if sizes[#sizes] <= KEPT_ROWS then
				break
			end

			Stores.spend(READ_UNITS)
			await(objects[1]:getAll("All"))
			table.insert(sizes, sizeOf())
		end

		-- 4) Every copy reads, lifts its next lowest players past the cutoff and saves, then one copy reads
		local held: boolean = sizes[#sizes] <= KEPT_ROWS
		local rounds: { string } = {}

		for round: number = 1, TRIM_ROUNDS do
			for _, object: Object in objects do
				Stores.spend(MAX_RANGE_READ)
				await(object:getAll("All"))
			end

			for index: number, object: Object in objects do
				for rank: number = (round - 1) * RISERS + 1, round * RISERS do
					object:increment("All", users[(index - 1) * TRIM_PLAYERS + rank], BOOST)
				end

				Stores.spend(RISERS)
				await(object:save())
			end

			local before: number = sizeOf()
			Stores.spend(READ_UNITS)
			
			await(objects[1]:getAll("All"))

			local after: number = sizeOf()
			held = held and after <= KEPT_ROWS
			table.insert(rounds, `{before} before the read and {after} after`)
		end

		local trail: { string } = {}
		for _, size: number in sizes do
			table.insert(trail, `{size}`)
		end

		local burst: string = `{TRIM_COPIES} copies each saved {TRIM_PLAYERS} players into an unread map`
		local trimmed: string = `{#sizes - 1} reads brought it to {KEPT_ROWS} or under ({table.concat(trail, ", ")})`
		local writing: string = `{TRIM_ROUNDS} rounds of every copy lifting {RISERS} players past the cutoff`

		return held, `{burst}, peaking at {sizes[1]} entries; {trimmed}; {writing} left {table.concat(rounds, "; ")}`
	end)

	local removed: boolean, removal: string = Stores.delete(Checks.entries({ boards }, users))

	return passed and removed, `{line}; {removal}`
end

--[[
    What a read costs: Frontier Zero's 13 boards, filled straight to their
    rows, read once through its three objects, in items, requests, DataStore
    budget and time, with what that costs at 2,000 CCU worked out beside it
--]]

function Bench.readCost(runId: string): (boolean, string)
	local shared: boolean = true -- Boards on one slot share a store, so the fill writes each slot once
	local fleet: { { [string]: BoardConfig } } = Checks.fleet(runId, "B2", shared)
	local filled: { Entry } = {}
	for _, entry: Entry in Checks.entries(fleet, Checks.span(FILL_ROWS)) do
		if entry.store ~= "totals" then
			table.insert(filled, entry)
		end
	end

	local mapBoards: number = 0
	local orderedBoards: number = 0
	for _, boards: { [string]: BoardConfig } in fleet do
		for _ in Checks.maps(boards) do
			mapBoards += 1
		end

		orderedBoards += boards.AllTime and 1 or 0
	end

	local objects: { Object } = build(fleet)

	local passed: boolean, line: string = finish(objects, function (): (boolean, string)
		for _, entry: Entry in filled do
			local set: boolean, reason: any = Stores.set(entry, entry.userId)
			if not set then
				return false, `the fill failed at {entry.store} {entry.name} {entry.key}: {reason}`
			end
		end

		-- The read takes a minute's units at once, so it waits for the fill's to leave the window
		Stores.spend(mapBoards * FILL_ROWS)

		local before: { [string]: number } = Stores.budgets()
		local started: number = os.clock()
		local reads: { any } = {}

		for _, object: Object in objects do
			table.insert(reads, object:getAll("All"))
		end

		local mapItems: number = 0
		local orderedItems: number = 0
		local read: number = 0

		for _, promise: any in reads do
			local results: { BoardResult } = await(promise)
			for _, result: BoardResult in results do
				read += 1
				if result.board == "AllTime" then
					orderedItems += #result.rows
				else
					mapItems += #result.rows
				end
			end
		end

		local took: string = seconds(started)
		local moved: string = Stores.moved(before, Stores.budgets())

		local perMinute: number = MINUTE / READ_INTERVAL
		local scaled: { string } = {}

		for _, players: number in SERVER_SIZES do
			local servers: number = math.ceil(CCU / players)
			local units: number = servers * mapItems * perMinute
			local budget: number = UNITS_BASE + UNITS_PER_USER * CCU
			local share: string = string.format("%.1f", units / budget * PERCENT)
			local lists: string = string.format("%.2f", orderedBoards * perMinute)
			local listBudget: number = LIST_BASE + LIST_PER_PLAYER * players

			local experience: string =
				`{servers} servers x {mapItems} items x {MINUTE}/{READ_INTERVAL} = {math.round(units)} units a minute`
			local server: string = `each server {orderedBoards} x {MINUTE}/{READ_INTERVAL} = {lists} ordered lists`
			table.insert(
				scaled,
				`at {players} players a server, {experience}, {share}% of {budget}; {server} of its {listBudget}`
			)
		end

		local stores: { [string]: boolean } = {}
		local filledStores: number = 0

		for _, entry: Entry in filled do
			filledStores += stores[entry.name] and 0 or 1
			stores[entry.name] = true
		end

		local requests: number = mapBoards + orderedBoards
		local maps: string = `{mapItems} items from {mapBoards} maps, a request unit each`
		local ordered: string = `{orderedItems} from {orderedBoards} ordered stores`
		local measured: string = `{read} boards read in {took} s, {requests} requests: {maps}, and {ordered}`
		local sharing: string = `boards in different objects share a slot's store, so the fill wrote {filledStores}`

		return read == requests and mapItems == mapBoards * FILL_ROWS,
			`{measured}; DataStore budgets {moved}; {table.concat(scaled, "; ")}; {sharing}`
	end)

	local removed: boolean, removal: string = Stores.delete(filled)

	return passed and removed, `{line}; {removal}`
end

--[[
    What a save costs: every board of Frontier Zero's three objects queued
    for each of the players, each object's maps read first as its automation
    does, then the three saves one after another, in requests, budget and time
--]]

function Bench.saveCost(runId: string, players: number): (boolean, string)
	assert(type(players) == "number" and players >= 1 and players % 1 == 0, `saveCost takes a whole number of players`)

	local shared: boolean = false -- Every board on a store of its own, as the game builds them
	local fleet: { { [string]: BoardConfig } } = Checks.fleet(runId, "B3", shared)
	local users: { number } = Checks.span(players)
	local objects: { Object } = build(fleet)

	local passed: boolean, line: string = finish(objects, function (): (boolean, string)
		local boardCount: number = 0
		local standard: number = 0
		local ordered: number = 0

		for index: number, object: Object in objects do
			local maps: { [string]: boolean } = Checks.maps(fleet[index])
			for _ in maps do
				Stores.spend(REQUEST_UNITS)
			end

			await(object:getAll(maps))

			for _, userId: number in users do
				object:increment("All", userId, AMOUNT)
			end

			for name: string in fleet[index] do
				boardCount += 1
				standard += maps[name] and players or 0
				ordered += maps[name] and 0 or players
			end
		end

		-- The map writes come inside the saves, so the window is cleared for them first
		Stores.spend(math.min(standard, Stores.UNIT_LIMIT))

		local before: { [string]: number } = Stores.budgets()
		local started: number = os.clock()
		local times: { string } = {}
		local failures: { string } = {}

		for _, object: Object in objects do
			local began: number = os.clock()
			local saved: boolean, reason: any = object:save():timeout(AWAIT_DEADLINE):await()
			table.insert(times, seconds(began))

			if not saved then
				table.insert(failures, tostring(reason))
			end
		end

		local took: number = os.clock() - started
		local moved: string = Stores.moved(before, Stores.budgets())
		local writes: number = standard + ordered
		local rate: string = string.format("%.1f", writes / took)

		local queue: string = `{players} players on all {boardCount} boards: {writes} board writes`
		local requests: string = `{standard} standard and {ordered} ordered UpdateAsync, and {standard} map writes`
		local flight: string = `each save at most {MAX_IN_FLIGHT} board writes in flight, the objects one after another`
		local timing: string = `saved in {table.concat(times, ", ")} s, {string.format("%.2f", took)} s in all`
		local speed: string = `{rate} board writes a second`
		local throttle: string = standard > Stores.UNIT_LIMIT and ", more map writes than a minute's units" or ""
		local failed: string = #failures > 0 and table.concat(failures, "; ") or "none"
		local spending: string = `DataStore budgets {moved}{throttle}`

		return #failures == 0, `{queue}, {requests}; {flight}; {timing}, {speed}; {spending}; failures {failed}`
	end)

	local removed: boolean, removal: string = Stores.delete(Checks.entries(fleet, users))

	return passed and removed, `{line}; {removal}`
end

--[[
    How fast the queue takes increments: QUEUE_CALLS of them naming one
    board in one frame, timed, with a thread deferred before the loop as the
    proof that no call yielded, since a deferred thread runs once one yields
--]]

function Bench.queueSpeed(runId: string): (boolean, string)
	local boards: { [string]: BoardConfig } = Checks.boards(runId, "queue")
	local userId: number = Checks.users("queue")[1]
	local targets: { [string]: boolean } = Checks.maps(boards)
	local object: Object = build({ boards })[1]

	return finish({ object }, function (): (boolean, string)
		local yielded: boolean = false
		task.defer(function ()
			yielded = true
		end)

		local started: number = os.clock()
		for _ = 1, QUEUE_CALLS do
			object:increment(targets, userId, AMOUNT)
		end

		local took: number = os.clock() - started
		local stayed: boolean = not yielded

		local total: string = string.format("%.2f", took * MILLISECONDS)
		local each: string = string.format("%.3f", took / QUEUE_CALLS * MICROSECONDS)
		local timing: string = `{QUEUE_CALLS} increments naming one board took {total} ms, {each} us a call`
		local proof: string = stayed and "had not run when it ended, so no call yielded"
			or "ran inside it, so a call yielded"

		return stayed, `{timing}; a thread deferred before the loop {proof}`
	end)
end

return Bench
