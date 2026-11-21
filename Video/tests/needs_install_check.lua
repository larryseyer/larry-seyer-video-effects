-- lua tests/needs_install_check.lua <pack dir> <ini>: prints whether the installed presets are current.
package.path = arg[1] .. "/lib/?.lua;" .. package.path
local L = require("lsvfx")
local function list_files(dir)
  local out = {}
  local p = io.popen('ls "' .. dir .. '"')
  for f in p:lines() do out[#out + 1] = f end
  p:close()
  return out
end
print("needs install:", L.needs_install(arg[2], L.load_all(arg[1] .. "/effects", list_files)))
