-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/http.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local table		= require "table";

local mCURL		= require "cURL";

local metaConnection = {};
metaConnection.__index = metaConnection;

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

	obj.handle:setopt_writefunction(writeFunction, obj);

	return setmetatable(obj, metaConnection);
end


function
metaConnection.request(self, body)
	assert(body);

	if body then
		self.handle:setopt(mCURL.OPT_POSTFIELDS, body);
	end

	self.buf = {};

	local ok, err = pcall(self.handle.perform, self.handle);
	if not ok then
		return false, 0, err;
	end

	local statusCode = self.handle:getinfo(mCURL.INFO_RESPONSE_CODE);
	local response = table.concat(self.buf);

	-- Close the reference so the buffer could be collected as soon as
	-- possible.
	self.buf = nil;

	return true, statusCode, response;
end

return {
	connection	= connection,
};
