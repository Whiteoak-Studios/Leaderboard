--[[
    The saves, merged onto a Leaderboard: each queue written through the one
    pool of board writes every object on the server shares, and a call's
    writes settled together
--]]

--!strict
local Write = {}

local Promise: any = require(script.Parent.Parent.Promise)

local Constants = require(script.Parent.Constants)
local Queue = require(script.Parent.Queue)
local Types = require(script.Parent.Config.Types.Leaderboard)

local MAX_IN_FLIGHT: number = Constants.MAX_IN_FLIGHT

type Entry = Queue.Entry
type Leaderboard = Types.Leaderboard

local Writing: number = 0 -- The board writes in flight across every object's saves, at most MAX_IN_FLIGHT
local Waiting: { () -> () } = {} -- Each lane waiting for one of those writes to end, oldest first

--[[
    Resolves once one of the server's MAX_IN_FLIGHT board writes is free,
    holding it until free hands it on
--]]

local function claim(): any
	if Writing < MAX_IN_FLIGHT then
		Writing += 1

		return Promise.resolve()
	end

	return Promise.new(function (resolve: () -> ())
		table.insert(Waiting, resolve)
	end)
end

--[[
    Hands a finished write's place to the lane that has waited longest, or
    frees it when no lane waits
--]]

local function free()
	local waiter: (() -> ())? = table.remove(Waiting, 1)
	if waiter then
		waiter()
	else
		Writing -= 1
	end
end

--[[
    Takes the queue and writes it through MAX_IN_FLIGHT lanes, each writing
    its next entry once its last has settled and the server's pool has room.
    A failed write puts its amount back, and the save rejects once every
    write has settled
--]]

function Write._write(self: Leaderboard): any
	local entries: { Entry } = self._queue:take()
	local writes: { any } = {}
	local lanes: { any } = {}
	local taken: number = 0

	for _ = 1, math.min(MAX_IN_FLIGHT, #entries) do
		-- A lane loops rather than chaining, so writes that settle at once never deepen the stack
		local lane: any = Promise.new(function (resolve: () -> ())
			while taken < #entries do
				taken += 1
				local entry: Entry = entries[taken]

				claim():await()

				local write: any = self._boards[entry.board]:update(entry.userId, function (old: number): number
					return old + entry.amount
				end)

				table.insert(writes, write)

				local written: boolean = write:await()
				free()

				if not written then
					self._queue:restore(entry)
				end
			end

			resolve()
		end)

		table.insert(lanes, lane)
	end

	return Promise.allSettled(lanes):andThen(function (): any
		return self:_settleAll(writes, "save every queued amount, and the failed ones stay queued")
	end)
end

--[[
    Waits for every promise to settle, then rejects with each failure's
    reason if any failed, so one failed write stops none of the others
--]]

function Write._settleAll(_: Leaderboard, promises: { any }, action: string): any
	local reasons: { string } = {}
	local caught: { any } = {}

	for _, promise: any in promises do
		local handled: any = promise:catch(function (reason: any)
			table.insert(reasons, tostring(reason))
		end)

		table.insert(caught, handled)
	end

	return Promise.allSettled(caught):andThen(function (): any
		if #reasons > 0 then
			local failed: string = `{#reasons} of {#promises} writes failed`

			return Promise.reject(`Leaderboard could not {action}: {failed}. {table.concat(reasons, "; ")}`)
		end

		return nil
	end)
end

return Write
