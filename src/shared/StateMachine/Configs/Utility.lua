-- ReplicatedStorage/StateMachine/Configs/Utility.lua

local Utility = {}

-- A generic, recursive deep copy function for tables.
-- Handles tables containing other tables, functions, and primitive values.
function Utility.deepCopy(original)
	local copy = {}

	-- Check for infinite recursion (self-reference) in the root table
	local seen = {}

	local function copyTable(tbl)
		-- If it's not a table, return the value immediately (handles numbers, strings, functions, nil, etc.)
		if type(tbl) ~= "table" then
			return tbl
		end

		-- Check if we've already copied this table to prevent infinite loops (for circular references)
		if seen[tbl] then
			return seen[tbl]
		end

		local newTable = {}
		seen[tbl] = newTable -- Mark the new table as the copy for the original

		-- Iterate through all keys (both array and dictionary parts)
		for key, value in pairs(tbl) do
			-- Recursively copy the value
			newTable[copyTable(key)] = copyTable(value)
		end

		return newTable
	end

	-- Start the recursion from the original table
	return copyTable(original)
end

return Utility