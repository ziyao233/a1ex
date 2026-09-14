-- SPDX-License-Identifier: MPL-2.0
--[[
--	a1ex
--	src/tools/bash.lua
--	Copyright (C) 2026 Yao Zi <me@ziyao.cc>
--]]

local io		= require "io";
local math		= require "math";
local table		= require "table";

local mSignal		= require "posix.signal";
local mStdio		= require "posix.stdio";
local mUnistd		= require "posix.unistd";
local mWait		= require "posix.sys.wait";


--[[ TODO: Support command timeout ]]
local parameters = {
	type		= "object",
	properties	= {
		command	= {
			type		= "string",
			description	= "Command to be executed by bash"
		},

		timeout = {
			type		= "integer",
			default		= 300,
			description	= "Timeout in seconds, zero to disable"
		},
	},
	required = { "command" },
	additionalProperties = false,
};

local definition = {
	type		= "function",
	["function"]	= {
		name		= "bash",
		description	= "Execute commands with bash",
		parameters	= parameters,
	},
};

local function
runWithTimeout(command, timeout)
	timeout = timeout == 0 and 2^31 or timeout;

	local cmdR, cmdW = mUnistd.pipe();
	local outputR, outputW = mUnistd.pipe();

	local pid, errmsg = mUnistd.fork();
	if pid == nil then
		mUnistd.close(cmdR);
		mUnistd.close(cmdW);
		mUnistd.close(outputR);
		mUnistd.close(outputW);

		return "Failed to fork a process: " .. errmsg;
	elseif pid == 0 then
		mUnistd.close(cmdW);
		mUnistd.close(outputR);
		mUnistd.close(mUnistd.STDIN_FILENO);
		mUnistd.close(mUnistd.STDOUT_FILENO);
		mUnistd.close(mUnistd.STDERR_FILENO);

		mUnistd.dup2(cmdR, mUnistd.STDIN_FILENO);
		mUnistd.dup2(outputW, mUnistd.STDOUT_FILENO);
		mUnistd.dup2(outputW, mUnistd.STDERR_FILENO);

		local _, err = mUnistd.exec("/usr/bin/env",
					    {
					    	[0] = "/usr/bin/env",
						"bash", "-s"
					    });
		io.stderr:write(err);
		os.exit(1);
	end

	mUnistd.close(cmdR);
	mUnistd.close(outputW);

	local isTimeout = false;
	mSignal.signal(mSignal.SIGALRM, function() isTimeout = true; end);

	mSignal.signal(mSignal.SIGPIPE, mSignal.SIG_IGN);

	local fcmdW = mStdio.fdopen(cmdW, "w");
	fcmdW:write(command);
	fcmdW:close();

	mUnistd.alarm(timeout);

	local buf = {};
	while not isTimeout do
		local data, err = mUnistd.read(outputR, 16384);
		if not data then
			goto killProcess;
		elseif data == "" then
			goto waitProcess;
		end

		table.insert(buf, data);
	end

::killProcess::
	mSignal.kill(pid, mSignal.SIGKILL);

::waitProcess::
	mUnistd.alarm(0);
	mSignal.signal(mSignal.SIGALRM, mSignal.SIG_DFL);

	mUnistd.close(outputR);

	local _, status, exitCode = mWait.wait(pid);
	if isTimeout then
		table.insert(buf, "\nProcess timed out");
	elseif status == "exited" then
		table.insert(buf, ("\nProcess exited with %d"):
				  format(exitCode));
	elseif status == "stopped" or status == "killed" then
		table.insert(buf, ("\nProcess terminated with signal %d"):
				  format(exitCode));
	end

	return table.concat(buf);
end

local function
process(arg)
	local command = arg.command;
	if not command then
		return "Missing 'command' argument";
	end

	if type(command) ~= "string" then
		return "Wrong type for 'command' argument, expect string";
	end

	local timeout = 300;
	if arg.timeout then
		timeout = arg.timeout;

		if type(timeout) ~= "number" or
		   not math.tointeger(timeout) then
			return "Wrong type for 'timeout' argument, expect integer";
		end

		if timeout < 0 then
			return "Invalid timeout, it must be greater than zero";
		end
	end

	print(("[TOOL] Executing '%s' with timeout %d"):
	      format(command, timeout));

	return runWithTimeout(command, timeout);
end

return {
	definition	= definition,
	process		= process,
};
