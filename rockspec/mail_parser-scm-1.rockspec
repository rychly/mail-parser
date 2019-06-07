package = "mail_parser"
version = "scm-1"
source = {
	url = "git+https://gitlab.com/rychly/mail-parser.git",
	branch = "master"
}
description = {
	summary = "Lua scripts to parse mail messages, plain or in MIME format.",
	detailed = "",
	homepage = "https://gitlab.com/rychly/mail-parser",
	license = "GNU/GPLv3"
}
dependencies = {
	"lua >= 5.1, < 5.4",
	"luafilesystem",
	"luasocket",
	"convert_charsets"
}
build = {
	type = "make",
	build_variables = {
		CFLAGS = "$(CFLAGS)",
		LIBFLAG = "$(LIBFLAG)",
		LUA_LIBDIR = "$(LUA_LIBDIR)",
		LUA_BINDIR = "$(LUA_BINDIR)",
		LUA_INCDIR = "$(LUA_INCDIR)",
		LUA = "$(LUA)"
	},
	install_variables = {
		PREFIX = "$(PREFIX)",
		LUA_BINDIR = "$(BINDIR)",
		LUA_LIBDIR = "$(LIBDIR)",
		LUA_LUADIR = "$(LUADIR)",
		LUA_CONFDIR = "$(CONFDIR)"
	}
}
