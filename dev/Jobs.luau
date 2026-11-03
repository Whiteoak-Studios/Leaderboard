--[[
    How a check runs through execute_luau: as a job whose result waits on
    the live run's Script, on a copy of the package that no other caller
    shares
--]]

--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ServerPackages = ServerScriptService.ServerPackages

local RESULT_WAIT: number = 20 -- Seconds a call waits on its job before answering that it still runs
local RESULT_POLL: number = 0.5 -- Seconds between looks at a job's result
local RUNNING: string = "RUNNING" -- How a job's result starts until the job ends

type Destroyable = { destroy: (self: any) -> any } -- A Leaderboard object, as far as finish needs one

local Jobs = {
	holder = script.Parent :: Script, -- The Script, whose attributes outlive every call's copy of these modules
}

--[[
    Starts a check as a job of its own and waits up to RESULT_WAIT for it.
    The result is kept as an attribute named for the job, PASS or FAIL and
    the check's line, so a later call reads it with result
--]]

function Jobs.run(name: string, check: (...any) -> (boolean, string), ...: any): string
	Jobs.holder:SetAttribute(name, `{RUNNING} since {os.date("!%H:%M:%S")} UTC`)

	task.spawn(function (...: any)
		local ran: boolean, passed: any, line: any = pcall(check, ...)
		local verdict: string = ran and passed and "PASS" or "FAIL"
		local detail: string = ran and tostring(line) or `threw {passed}`

		Jobs.holder:SetAttribute(name, `{verdict} {detail}`)
	end, ...)

	return Jobs.result(name)
end

--[[
    A job's result once it has one, or its RUNNING line once RESULT_WAIT has
    passed, in which case the job carries on and a later call asks again
--]]

function Jobs.result(name: string): string
	local deadline: number = os.clock() + RESULT_WAIT
	local result: any = Jobs.holder:GetAttribute(name)

	while type(result) == "string" and string.sub(result, 1, #RUNNING) == RUNNING and os.clock() < deadline do
		task.wait(RESULT_POLL)
		result = Jobs.holder:GetAttribute(name)
	end

	return type(result) == "string" and result or `No job named {name} has run in this datamodel`
end

--[[
    A copy of the package no other caller shares, with its own objects, name
    cache and close: its ModuleScript cloned beside Promise and Signal and
    required. The clone goes once required, since the copy has loaded
--]]

function Jobs.copy(): any
	local clone = ServerPackages.Leaderboard:Clone()
	clone.Name = "LeaderboardCopy"
	clone.Parent = ServerPackages

	-- The checker follows only a require by path, so the clone's goes through any, typed by each caller
	local loaded: any = (require :: any)(clone)
	clone:Destroy()

	return loaded
end

--[[
    Waits for a package promise, deadline seconds at most, and gives its
    value or throws its rejection
--]]

function Jobs.await(promise: any, deadline: number): any
	return promise:timeout(deadline):expect()
end

--[[
    Runs a check's body, then destroys every object it built whether the
    body returned or threw, waiting deadline seconds at most on each last
    save, and gives the body's result or what it threw
--]]

function Jobs.finish(objects: { Destroyable }, deadline: number, body: () -> (boolean, string)): (boolean, string)
	local ran: boolean, passed: any, line: any = pcall(body)
	for _, object: Destroyable in objects do
		object:destroy():timeout(deadline):await()
	end

	if not ran then
		return false, `threw {passed}`
	end

	return passed, line
end

--[[
    Clears every attribute on the Script: each job's result, and the run's
    RunId and Players
--]]

function Jobs.clear()
	for name: string in Jobs.holder:GetAttributes() do
		Jobs.holder:SetAttribute(name, nil)
	end
end

return Jobs
