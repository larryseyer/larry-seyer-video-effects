-- Standalone check of the installer: lua tests/install_check.lua <pack dir> <ini path>
package.path = arg[1] .. "/lib/?.lua;" .. package.path
local L = require("lsvfx")
local function list_files(dir)
  local out = {}
  local p = io.popen('ls "' .. dir .. '"')
  for f in p:lines() do out[#out + 1] = f end
  p:close()
  return out
end
local effects = L.load_all(arg[1] .. "/effects", list_files)
for _, e in ipairs(effects) do
  io.write(string.format("%-48s params=%2d lines=%4d\n", e.name, #e.params, #e.code))
end
local n, backup = L.install(arg[2], effects)
print("installed", n, "backup", backup)
