#!/usr/bin/env lua

-- set LUA_PATH and LUA_CPATH to load also local modules
local prefix_path = '.';
package.path = ('%s/?.lua;%s/?/init.lua;%s'):format(prefix_path, prefix_path, package.path)
package.cpath = ('%s/?.so;%s/?/init.so;%s'):format(prefix_path, prefix_path, package.cpath)

local mail_parser = require("mail-parser")
os.exit(mail_parser.main(arg))
