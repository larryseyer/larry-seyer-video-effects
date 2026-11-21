-- @description Larry Seyer Video Effects: Multicam camera action (one script installed as nine plus nine actions)
-- @version 1.0.0
-- @author Larry Seyer
-- @about Installed as "Larry Seyer Video Effects - Multicam camera N.lua" and "... camera N (Shift).lua" (N = 1-9);
--   the camera number and Shift come from the installed file name. Bind them to the number keys and Shift+number.
--   Playing: cuts to camera N at the play position. Stopped: changes the shot at the edit cursor to camera N.
--   The (Shift) actions switch the other way (a cut instead of the transition, or the transition instead of a cut).

local _, path = reaper.get_action_context()
local dir = path:match("^(.*[/\\])")
local cam = tonumber(path:match("camera (%d)"))
local other = path:find("(Shift)", 1, true) ~= nil
package.path = dir .. "lib/?.lua;" .. dir .. "../lib/?.lua;" .. package.path
local MC = require "multicam"

if not cam then
  reaper.MB("This action's file name has no camera number (expected 'Multicam camera 1' to 'camera 9').", "Multicam", 0)
  return
end
local sw = MC.find()
if not sw then
  reaper.MB("No Multicam Switcher in this project. Run 'Larry Seyer Video Effects - Multicam' to set one up.", "Multicam", 0)
  return
end
MC.switch(sw, cam, other)
