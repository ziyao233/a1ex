#!/usr/bin/env lua5.4
-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	a1ex.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local io		= require "io";
local os		= require "os";

local mHttp		= require "a1ex.http";
local mInteraction	= require "a1ex.interaction";
local mSession		= require "a1ex.session";
local mTools		= require "a1ex.tools";

local function
pwarn(fmt, ...)
	io.stderr:write((fmt .. "\n"):format(...));
end

local function
perror(fmt, ...)
	pwarn(fmt, ...);
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

	if ret.hideReasoning then
		cfg.hideReasoning = checkCfg(ret, "hideReasoning", "boolean");
	end

	if ret.pretty then
		cfg.pretty = checkCfg(ret, "pretty", "function");
	end

	return cfg;
end

local function
printHelp(arg0)
	io.stderr:write(([[
Usage: %s [options]

Options:
	--help			Print this help
	--hide-reasoning
	--display-reasoning	Display reasoning content or not, overrides
				hideReasoning in configuration
	--detailed-usage	Show cumulative usage among each turn of
				API calls
]]):format(arg0));
end

local function
parseArguments(arg)
	local cfg = {};

	local i = 1;
	while i <= #arg do
		if arg[i] == "--hide-reasoning" then
			cfg.hideReasoning = true;
		elseif arg[i] == "--display-reasoning" then
			cfg.hideReasoning = false;
		elseif arg[i] == "--detailed-usage" then
			cfg.detailedUsage = true;
		elseif arg[i] == "--help" then
			printHelp(arg[0]);
			os.exit(0);
		else
			pwarn("Unrecognized option %s", arg[i]);
			printHelp(arg[0]);
			os.exit(1);
		end

		i = i + 1;
	end

	return cfg;
end

local cfgArgs = parseArguments(arg);
local cfg = parseConfiguration();

for k, v in pairs(cfgArgs) do
	cfg[k] = v;
end

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

mInteraction.init();

if cfg.pretty then
	mInteraction.setPretty(cfg.pretty);
end

local function
onRetry(count, statusCode, rep)
	mInteraction.pretty("warning", ("Server responds with error code %d: %s"):
				       format(statusCode, rep));
	mInteraction.pretty("warning", ("Retrying (count %d)"):format(count));
end

local function
showUsage(session)
	if not session.compTokens then
		mInteraction.pretty("info", "Session usage unavailable");
		return;
	end

	local cacheInfo = "";
	if session.promptTokens ~= 0 and session.cachedTokens then
		local rate = session.cachedTokens * 100 /
			     session.promptTokens;
		cacheInfo = (" (%d cached, %.1f%%)"):
			    format(session.cachedTokens, rate);
	end

	local total = session.promptTokens + session.compTokens;
	mInteraction.pretty("info",
			    ("Session usage: %d input%s, %d output, %d in total"):
			    format(session.promptTokens, cacheInfo,
			    	   session.compTokens, total));
end

local finishReason, msg = "stop";
while true do
	if finishReason == "stop" then
		local line = mInteraction.readline();
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
	local ok, statusCode, rep = connection:requestWithRetry(req, 5, 5,
				    onRetry);
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

	if msg.reasoningContent and msg.reasoningContent ~= "" and
	   not cfg.hideReasoning then
		mInteraction.pretty("reasoning", msg.reasoningContent);
	end

	if msg.content and msg.content ~= "" then
		mInteraction.pretty("assistant", msg.content);
	end

	if cfg.detailedUsage then
		showUsage(session);
	end
end

::exit::

if not cfg.detailedUsage then
	showUsage(session);
end
