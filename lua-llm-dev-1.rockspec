package = "lua-llm"
version = "dev-1"
source = {
   url = "git+ssh://git@github.com/edward70/lua-llm.git"
}
description = {
   summary = "OpenAI compatible API for Lua.",
   detailed = [[
OpenAI compatible API for Lua. Compatible with any socket library
that supports the LuaSocket request interface. Compatible with OpenResty using
[`lapis.nginx.http`](https://leafo.net/lapis/reference/utilities.html#making-http-requests).]],
   homepage = "https://github.com/edward70/lua-llm",
   license = "MIT"
}
dependencies = {
  "lua >= 5.1",
  "lpeg",
  "lua-cjson",
  "tableshape",
  "luasocket",
  "luasec",
}
build = {
   type = "builtin",
   modules = {
      ["openai"] = "openai/init.lua"
   }
}
