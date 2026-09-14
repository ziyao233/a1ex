package = "a1ex"
version = "dev-1"
source = {
	url = "git+https://github.com/ziyao233/a1ex.git"
}
description = {
	homepage = "https://github.com/ziyao233/a1ex",
	license = "MPL-2.0"
}
dependencies = {
	"lua >= 5.4",
	"Lua-cURL >= 0.3.0",
	"luaposix",
	"lua-cjson"
}
build = {
	type = "builtin",
	install = {
		bin = {
			a1ex = "a1ex.lua"
		}
	},
	modules = {
		["a1ex.http"]		= "a1ex/http.lua",
		["a1ex.session"]	= "a1ex/session.lua",
		["a1ex.tools"]		= "a1ex/tools.lua",
		["a1ex.tools.bash"]	= "a1ex/tools/bash.lua",
		["a1ex.tools.read"]	= "a1ex/tools/read.lua",
		["a1ex.tools.write"]	= "a1ex/tools/write.lua",
	}
}
