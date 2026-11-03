--[[
    The live run's Script in the dev place, idle until its RunId attribute
    is set before play: then it queues the shutdown check, or with Players
    set, Frontier Zero's fleet full of players, for the server's close to save
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerPackages = ServerScriptService.ServerPackages

local Leaderboard = require(ServerPackages.Leaderboard)

local Checks = require(script.Checks)
local Jobs = require(script.Jobs)
local Stores = require(script.Stores)

local PREFIX: string = "[Leaderboard live]" -- Starts every line this Script prints, for get_console_output
local CLOSE_AMOUNT: number = Checks.CLOSE_AMOUNT
local FLEET_AMOUNT: number = 1 -- What each of the fleet's players adds to each board

type BoardConfig = Leaderboard.BoardConfig
type Object = Leaderboard.Leaderboard

local runId: any = script:GetAttribute("RunId")
local players: any = script:GetAttribute("Players")

--[[
    The shutdown check: one object over a rolling board and AllTime, read so
    its save writes the row, holding an amount only the package's own close
    saves, which the Edit datamodel reads back once play stops
--]]

local function queueCheck(id: string)
	local boards: { [string]: BoardConfig } = Checks.boards(id, "close")
	local userId: number = Checks.users("close")[1]
	local object: Object = Leaderboard.new(boards)

	object:getAll(Checks.maps(boards)):expect()
	object:increment("All", userId, CLOSE_AMOUNT)

	print(`{PREFIX} close: queued {CLOSE_AMOUNT} for {userId} under {id}, for the package's close to save`)
end

--[[
    The shutdown of a full queue: Frontier Zero's three objects with every
    board queued for each player, built on a copy required after our close
    is bound, so the close reaches ours first and it times the destroys the
    package's would make
--]]

local function queueFleet(id: string, count: number)
	local fleet: { { [string]: BoardConfig } } = Checks.closeFleet(id)
	local objects: { Object } = {}
	local writes: number = 0

	game:BindToClose(function ()
		local before: { [string]: number } = Stores.budgets()
		print(`{PREFIX} B3 close: destroying {#objects} objects holding {writes} board writes`)

		local started: number = os.clock()
		local promises: { any } = {}
		local failures: { string } = {}
		for _, object: Object in objects do
			local destroyed: boolean, promise: any = pcall(object.destroy, object)
			if destroyed then
				table.insert(promises, promise)
			else
				table.insert(failures, `destroy threw {promise}, so the package's close reached it first`)
			end
		end

		for _, promise: any in promises do
			local saved: boolean, reason: any = promise:await()
			if not saved then
				table.insert(failures, tostring(reason))
			end
		end

		local took: string = string.format("%.2f", os.clock() - started)
		local moved: string = Stores.moved(before, Stores.budgets())
		local failed: string = #failures > 0 and table.concat(failures, "; ") or "none"

		print(
			`{PREFIX} B3 close: {writes} board writes saved by destroy in {took} s; budgets {moved}; failures {failed}`
		)
	end)

	local Package: typeof(Leaderboard) = Jobs.copy()
	for _, boards: { [string]: BoardConfig } in fleet do
		local object: Object = Package.new(boards)
		table.insert(objects, object)

		object:getAll(Checks.maps(boards)):expect()
		for _, userId: number in Checks.span(count) do
			object:increment("All", userId, FLEET_AMOUNT)
		end

		for _ in boards do
			writes += count
		end
	end

	print(`{PREFIX} B3 close: queued {count} players on every board, {writes} board writes, for the close to save`)
end

if type(runId) == "string" then
	if type(players) == "number" then
		queueFleet(runId, players)
	else
		queueCheck(runId)
	end
end
