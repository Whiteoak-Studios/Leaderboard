local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.DevPackages.TestEZ)

local Leaderboard = script.Parent.Parent.Module

TestEZ.TestBootstrap:run({
    Leaderboard["init.spec"],
})