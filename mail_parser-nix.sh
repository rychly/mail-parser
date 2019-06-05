#!/usr/bin/env nix-shell
--[[
#!nix-shell -i lua default.nix
# ^ because the following inline Nix expression cannot include ./?.lua and ./?/init.lua in LUA_PATH: #!nix-shell -i lua -p "luaPackages.lua.withPackages(ps: with ps; [ luasocket convert-charsets ])"
--]]

local mail_parser = require("mail_parser")
os.exit(mail_parser.main(arg))
