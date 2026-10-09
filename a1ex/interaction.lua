-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/interaction.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local io		= require "io";
local os		= require "os";

local mCffi		= require "cffi";
local mTermio		= require "posix.termio";
local mUnistd		= require "posix.unistd";

local getline, isTerm;

--[[
-- libreadline sets the soversion based on its major version, it's said that
-- between Readline 6 and Readline 8, there's no ABI breakage.
--
-- However, readline 8 was released in Jan 2019 while Lua 5.4 was release in
-- Jun 2020, so a system comes with Lua 5.4 unlikely ships readline 7 or
-- earlier. Let's be simple, until someone complains (or readline 9 is
-- released).
--
-- Note Lua interpreters might link to libreadline, too, which might cause
-- conflicts if the interpreter links a different version. Let's ignore it for
-- now.
--]]
local function
init()
	isTerm = mUnistd.isatty(mUnistd.STDIN_FILENO);

	local ok, cReadline;
	if isTerm then
		ok, cReadline = pcall(mCffi.load, "libreadline.so.8");
	end

	if not ok or not isTerm or os.getenv("DEBUG_NOREADLINE") then
		if not ok and isTerm then
			io.stderr:write(("Failed to load libreadline.so.8: %s\n"):
					format(cReadline));
			io.stderr:write("Falling back to simple IO\n");
		end

		getline = function()
			if isTerm then
				io.stdout:write("> ");
				io.stdout:flush();
			end

			return io.stdin:read("l");
		end;
	else
		mCffi.cdef([[
			char *readline(const char *prompt);
			void free(void *p);
		]]);

		getline = function()
			local cLine = cReadline.readline("> ");
			if cLine == mCffi.nullptr then
				return nil;
			end

			local line = mCffi.string(cLine);

			mCffi.C.free(cLine);

			return line;
		end;
	end
end

local function
readline()
	local line, attr;

	if isTerm then
		local msg;
		attr, msg = mTermio.tcgetattr(mUnistd.STDIN_FILENO);
		assert(attr, msg);

		local oldVINTR = attr.cc[mTermio.VINTR];

		attr.cc[mTermio.VINTR] = mUnistd._PC_VDISABLE;
		mTermio.tcsetattr(mUnistd.STDIN_FILENO, mTermio.TCSANOW, attr);

		attr.cc[mTermio.VINTR] = oldVINTR;
	end

	repeat
		line = getline();

		if not line then
			goto exit;
		end
	until line ~= "";

::exit::
	if isTerm then
		mTermio.tcsetattr(mUnistd.STDIN_FILENO, mTermio.TCSANOW, attr);
	end

	return line;
end

return {
	init		= init,
	readline	= readline,
};
