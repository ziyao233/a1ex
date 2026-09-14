-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/tools.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local os		= require "os";
local table		= require "table";

local mCjson		= require "cjson";

local toolNames = {
	"bash", "write",
};

local definitions, tools = {}, {};
for _, name in pairs(toolNames) do
	tools[name] = require("a1ex.tools." .. name);
	table.insert(definitions, tools[name].definition);
end

local debugPrint;
if os.getenv("DEBUG_TOOLS") then
	debugPrint = function(s)
		print(s);
		return s;
	end;
else
	debugPrint = function(s)
		return s;
	end;
end

local function
process(call)
	local ok, arg = pcall(mCjson.decode, call.func.arguments);
	if not ok then
		return "Failed to decode arguments as JSON: " .. arg;
	end

	if type(arg) ~= "table" then
		return "Tool call arguments aren't an object";
	end

	local tool = tools[call.func.name];
	if not tool then
		return ("Tool '%s' not found"):format(call.func.name);
	end

	return debugPrint(tool.process(arg));
end

return {
	definitions	= definitions,
	process		= process,
       };
