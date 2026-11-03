--[[
    Throws unless the call throws exactly the given message, which is how a
    case proves a fake refuses what the real service refuses
--]]

--!strict
return function (message: string, call: () -> ())
	local ran: boolean, thrown: any = pcall(call)
	assert(not ran, `Expected "{message}", and nothing was thrown`)
	assert(thrown == message, `Expected "{message}", got "{thrown}"`)
end
