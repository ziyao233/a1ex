#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	a1ex.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local io		= require "io";
local os		= require "os";
local table		= require "table";

local mCURL		= require "cURL";

local mHttp		= require "a1ex.http";
local mSession		= require "a1ex.session";
local mTools		= require "a1ex.tools";

local function
perror(fmt, ...)
	io.stderr:write((fmt .. "\n"):format(...));
	os.exit(1);
end

local function
checkCfg(cfg, k, t)
	if type(cfg[k]) == t then
		return cfg[k];
	end

	perror("Invalid configuration property %s: expecting %s, got %s", k,
	       t, type(cfg[k]));
end

local function
parseConfiguration()
	local home = os.getenv("HOME")
	if not home then
		perror("$HOME is not set");
	end

	local cfgPath = home .. "/.config/a1ex/a1ex.lua";
	local cfgFile, msg = io.open(cfgPath, "r");
	if not cfgFile then
		perror("Failed to open %s as configuration: %s", cfgPath, msg);
	end

	local env = {};
	setmetatable(env, { __index = _G });
	env._G = env;
	local fcfg, msg = load(cfgFile:read("a"), cfgPath, "t", env);
	if not fcfg then
		perror("Failed to parse configuration: %s", msg);
	end

	cfgFile:close();

	local ok, ret = pcall(fcfg);
	if not ok then
		perror("Failed to evaluate configuration: %s", ret);
	end

	local cfg = {
		endpoint	= checkCfg(ret, "endpoint", "string"),
		apiKey		= checkCfg(ret, "apiKey", "string"),
	};

	if ret.arguments then
		cfg.arguments = checkCfg(ret, "arguments", "table");
	end

	if ret.prompt then
		cfg.prompt = checkCfg(ret, "prompt", "string");
	end

	return cfg;
end

local cfg = parseConfiguration();
local connection = mHttp.connection(cfg.endpoint, {
	"Content-type: application/json",
	("Authorization: Bearer %s"):format(cfg.apiKey),
	"User-agent: a1ex",
});

local session = mSession.session();
for k, v in pairs(cfg.arguments or {}) do
	session:setArgument(k, v);
end

session:registerTools(mTools.definitions);

if cfg.prompt then
	session:setSystemPrompt(cfg.prompt);
end

local finishReason, msg = "stop";
while true do
	if finishReason == "stop" then
		io.stdout:write("> ");
		io.stdout:flush();

		local line = io.stdin:read("l");
		if not line then
			goto exit;
		end

		session:appendUser(line);
	elseif finishReason == "tool_calls" then
		for _, call in ipairs(msg.toolCalls) do
			session:appendTool(call.id,
					   mTools.process(call));
		end
	else
		perror("Invalid finish reason %s", finishReason);
	end

	local req = session:generateRequest();
	local ok, statusCode, rep = connection:request(req);
	if not ok then
		perror("Failed to request the server: %s", rep);
	end

	if statusCode ~= 200 then
		perror("Server responds with error code %d: %s",
		       statusCode, rep);
	end

	local err;
	msg, finishReason = session:parseResponse(rep);
	if not msg then
		perror("Failed to parse server response: %s", finishReason);
	end

	if msg.reasoningContent and msg.reasoningContent ~= "" then
		print("[REASONING] " .. msg.reasoningContent);
	end

	if msg.content and msg.content ~= "" then
		print("[ASSISTANT] " .. msg.content);
	end
end

::exit::

io.stdout:write('\n');
