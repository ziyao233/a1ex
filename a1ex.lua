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

local mSession		= require "a1ex.session";

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

	return cfg;
end

local cfg = parseConfiguration();
local connection = mCURL.easy{
				url			= cfg.endpoint,
				httpheader		= {
					"Content-type: application/json",
					("Authorization: Bearer %s"):
					format(cfg.apiKey),
				},
				[mCURL.OPT_POST]	= true,
			     };

if os.getenv("DEBUG_CURL_REQUEST") then
	connection:setopt(mCURL.OPT_VERBOSE, true);
end

local session = mSession.session();
for k, v in pairs(cfg.arguments or {}) do
	session:setArgument(k, v);
end

io.stdout:write("> ");
io.stdout:flush();
for line in io.lines() do

	local req = session:generateRequest(line);
	local written;
	local readf = function()
		if not written then
			written = true;
			return req;
		end
	end;
	connection:setopt_readfunction(readf);

	local repBuf = {};
	local writef = function(t)
		table.insert(repBuf, t);
		return true;
	end
	connection:setopt_writefunction(writef);

	local ok, err = pcall(connection.perform, connection);
	if not ok then
		perror("Failed to request the server: %s", ret);
	end

	local rep = table.concat(repBuf);
	local errcode = connection:getinfo(mCURL.INFO_RESPONSE_CODE);
	if errcode ~= 200 then
		perror("Server responds with error code %d: %s",
		       errcode, rep);
	end

	local msg, err = session:parseResponse(rep);
	if not msg then
		perror("Failed to parse server response: %s", err);
	end

	if msg.reasoningContent then
		print("[REASONING] " .. msg.reasoningContent);
	end

	print("[ASSISTANT] " .. msg.content);

	io.stdout:write("> ");
	io.stdout:flush();
end
