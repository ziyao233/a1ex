-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/tools/read.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local io		= require "io";
local math		= require "math";
local table		= require "table";

local parameters = {
	type		= "object",
	properties	= {
		path = {
			type		= "string",
			description	= "File path to read",
		},

		offset = {
			type		= "integer",
			description	= "Line number to start from (1-indexed)",
			default		= 1,
		},

		limit = {
			type		= "integer",
			description	= "Maximum number of lines to read",
			default		= 2000,
		},


	},
	required = { "path" },
	additionalProperties = false,
};

local definition = {
	type		= "function",
	["function"]	= {
		name		= "read",
		description	= "Read content from a file",
		parameters	= parameters,
	},
};

local function
process(arg)
	if not arg.path then
		return "Missing 'path' argument";
	end

	local path = arg.path;
	if type(path) ~= "string" then
		return "Wrong type for 'path' argument, expect string";
	end

	local offset = 1;
	if arg.offset then
		offset = arg.offset;

		if type(offset) ~= "number" or
		   not math.tointeger(offset) then
			return "Wrong type for 'offset' argument, expect integer";
		end

		if offset < 1 then
			return "Invalid offset, it must be greater than zero";
		end
	end

	local limit = 2000;
	if arg.limit then
		limit = arg.limit;

		if type(limit) ~= "number" or
		   not math.tointeger(limit) then
			return "Wrong type for 'limit' argument, expect integer";
		end

		if limit < 1 then
			return "Invalid limit, it must be greater than zero";
		end
	end

	print(("[TOOL] Reading '%s' line %d - %d"):
	      format(path, offset, offset + limit - 1));

	local file, msg = io.open(path, "r");
	if not file then
		return "Failed to open file: " .. msg;
	end

	local buf = {};
	local count = 1;
	for line in file:lines("l") do
		if count >= offset + limit then
			goto done;
		elseif count >= offset then
			table.insert(buf, line);
		end

		count = count + 1;
	end

::done::
	file:close();

	return table.concat(buf, '\n');
end

return {
	definition	= definition,
	process		= process,
};
