#!/usr/bin/lua
package.path="/tmp/luci-app/usr/lib/lua/?.lua;/tmp/luci-app/usr/lib/lua/?/init.lua;"..package.path
package.cpath="/tmp/luci-app/usr/lib/lua/?.so;"..package.cpath
require "luci.cacheloader"
require "luci.sgi.cgi"
luci.sgi.cgi.run()
