--[[
    The fake clock environments run on: one time behind os.time, os.clock,
    DateTime and Heartbeat, and a task library whose waits, delays and
    defers run only when a case advances it
--]]

--!strict
local task = require("@lune/task")

local START: number = 1793793600 -- A Wednesday noon UTC, inside an hour, day, week and month rather than on an edge
local FRAME: number = 1 / 60 -- One Heartbeat, the least a wait lasts
local MAX_RESUMES: number = 10000 -- Threads one instant may resume before the clock calls it a runaway

type Entry = {
	at: number, -- The os.clock time it is due
	parker: any, -- The signal its thread waits on
}

export type Task = {
	spawn: (callback: any, ...any) -> thread,
	defer: (callback: any, ...any) -> thread,
	delay: (seconds: number?, callback: any, ...any) -> thread,
	wait: (seconds: number?) -> number,
	cancel: (thread: thread) -> (),
}

export type Clock = {
	advance: (seconds: number) -> (),
	advanceUntil: (condition: () -> boolean, limit: number) -> boolean,
	now: () -> number,
	task: Task,
	os: { [string]: any },
	DateTime: { [string]: any },
	Heartbeat: any,
}

local Clock = {
	START = START,
}

--[[
    Builds a clock at its start time. Its Heartbeat and the signal each
    waiting thread parks on come from the given Signal module, which runs
    on Lune's task, so a resumed thread runs before advance moves on
--]]

function Clock.new(Signal: any): Clock
	local elapsed: number = 0
	local queue: { Entry } = {}
	local heartbeat: any = Signal.new()

	local function now(): number
		return START + elapsed
	end

	--[[
	    Parks the running thread until the clock reaches at, behind every
	    thread due as soon
	--]]

	local function park(at: number)
		local index: number = #queue + 1
		for position: number, entry: Entry in queue do
			if entry.at > at then
				index = position
				break
			end
		end

		local parker: any = Signal.new()
		table.insert(queue, index, { at = at, parker = parker })
		parker:Wait()
	end

	--[[
	    How long a wait lasts: Roblox reads a missing, negative, infinite or
	    NaN wait as none, and a wait lasts a frame at the least
	--]]

	local function length(seconds: number?): number
		local given: number = (seconds and seconds >= 0 and seconds < math.huge) and seconds or 0

		return math.max(given, FRAME)
	end

	--[[
	    Runs a function, or resumes a thread, on a thread of its own once the
	    clock reaches at
	--]]

	local function schedule(at: number, callback: any, ...: any): thread
		return task.spawn(function (...: any)
			park(at)

			if type(callback) == "function" then
				callback(...)
			else
				task.spawn(callback, ...)
			end
		end, ...)
	end

	--[[
	    Resumes every thread due by now in time order, including any a
	    resumed thread schedules for now
	--]]

	local function resumeDue()
		local resumed: number = 0
		while resumed < MAX_RESUMES and queue[1] and queue[1].at <= elapsed do
			local entry: Entry = table.remove(queue, 1) :: Entry
			resumed += 1
			entry.parker:Fire()
		end

		if queue[1] and queue[1].at <= elapsed then
			error(
				`The clock resumed {MAX_RESUMES} threads in one instant with more still due; something defers forever`
			)
		end
	end

	--[[
	    Moves time forward, stopping at each thread due on the way and at
	    every frame while anything listens on Heartbeat, as Promise.delay
	    does. Heartbeat fires at each stop, then the threads due there run
	--]]

	local function advance(seconds: number)
		assert(seconds >= 0 and seconds < math.huge, `clock.advance takes a finite time to move forward, not {seconds}`)

		local target: number = elapsed + seconds
		resumeDue()

		-- Whiteoak TODO: a pending Promise.delay makes this step frame by frame, so jump to its due time
		-- once a case advances days under one
		while elapsed < target do
			local stop: number = target
			if queue[1] then
				stop = math.min(stop, queue[1].at)
			end

			if #heartbeat:GetConnections() > 0 then
				stop = math.min(stop, elapsed + FRAME)
			end

			local step: number = stop - elapsed
			elapsed = stop
			heartbeat:Fire(step)
			resumeDue()
		end
	end

	--[[
	    Advances a frame at a time until the condition holds or the limit
	    passes, and says whether it held
	--]]

	local function advanceUntil(condition: () -> boolean, limit: number): boolean
		local deadline: number = elapsed + limit
		advance(0)

		while not condition() and elapsed < deadline do
			advance(math.min(FRAME, deadline - elapsed))
		end

		return condition()
	end

	local fakeOs: { [string]: any } = table.clone(os)

	fakeOs.clock = function (): number
		return elapsed
	end

	fakeOs.time = function (date: any): number
		-- A date table reads as UTC, as it does on a Roblox server
		if date then
			return os.time(date)
		end

		return math.floor(now())
	end

	fakeOs.date = function (format: string?, time: number?): any
		return os.date(format, time or math.floor(now()))
	end

	return {
		advance = advance,
		advanceUntil = advanceUntil,
		now = now,
		Heartbeat = heartbeat,
		os = fakeOs,

		task = {
			spawn = task.spawn,
			cancel = task.cancel,

			defer = function (callback: any, ...: any): thread
				return schedule(elapsed, callback, ...)
			end,

			delay = function (seconds: number?, callback: any, ...: any): thread
				return schedule(elapsed + length(seconds), callback, ...)
			end,

			wait = function (seconds: number?): number
				local start: number = elapsed
				park(elapsed + length(seconds))

				return elapsed - start
			end,
		},

		DateTime = {
			now = function (): { UnixTimestamp: number }
				return { UnixTimestamp = math.floor(now()) }
			end,

			fromUniversalTime = function (
				year: number?,
				month: number?,
				day: number?,
				hour: number?,
				minute: number?,
				second: number?
			): { UnixTimestamp: number }
				local date: { [string]: number } = {
					year = year or 1970,
					month = month or 1,
					day = day or 1,
					hour = hour or 0,
					min = minute or 0,
					sec = second or 0,
				}

				return { UnixTimestamp = os.time(date :: any) }
			end,
		},
	}
end

return Clock
