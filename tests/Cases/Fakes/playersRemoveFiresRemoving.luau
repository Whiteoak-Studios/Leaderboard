--[[
    Players.remove fires PlayerRemoving with the leaving player, as a player
    leaving the server does
--]]

--!strict
local Environment = require("../../Environment")

local USER: number = 42

return function (): (boolean, string | nil)
	local players: any = Environment.new().services.Players
	local left: number? = nil

	players.PlayerRemoving:Connect(function (player: any)
		left = player.UserId
	end)

	players.remove(USER)

	if left ~= USER then
		return false, `PlayerRemoving fired with {left}`
	end

	return true, nil
end
