-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/session.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local mCjson			= require "cjson";

local metaSession = {};
metaSession.__index = metaSession;

local function
session()
	return setmetatable({
				messages	= {},
				nMessages	= 0,
				extraArgs	= {},
			    }, metaSession);
end

function
metaSession.appendMessage(self, msg)
	local role = msg.role;
	assert(role == "system" or role == "user" or role == "assistant",
	       ("Invalid message role '%s'"):format(role));

	self.nMessages = self.nMessages + 1;
	self.messages[self.nMessages] = msg;
end

function
metaSession.setArgument(self, key, value)
	self.extraArgs[key] = value;
end

function
metaSession.setSystemPrompt(self, prompt)
	assert(self.nMessages == 0,
	       "Setting system prompt during conversation");

	self:appendMessage{ role = "system", content = prompt };
end

local function
parseMessage(self, rawMsg)
	local role = rawMsg.role;

	if type(role) ~= "string" then
		return false, "missing role in reply";
	end

	if role ~= "assistant" then
		return false, "invalid role in reply";
	end

	if type(rawMsg.content) ~= "string" then
		return false, "missing content in reply";
	end

	local msg = {
			role			= role,
			content 		= rawMsg.content,
			reasoningContent	= rawMsg.reasoning_content,
		    };
	self:appendMessage(msg);

	return msg;
end

function
metaSession.parseResponse(self, rawResponse)
	local invalidResponse = function(reason)
		return false, ("Invalid/unsupported server response, %s: %s\n"):
			      format(reason, rawResponse);
	end;

	local ok, response = pcall(mCjson.decode, rawResponse);
	if not ok then
		return invalidResponse "failed to decode as JSON";
	end

	if type(response.choices) ~= "table" or #response.choices < 1 then
		return invalidResponse "missing choices";
	end

	if type(response.choices[1]) ~= "table" then
		return invalidResponse "invalid choice";
	end

	local msg, err = parseMessage(self, response.choices[1].message);
	if not msg then
		return invalidResponse(err);
	end

	return msg;
end

function
metaSession.generateRequest(self, prompt)
	local msg = {
			role = "user",
			content = prompt,
		    };
	self:appendMessage(msg);

	local req = {
		messages = {},
	};

	for i, msg in ipairs(self.messages) do
		req.messages[i] = {
			role			= msg.role,
			content			= msg.content,
			reasoning_content	= msg.reasoningContent,
		};
	end

	for k, v in pairs(self.extraArgs) do
		req[k] = v;
	end

	return mCjson.encode(req);
end

return {
	session		= session,
};
