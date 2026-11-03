--[[
    Records the arguments of every call a table's function takes from here
    on, then makes the call, which is how a case counts calls it cannot see
--]]

--!strict
return function (holder: { [string]: any }, name: string): { { any } }
	local calls: { { any } } = {}
	local original: (...any) -> ...any = holder[name]

	holder[name] = function (...: any): ...any
		table.insert(calls, { ... })

		return original(...)
	end

	return calls
end
