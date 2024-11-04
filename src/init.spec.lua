local Key = 1 -- The key for the leaderboard (change to reset)
local LeaderboardTypes = { -- You must provide keys for the individual boards
    ["AllTime"] = `AllTime-{Key}`,
}

return function ()
    local Leaderboard = require(script.Parent)

    describe("new", function()
        it("should Create a new leaderboard", function()
            local MoneyLeaderboard = Leaderboard.new(LeaderboardTypes, {
                Automation = true, -- Whether a connection to auto update leader board should be made
                Interval = 10, -- How often to update leaderboard
                RecordCount = 25, -- You can also do {Daily = 50, Weekly = 50, Monthly = 50, AllTime = 100}
            })

            local function increment()
                MoneyLeaderboard:IncrementValues("All", 1207632542, 20)
            end

            task.spawn(function()
                while task.wait(2) do
                    increment()
                end
            end)

            -- MoneyLeaderboard:Destroy() -- To remove leaderboard from datastore!

            MoneyLeaderboard.Updated:Connect(function(boards)
                -- This is where you would update the leaderboard GUI
                -- Returns us a table of all the boards that were updated
                for _, board in boards do
                    print(`Updating board {board.Type} - with {#board.Data} data`)
                end
            end)
        end)
    end)
end