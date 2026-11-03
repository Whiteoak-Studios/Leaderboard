--[[
    A fake MemoryStoreService of sorted maps two servers can share, with the
    real name, key, value and expiry limits, entries expiring on the fake
    clock, and the peek reader a case checks a map with
--]]

--!strict
local roblox: any = require("@lune/roblox")
local serde = require("@lune/serde")

local Clock = require("./Clock")
local Faults = require("./Faults")
local Store = require("./Store")

local MAX_LENGTH: number = 128 -- Characters in a sorted map's name or a key
local MAX_VALUE: number = 32 * 1024 -- Bytes a value takes as JSON
local MAX_EXPIRATION: number = 3888000 -- Seconds an entry lives at most, 45 days
local MAX_RANGE: number = 200 -- Items one GetRangeAsync returns at most
local METHODS: { string } = { "UpdateAsync", "GetRangeAsync", "RemoveAsync" }

type Clock = Clock.Clock
type Entry = Store.Entry
type Entries = { [string]: Entry }

export type Item = {
	key: string,
	value: any,
	sortKey: number,
	expiresAt: number,
}

export type Maps = { [string]: Entries }

export type MemoryStoreService = {
	GetSortedMap: (self: any, name: string) -> { [string]: any },
	failNext: (method: string, count: number?) -> (),
	delayNext: (method: string, seconds: number) -> (),
	rerunNext: (method: string) -> (),
	peek: (map: string) -> { Item },
}

local MemoryStoreService = {}

--[[
    A key as the map reads it, a number passed as its digits, refused past
    128 characters
--]]

local function keyed(key: string | number): string
	assert(type(key) == "string" or type(key) == "number", `A sorted map key is a string, not a {type(key)}`)

	local text: string = tostring(key)
	if #text > MAX_LENGTH then
		error("InvalidParameter: The provided key is not valid.", 0)
	end

	return text
end

--[[
    The map's live entries, ordered by sort key and then by key, highest
    first when descending
--]]

local function items(entries: Entries, now: number, descending: boolean): { Item }
	local listed: { Item } = {}
	for key: string, entry: Entry in entries do
		if entry.value ~= nil and (entry.expiresAt :: number) > now then
			table.insert(listed, {
				key = key,
				value = Store.copy(entry.value),
				sortKey = entry.sortKey :: number,
				expiresAt = entry.expiresAt :: number,
			})
		end
	end

	-- Descending swaps the pair rather than negating, since a sort's order must stay strict
	table.sort(listed, function (a: Item, b: Item): boolean
		local first: Item, second: Item = a, b
		if descending then
			first, second = b, a
		end

		return first.sortKey < second.sortKey or (first.sortKey == second.sortKey and first.key < second.key)
	end)

	return listed
end

--[[
    Builds a MemoryStoreService over the given maps, whose entries expire
    and whose delays wait on the given clock
--]]

function MemoryStoreService.new(maps: Maps, clock: Clock): MemoryStoreService
	local faults: Faults.Faults = Faults.new("MemoryStoreService", METHODS, clock.task.wait)

	return {
		failNext = faults.failNext,
		delayNext = faults.delayNext,
		rerunNext = faults.rerunNext,

		GetSortedMap = function (_: any, name: string): { [string]: any }
			if #name > MAX_LENGTH then
				error("InvalidParameter: The provided sorted map name is not valid.", 0)
			end

			local entries: Entries = maps[name] or {}
			maps[name] = entries

			return {
				UpdateAsync = function (
					_: any,
					key: string | number,
					transform: (any, number?) -> (any, number | nil),
					expiration: number
				): (any, number | nil)
					local keyName: string = keyed(key)
					if not (expiration > 0 and expiration <= MAX_EXPIRATION) then
						error(
							`The expiration {expiration} is outside the 0 to {MAX_EXPIRATION} seconds an entry lives`,
							0
						)
					end

					local written: Entry? = Store.update(entries, keyName, faults, function (read: Entry?): Entry | nil
						local value: any, sortKey: number?
						if read and read.value ~= nil and (read.expiresAt :: number) > clock.now() then
							value, sortKey = transform(Store.copy(read.value), read.sortKey)
						else
							value, sortKey = transform(nil, nil)
						end

						if value == nil then
							return nil
						end

						local size: number = #serde.encode("json", value)
						if size > MAX_VALUE then
							error(`The value for {keyName} is {size} bytes, past the {MAX_VALUE} a sorted map holds`, 0)
						end

						-- Whiteoak TODO: numeric sort keys only; add string and missing ones, in the
						-- engine's order, once a unit writes one
						if type(sortKey) ~= "number" then
							error(`The fake sorted map sorts by number, not by the {type(sortKey)} {keyName} gave`, 0)
						end

						return { value = Store.copy(value), sortKey = sortKey }
					end)

					if not written then
						return nil, nil
					end

					-- An entry's life runs from when its write lands
					written.expiresAt = clock.now() + expiration

					return Store.copy(written.value), written.sortKey
				end,

				-- Whiteoak TODO: no exclusive bounds; add them once a read pages past the first range
				GetRangeAsync = function (_: any, direction: any, count: number, lower: any, upper: any): { any }
					if not (count >= 1 and count <= MAX_RANGE and count % 1 == 0) then
						error(`GetRangeAsync takes a count of 1 to {MAX_RANGE}, not {count}`, 0)
					end

					assert(lower == nil and upper == nil, "The fake sorted map reads no range bounds")

					local descending: boolean = direction == roblox.Enum.SortDirection.Descending
					assert(
						descending or direction == roblox.Enum.SortDirection.Ascending,
						`GetRangeAsync takes an Enum.SortDirection, not {direction}`
					)

					faults.spend("GetRangeAsync")

					local range: { any } = {}
					for _, item: Item in items(entries, clock.now(), descending) do
						if #range == count then
							break
						end

						table.insert(range, { key = item.key, value = item.value, sortKey = item.sortKey })
					end

					return range
				end,

				RemoveAsync = function (_: any, key: string | number)
					local keyName: string = keyed(key)
					faults.spend("RemoveAsync")

					entries[keyName] = {}
				end,
			}
		end,

		peek = function (map: string): { Item }
			local descending: boolean = true -- Highest first, as a board reads its rows

			return items(maps[map] or {}, clock.now(), descending)
		end,
	}
end

return MemoryStoreService
