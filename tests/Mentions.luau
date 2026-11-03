--[[
    Whether what a call threw holds the given text as written, which is how
    a case proves a refusal names what it refused
--]]

--!strict
local PLAIN: boolean = true -- Finds the text as written, not as a pattern

return function (thrown: any, text: string): boolean
	return tostring(thrown):find(text, 1, PLAIN) ~= nil
end
