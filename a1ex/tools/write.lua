-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/tools/write.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local io		= require "io";

local parameters = {
	type		= "object",
	properties	= {
		path	= {
			type		= "string",
			description	= "File path to write",
		},

		content = {
			type		= "string",
			description	= "Content to write",
		},
	},
	required = { "path", "content" },
	additionalProperties = false,
};

local definition = {
	type		= "function",
	["function"]	= {
		name		= "write",
		description	= "Write content to a file, overwriting if " ..
				  "the path exists. It doesn't " ..
				  "create leading directories automatically",
		parameters	= parameters,
	},
};

local function
process(arg)
	local path = arg.path;
	if not path then
		return "Missing 'path' argument";
	end

	if type(path) ~= "string" then
		return "Wrong type for 'path' argument, expect string";
	end

	local content = arg.content;
	if not content then
		return "Missing 'content' argument";
	end

	if type(content) ~= "string" then
		return "Wrong type for 'content' argument, expect string";
	end

	print(("[TOOL] Writing '%s'"):format(path));

	local file <close>, msg = io.open(path, "wb");
	if not file then
		return "Failed to open file: " .. msg;
	end

	local ok, msg = file:write(content);
	if not ok then
		return "Failed to write to the file: " .. msg;
	end

	local ok, msg = file:close();
	if not ok then
		return "Failed to write to the file: " .. msg;
	end

	return "ok";
end

return {
	definition	= definition,
	process		= process,
};
