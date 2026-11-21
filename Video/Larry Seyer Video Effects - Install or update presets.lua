-- @description Larry Seyer Video Effects: install or update the Video Processor presets
-- @version 1.0.0
-- @author Larry Seyer
-- @about Adds every Larry Seyer Video Effects effect to the Video Processor preset list (presets named "LS <Category>: ...").
--   Your other video presets are kept. The first install backs up the preset file next to it.

local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
reaper.SetExtState("LS_VIDEO_FX", "path", DIR, true)  -- lets scripts and AI agents find this folder
package.path = DIR .. "lib/?.lua;" .. package.path
local L = require "lsvfx"

local function list_files(dir)
  local out, i = {}, 0
  while true do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    out[#out + 1] = f
    i = i + 1
  end
  return out
end

local ini = reaper.GetResourcePath() .. "/presets/builtin_video_processor.ini"
local effects = L.load_all(DIR .. "effects", list_files)
local n, backup = L.install(ini, effects)
reaper.MB(string.format("Installed %d Larry Seyer Video Effects presets.\n\nIn any Video Processor, open the preset list and look for the LS entries.%s",
  n, backup and ("\n\nBackup of your previous preset file:\n" .. backup) or ""), "Larry Seyer Video Effects", 0)
