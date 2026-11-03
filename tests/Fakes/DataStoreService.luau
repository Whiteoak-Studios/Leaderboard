--[[
    A fake DataStoreService over data two servers can share: standard and
    ordered stores with the real name, key and value limits, and the peek
    readers a case checks them with
--]]

--!strict
local Faults = require("./Faults")
local Store = require("./Store")

local MAX_LENGTH: number = 50 -- Characters in a store name or a key, on both kinds
local MAX_PAGE: number = 100 -- Entries one GetSortedAsync page holds
local METHODS: { string } = { "UpdateAsync", "RemoveAsync", "GetSortedAsync" }

type Entry = Store.Entry
type Entries = { [string]: Entry }
type Row = { key: string, value: number }

export type Data = {
	standard: { [string]: Entries },
	ordered: { [string]: Entries },
}

export type DataStoreService = {
	GetDataStore: (self: any, name: string) -> { [string]: any },
	GetOrderedDataStore: (self: any, name: string) -> { [string]: any },
	failNext: (method: string, count: number?) -> (),
	delayNext: (method: string, seconds: number) -> (),
	rerunNext: (method: string) -> (),
	peek: (store: string, key: string | number) -> any,
	peekOrdered: (store: string, key: string | number) -> number | nil,
}

local DataStoreService = {}

--[[
    The entries of one store by name, refused past 50 characters as both
    kinds refuse it
--]]

local function named(stores: { [string]: Entries }, name: string): Entries
	if #name > MAX_LENGTH then
		error("DataStore name is too long", 0)
	end

	local entries: Entries = stores[name] or {}
	stores[name] = entries

	return entries
end

--[[
    A key as the store reads it, a number passed as its digits, refused
    past 50 characters
--]]

local function keyed(key: string | number): string
	assert(type(key) == "string" or type(key) == "number", `A store key is a string, not a {type(key)}`)

	local text: string = tostring(key)
	if #text > MAX_LENGTH then
		error("102: Key name exceeds the 50 character limit.", 0)
	end

	return text
end

--[[
    An ordered store keeps integers only, and refuses a fraction or an
    infinity before any request
--]]

local function checkInteger(value: any)
	if type(value) ~= "number" or value % 1 ~= 0 then
		error("103: double is not allowed in data stores.", 0)
	end
end

--[[
    Builds a DataStoreService over the given data, waiting on the clock's
    wait for any delay a case queues
--]]

function DataStoreService.new(data: Data, sleep: (seconds: number?) -> number): DataStoreService
	local faults: Faults.Faults = Faults.new("DataStoreService", METHODS, sleep)

	--[[
	    Removes a key as both kinds do, leaving an empty entry, so the
	    removal counts as a write
	--]]

	local function remove(entries: Entries, key: string | number): any
		local name: string = keyed(key)
		faults.spend("RemoveAsync")

		local removed: Entry? = entries[name]
		entries[name] = {}

		return removed and Store.copy(removed.value)
	end

	return {
		failNext = faults.failNext,
		delayNext = faults.delayNext,
		rerunNext = faults.rerunNext,

		GetDataStore = function (_: any, name: string): { [string]: any }
			local entries: Entries = named(data.standard, name)

			return {
				UpdateAsync = function (_: any, key: string | number, transform: (any, any) -> any): (any, any)
					local written: Entry? = Store.update(
						entries,
						keyed(key),
						faults,
						function (read: Entry?): Entry | nil
							local value: any = transform(Store.copy(read and read.value), nil)
							if value == nil then
								return nil
							end

							return { value = Store.copy(value) }
						end
					)

					if not written then
						return nil, nil
					end

					return Store.copy(written.value), nil
				end,

				RemoveAsync = function (_: any, key: string | number): (any, any)
					return remove(entries, key), nil
				end,
			}
		end,

		GetOrderedDataStore = function (_: any, name: string): { [string]: any }
			local entries: Entries = named(data.ordered, name)

			return {
				UpdateAsync = function (
					_: any,
					key: string | number,
					transform: (number?) -> number | nil
				): number | nil
					local written: Entry? = Store.update(
						entries,
						keyed(key),
						faults,
						function (read: Entry?): Entry | nil
							local value: number? = transform(read and read.value)
							if value == nil then
								return nil
							end

							checkInteger(value)

							return { value = value }
						end
					)

					return written and written.value
				end,

				-- Whiteoak TODO: one page, no AdvanceToNextPageAsync; add it once a read walks past the first page
				GetSortedAsync = function (
					_: any,
					ascending: boolean,
					pageSize: number,
					minValue: number?,
					maxValue: number?
				): { [string]: any }
					if not (pageSize >= 1 and pageSize <= MAX_PAGE and pageSize % 1 == 0) then
						error(`GetSortedAsync takes a page size of 1 to {MAX_PAGE}, not {pageSize}`, 0)
					end

					faults.spend("GetSortedAsync")

					local rows: { Row } = {}
					for key: string, entry: Entry in entries do
						local value: number? = entry.value
						if value and value >= (minValue or -math.huge) and value <= (maxValue or math.huge) then
							table.insert(rows, { key = key, value = value })
						end
					end

					-- Descending swaps the pair rather than negating, since a sort's order must stay strict
					table.sort(rows, function (a: Row, b: Row): boolean
						local first: Row, second: Row = a, b
						if not ascending then
							first, second = b, a
						end

						return first.value < second.value or (first.value == second.value and first.key < second.key)
					end)

					local page: { Row } = table.move(rows, 1, math.min(#rows, pageSize), 1, {})

					return {
						IsFinished = #rows <= pageSize,

						GetCurrentPage = function (_: any): { Row }
							return page
						end,
					}
				end,

				RemoveAsync = function (_: any, key: string | number): number | nil
					return remove(entries, key)
				end,
			}
		end,

		peek = function (store: string, key: string | number): any
			local entry: Entry? = (data.standard[store] or {})[tostring(key)]

			return entry and Store.copy(entry.value)
		end,

		peekOrdered = function (store: string, key: string | number): number | nil
			local entry: Entry? = (data.ordered[store] or {})[tostring(key)]

			return entry and entry.value
		end,
	}
end

return DataStoreService
