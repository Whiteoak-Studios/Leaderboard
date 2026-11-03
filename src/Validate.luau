--[[
    The checks a Leaderboard makes on the values a game hands it: the boards
    a call targets, the rows a read takes, and each user id, amount and value
--]]

--!strict
local Constants = require(script.Parent.Constants)

local MAX_ROWS: number = Constants.MAX_ROWS

local Validate = {}

--[[
    The names of the boards a call targets, in the order of the object's
    sorted names. Throws unless boards is "All" or a dictionary holding true
    for at least one board, each of them one of those names
--]]

function Validate.targets(method: string, names: { string }, boards: any): { string }
	-- boards stays any, since neither checker indexes a value refined only to a table
	if boards == "All" then
		return names
	end

	if type(boards) ~= "table" then
		error(`Leaderboard:{method} takes "All" or a dictionary of board names to true, not {boards}`, 0)
	end

	if next(boards) == nil then
		error(`Leaderboard:{method} was given an empty dictionary of boards, which targets none`, 0)
	end

	for name: any, targeted: any in boards do
		if not table.find(names, name) or targeted ~= true then
			local held: string = `each key names one of this object's boards, {table.concat(names, ", ")}`
			error(`Leaderboard:{method}'s boards hold {name} = {targeted}, where {held}, and holds true`, 0)
		end
	end

	local targets: { string } = {}
	for _, name: string in names do
		if boards[name] then
			table.insert(targets, name)
		end
	end

	return targets
end

--[[
    The rows a read takes from each board: a range's one number for every
    board, or its number by board name and MAX_ROWS for the rest. Throws on
    a name no board holds, or a number of rows outside 1 to MAX_ROWS
--]]

function Validate.amounts(names: { string }, label: string, range: any): { [string]: number }
	-- range stays any, since neither checker indexes a value refined only to a table
	if type(range) == "table" then
		for name: any in range do
			if not table.find(names, name) then
				error(`{label} names {name}, which is not one of this object's boards`, 0)
			end
		end
	elseif range ~= nil and type(range) ~= "number" then
		error(`{label} is a number or a table of numbers by board name, not a {typeof(range)}`, 0)
	end

	local amounts: { [string]: number } = {}
	for _, name: string in names do
		local rows: unknown = MAX_ROWS
		if type(range) == "number" then
			rows = range
		elseif type(range) == "table" and range[name] ~= nil then
			rows = range[name]
		end

		if type(rows) ~= "number" or rows % 1 ~= 0 or rows < 1 or rows > MAX_ROWS then
			error(`{label} takes a whole number of rows from 1 to {MAX_ROWS}, not {rows}`, 0)
		end

		amounts[name] = rows
	end

	return amounts
end

--[[
    Throws, naming the call and the value, unless a user id is a whole,
    finite number. A negative one passes, as Studio's test players have
--]]

function Validate.userId(method: string, userId: unknown)
	if type(userId) ~= "number" or userId % 1 ~= 0 then
		error(`Leaderboard:{method} takes a userId that is a whole, finite number, not {userId}`, 0)
	end
end

--[[
    Throws, naming the call and the value, unless an amount or a value is a
    whole, non-negative, finite number, which every store holds exactly
--]]

function Validate.count(method: string, what: string, count: unknown)
	if type(count) ~= "number" or count % 1 ~= 0 or count < 0 then
		error(`Leaderboard:{method} takes {what} that is a whole, non-negative, finite number, not {count}`, 0)
	end
end

return Validate
