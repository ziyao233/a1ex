-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/session.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local math			= require "math";

local mCjson			= require "cjson";

--[[
-- I definitely missed a lot of type guards in this totally handwritten parser,
-- before implementing Response API or anything complicated, we should have a
-- generic schema-based verifier. For simplicity, let's ignore some checks.
--]]

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
	assert(role == "system" or role == "user" or role == "assistant" or
	       role == "tool",
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

function
metaSession.registerTools(self, definitions)
	self.tools = definitions;
end

local function
nullable(value)
	if value == mCjson.null then
		return nil;
	end

	return value;
end

local function
parseMessage(self, rawMsg)
	local role = rawMsg.role;

	if type(role) ~= "string" then
		return false, "missing role in reply or it's in wrong type";
	end

	if role ~= "assistant" then
		return false, "invalid role in reply";
	end

	if type(rawMsg.content) ~= "string" and
	   rawMsg.content ~= mCjson.null and
	   rawMsg.content ~= nil then
		return false, "missing content in reply or it's in wrong type";
	end

	local toolCalls;
	if rawMsg.tool_calls and rawMsg.tool_calls ~= mCjson.null then
		if type(rawMsg.tool_calls) ~= "table" then
			return false, "invalid type for tool_calls";
		end

		if #rawMsg.tool_calls == 0 then
			return false, "finished with tool_calls but no tool is called";
		end

		toolCalls = {};
		for _, call in ipairs(rawMsg.tool_calls) do
			if type(call.id) ~= "string" then
				return false, "invalid type for tool call ID";
			end

			if type(call.type) ~= "string" or
			   call.type ~= "function" then
				return false, "invalid tool call type";
			end

			local func = call["function"];
			if type(func) ~= "table" or
			   type(func.name) ~= "string" or
			   type(func.arguments) ~= "string" then
				return false, "invalid tool call function";
			end

			table.insert(toolCalls, {
				id	= call.id,
				type	= call.type,
				func	= {
					name		= func.name,
					arguments	= func.arguments,
				},
			});
		end
	end

	local msg = {
			role			= role,
			content 		= nullable(rawMsg.content),
			reasoningContent	= nullable(rawMsg.reasoning_content),
			toolCalls		= toolCalls,
		    };
	self:appendMessage(msg);

	return msg;
end

local function
isInteger(x)
	return type(x) == "number" and math.tointeger(x);
end

local function
parseUsage(self, usage)
	local completion = usage.completion_tokens;
	if not isInteger(completion) then
		return false, "invalid/missing completion_tokens";
	end

	local prompt = usage.prompt_tokens;
	if not isInteger(prompt) then
		return false, "invalid/missing prompt_tokens";
	end

	local promptDetails = usage.prompt_tokens_details;
	if promptDetails then
		if type(promptDetails) ~= "table" then
			return false, "invalid type for prompt_tokens_details";
		end

		local cached = nullable(promptDetails.cached_tokens);
		-- OpenAI's schema mandates cached_tokens when
		-- prompt_tokens_details, but it's said that there're 3rd-party
		-- implementations violating this.
		if cached then
			if not isInteger(cached) then
				return false, "invalid type for cached_tokens";
			end

			self.cachedTokens = (self.cachedTokens or 0) + cached;
		end
	end

	self.compTokens = (self.compTokens or 0) + completion;
	self.promptTokens = (self.promptTokens or 0) + prompt;

	return true;
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

	local finishReason = response.choices[1].finish_reason;
	if type(finishReason) ~= "string" then
		return invalidResponse
				"missing finish_reason or it's in wrong type";
	end

	local msg, err = parseMessage(self, response.choices[1].message);
	if not msg then
		return invalidResponse(err);
	end

	local usage = nullable(response.usage);
	if usage then
		if type(usage) ~= "table" then
			return invalidResponse "invalid usage";
		end

		local ok, err = parseUsage(self, usage);
		if not ok then
			return invalidResponse(err);
		end
	end

	return msg, finishReason;
end

function
metaSession.appendUser(self, prompt)
	self:appendMessage{
		role	= "user",
		content	= prompt,
	};
end

function
metaSession.appendTool(self, toolCallID, content)
	self:appendMessage{
		role		= "tool",
		toolCallID	= toolCallID,
		content		= content,
	};
end

function
metaSession.generateRequest(self)
	local req = {
		messages	= {},
		tools		= self.tools,
	};

	for i, msg in ipairs(self.messages) do
		local toolCalls;
		if msg.toolCalls then
			toolCalls = {};

			for _, call in ipairs(msg.toolCalls) do
				table.insert(toolCalls, {
					id	= call.id,
					type	= call.type,
					["function"] = {
						name		= call.func.name,
						arguments	= call.func.arguments,
					},
				});
			end
		end

		req.messages[i] = {
			role			= msg.role,
			content			= msg.content,
			reasoning_content	= msg.reasoningContent,
			tool_call_id		= msg.toolCallID,
			tool_calls		= toolCalls,
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
