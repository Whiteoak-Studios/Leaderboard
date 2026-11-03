--[[
    The loader resolves a package's relative requires from each depth to one
    copy of the installed Promise and Signal, and a new environment loads
    every module fresh
--]]

--!strict
local Environment = require("../../Environment")

local FIXTURE: string = "tests/Fixtures/Package"

return function (): (boolean, string | nil)
	local env: any = Environment.new({ root = FIXTURE })
	local package: any = env.require("init")

	if package.Board.Promise ~= package.Promise or package.Queue.Promise ~= package.Promise then
		return false, "a folder module or a root file reached another Promise than the package root did"
	end

	if package.Board.Rows.Signal ~= package.Signal then
		return false, "a file inside a folder module reached another Signal than the package root did"
	end

	if type(package.Promise.delay) ~= "function" or type(package.Signal.new) ~= "function" then
		return false, "Promise or Signal is not the installed package"
	end

	if env.require("Board/init") ~= package.Board or env.require("Board/Rows") ~= package.Board.Rows then
		return false, "a case's require ran a module a second time"
	end

	if Environment.new({ root = FIXTURE }).require("init") == package then
		return false, "a new environment reused the last one's modules"
	end

	if pcall(env.require, "Board") then
		return false, "the require took a folder's path, where it takes a file's"
	end

	return true, nil
end
