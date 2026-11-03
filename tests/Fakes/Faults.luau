--[[
    The failures, delays and forced re-runs a case queues on a fake
    service's methods, each spent by that method's next call on any store
    the service made
--]]

--!strict
export type Faults = {
	failNext: (method: string, count: number?) -> (),
	delayNext: (method: string, seconds: number) -> (),
	rerunNext: (method: string) -> (),
	spend: (method: string) -> (),
	rerun: () -> boolean,
}

local Faults = {}

--[[
    Builds one service's faults. A method the service does not have is
    refused, so a misspelled name cannot leave a failure path untested
--]]

function Faults.new(service: string, methods: { string }, sleep: (seconds: number?) -> number): Faults
	local failures: { [string]: number } = {}
	local delays: { [string]: { number } } = {}
	local reruns: number = 0

	local function check(method: string)
		assert(table.find(methods, method), `{service} has no {method} a case can fail or delay`)
	end

	return {
		failNext = function (method: string, count: number?)
			check(method)

			local added: number = count or 1
			assert(added >= 1 and added % 1 == 0, `failNext takes a whole count of calls, not {count}`)
			failures[method] = (failures[method] or 0) + added
		end,

		delayNext = function (method: string, seconds: number)
			check(method)
			assert(seconds > 0 and seconds < math.huge, `delayNext takes a time to wait, not {seconds}`)

			local queued: { number } = delays[method] or {}
			table.insert(queued, seconds)
			delays[method] = queued
		end,

		rerunNext = function (method: string)
			assert(
				method == "UpdateAsync" and table.find(methods, method),
				`rerunNext re-runs a store's UpdateAsync, not {service}.{method}`
			)

			reruns += 1
		end,

		--[[
		    The fake's own: waits out the delay queued next on a method, then
		    throws if a failure is queued
		--]]

		spend = function (method: string)
			local queued: { number }? = delays[method]
			local seconds: number? = queued and table.remove(queued, 1)
			if seconds then
				sleep(seconds)
			end

			local failing: number = failures[method] or 0
			if failing > 0 then
				failures[method] = failing - 1
				error(`{service}.{method} failed, as failNext asked`, 0)
			end
		end,

		--[[
		    The fake's own: takes one forced re-run of UpdateAsync, if a case
		    queued any
		--]]

		rerun = function (): boolean
			if reruns == 0 then
				return false
			end

			reruns -= 1

			return true
		end,
	}
end

return Faults
