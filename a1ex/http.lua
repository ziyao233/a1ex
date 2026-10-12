-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/http.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local os		= require "os";
local table		= require "table";

local mCURL		= require "cURL";
local mUnistd		= require "posix.unistd";

local metaConnection = {};
metaConnection.__index = metaConnection;

local debugPrint;
if os.getenv("DEBUG_HTTP") then
	debugPrint = print;
else
	debugPrint = function() end;
end

local function
writeFunction(self, data)
	table.insert(self.buf, data);
	return true;
end

local function
connection(url, headers)
	local obj = {
		handle = mCURL.easy{
			url		= url,
			httpheader	= headers,
		},
	};

	obj.handle:setopt(mCURL.OPT_FOLLOWLOCATION, true);

	obj.handle:setopt_writefunction(writeFunction, obj);

	return setmetatable(obj, metaConnection);
end


function
metaConnection.request(self, body)
	if body then
		self.handle:setopt(mCURL.OPT_POSTFIELDS, body);
	end

	self.buf = {};

	debugPrint(body);
	local ok, err = pcall(self.handle.perform, self.handle);
	if not ok then
		return false, 0, err;
	end

	local statusCode = self.handle:getinfo(mCURL.INFO_RESPONSE_CODE);
	local response = table.concat(self.buf);
	debugPrint(response);

	-- Close the reference so the buffer could be collected as soon as
	-- possible.
	self.buf = nil;

	return true, statusCode, response;
end

local function
suitableForRetry(code)
	return code == 408 or code == 429 or
	       ((code >= 500 and code < 600) and code ~= 501);
end

function
metaConnection.requestWithRetry(self, body, attempts, delay, onRetry)
	onRetry = onRetry or function() end;

	local ok, statusCode, rep;
	local count = 0;
	repeat
		if count ~= 0 then
			onRetry(count, statusCode, rep);

			local retryAfter = self.handle:getinfo(mCURL.INFO_RETRY_AFTER);
			if retryAfter > 0 then
				debugPrint(("Resetting retry delay to %d"):
					   format(retryAfter));
				delay = retryAfter;
			end

			mUnistd.sleep(delay);
			delay = delay * 2;
		end

		ok, statusCode, rep = self:request(body);
		if ok and not suitableForRetry(statusCode) then
			break;
		end

		count = count + 1;
	until count >= attempts;

	return ok, statusCode, rep;
end

return {
	connection	= connection,
};
