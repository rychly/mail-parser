PREFIX=/usr/local
LUA_BINDIR=$(PREFIX)/bin
LUA_LIBDIR=$(PREFIX)/lib/lua/5.1
LUA_LUADIR=$(subst /lib/,/share/,$(LUA_LIBDIR))
LUA_CONFDIR=$(PREFIX)/etc

all:

install:
	mkdir -p $(LUA_LUADIR)
	cp mail-parser.lua $(LUA_LUADIR)
	mkdir -p $(LUA_BINDIR)
	cp mail-parser.sh $(LUA_BINDIR)/mail-parser
