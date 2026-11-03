--[[
    What the store fakes share: a deep copy, since a store never holds the
    table its caller holds, and UpdateAsync's read, commit and re-run
--]]

--!strict
local Faults = require("./Faults")

type Faults = Faults.Faults

export type Entry = {
	value: any, -- Nil once removed, so a removal still counts as a write
	sortKey: number?,
	expiresAt: number?,
}

local Store = {}

--[[
    Copies a value all the way down, as a store serializes what it is given
--]]

function Store.copy(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local copied: { [any]: any } = {}
	for key: any, item: any in value do
		copied[key] = Store.copy(item)
	end

	return copied
end

--[[
    Runs one UpdateAsync over a store's entries: reads the key, transforms
    it, spends the method's delay and failure, then commits only if the key
    still holds what it read, re-running the transform otherwise, as the
    real store does. A transform that gives nil cancels the write
--]]

function Store.update(
	entries: { [string]: Entry },
	key: string,
	faults: Faults,
	transform: (read: Entry?) -> Entry | nil
): Entry | nil
	local read: Entry? = entries[key]
	local written: Entry? = transform(read)
	faults.spend("UpdateAsync")

	-- A write that landed during the delay, or a re-run the case forced
	while written and (entries[key] ~= read or faults.rerun()) do
		read = entries[key]
		written = transform(read)
	end

	if written then
		entries[key] = written
	end

	return written
end

return Store
