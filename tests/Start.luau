--[[
    Where the fake clock starts, as the cases check it: the UTC day it starts
    in, which ends a Daily map's name, and how far the start is from midnight
--]]

--!strict
local Clock = require("./Fakes/Clock")

local DAY_SECONDS: number = 86400
local SINCE_MIDNIGHT: number = Clock.START % DAY_SECONDS

return {
	DAY = math.floor(Clock.START / DAY_SECONDS), -- The UTC day number the clock starts in
	SINCE_MIDNIGHT = SINCE_MIDNIGHT, -- Seconds from that day's midnight to the start
	TO_MIDNIGHT = DAY_SECONDS - SINCE_MIDNIGHT, -- Seconds from the start to the next midnight
}
