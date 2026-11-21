-- @description Larry Seyer Video Effects: Multicam switcher window
-- @version 1.0.0
-- @author Larry Seyer
-- @about A switcher window for the Multicam Switcher effect: set up from selected camera tracks, then cut while it
--   plays with the number keys, the camera buttons, or by clicking a camera in the video window (switcher view).
--   Stopped, a number changes the shot at the edit cursor.

local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("Larry Seyer Video Effects needs the ReaImGui extension (install it with ReaPack).", "Multicam", 0)
  return
end
package.path = DIR .. "lib/?.lua;" .. reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ImGui = require "imgui" "0.10"
local L = require "lsvfx"
local A = require "fxapi"
local W = require "widgets"
local MC = require "multicam"
W.init(ImGui)

-- The effects must be installed as presets before setup can add them.
local INI = reaper.GetResourcePath() .. "/presets/builtin_video_processor.ini"
do
  local files, i = {}, 0
  while true do
    local f = reaper.EnumerateFiles(DIR .. "effects", i)
    if not f then break end
    files[#files + 1] = f
    i = i + 1
  end
  local effects = L.load_all(DIR .. "effects", function() return files end)
  if L.needs_install(INI, effects) then L.install(INI, effects) end
end

local ctx = ImGui.CreateContext("Larry Seyer Video Effects - Multicam")
local FONT = ImGui.CreateFont("sans-serif")
local FONT_B = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold)
ImGui.Attach(ctx, FONT)
ImGui.Attach(ctx, FONT_B)

local TALLY = 0xD42A2AFF
local TALLY_HOVER = 0xE5483FFF
local IDLE = 0x2B3138FF
local PUSH_FAMILY = 7   -- transitions from Push on use Direction

local S = { added_clicks = MC.add_clicks(), message = nil }
local _, _, section, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(section, cmd, 1)
reaper.RefreshToolbar2(section, cmd)
MC.poll_click()   -- forget clicks from before this window opened

do
  local sw = MC.find()
  if sw then MC.set_view(sw, true); MC.keep_tags_last() end
end

reaper.atexit(function()
  local sw = MC.find()
  if sw then MC.set_view(sw, false) end
  if S.added_clicks then MC.remove_clicks() end
  reaper.SetToggleCommandState(section, cmd, 0)
  reaper.RefreshToolbar2(section, cmd)
end)

local function dim(text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, W.TEXT_DIM)
  ImGui.TextWrapped(ctx, text)
  ImGui.PopStyleColor(ctx)
end

local function shift_held() return ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift ~= 0 end

local function cursor_time()
  if reaper.GetPlayState() & 1 == 1 then return reaper.GetPlayPosition() end
  return reaper.GetCursorPosition()
end

-- Camera list: tagged camera tracks, or numbered cells for a multiview recording.
local function camera_list()
  local cams = MC.cameras()
  if #cams > 0 then return cams end
  reaper.gmem_attach(MC.GMEM)
  local out = {}
  for k = 1, math.max(math.floor(reaper.gmem_read(11)), 1) do out[k] = { id = k, name = "Camera " .. k } end
  return out
end

local function draw_setup()
  ImGui.PushFont(ctx, FONT_B, 15)
  ImGui.Text(ctx, "Set up multicam")
  ImGui.PopFont(ctx)
  dim("Line your camera tracks up in time, select them (2 to 9; top to bottom become cameras 1, 2, 3...) and click "
      .. "Set up. A Multicam track with the switcher goes in front of them.")
  ImGui.Spacing(ctx)
  if ImGui.Button(ctx, "Set up from selected tracks", -1, 34) then
    local _, err = MC.setup(A.insert_in_front_of)
    S.message = err
  end
  if S.message then ImGui.Spacing(ctx); ImGui.TextColored(ctx, 0xE5A04AFF, S.message) end
end

local function draw_cameras(sw, live)
  local cams = camera_list()
  local avail = ImGui.GetContentRegionAvail(ctx)
  local per_row = math.min(#cams, 5)
  local bw = math.max(70, (avail - (per_row - 1)*6)/per_row)
  local other = shift_held()
  for i, c in ipairs(cams) do
    if (i - 1) % per_row ~= 0 then ImGui.SameLine(ctx, 0, 6) end
    local on = c.id == live
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, on and TALLY or IDLE)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, on and TALLY_HOVER or 0x3A424BFF)
    ImGui.PushFont(ctx, FONT_B, 15)
    if ImGui.Button(ctx, c.id .. "\n" .. c.name .. "##cam" .. c.id, bw, 58) then MC.switch(sw, c.id, other) end
    ImGui.PopFont(ctx)
    ImGui.PopStyleColor(ctx, 2)
  end
end

local function draw_transition()
  local s = MC.settings()
  local changed = false
  ImGui.SeparatorText(ctx, "Switch with")
  if ImGui.RadioButton(ctx, "Cut", s.style == 0) then s.style = 0; changed = true end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Transition:", s.style ~= 0) then s.style = s.alt_style; changed = true end
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 150)
  if ImGui.BeginCombo(ctx, "##style", MC.TRANSITIONS[s.alt_style + 1]) then
    for k = 1, #MC.TRANSITIONS - 1 do
      if ImGui.Selectable(ctx, MC.TRANSITIONS[k + 1], s.alt_style == k) then
        s.alt_style = k
        if s.style ~= 0 then s.style = k end
        changed = true
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetNextItemWidth(ctx, 170)
  local fc, fv = ImGui.SliderInt(ctx, "frames", s.frames, 1, 120)
  if fc then s.frames = fv; changed = true end
  if s.alt_style >= PUSH_FAMILY then
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 90)
    if ImGui.BeginCombo(ctx, "direction", MC.DIRECTIONS[s.dir + 1]) then
      for k = 0, 3 do
        if ImGui.Selectable(ctx, MC.DIRECTIONS[k + 1], s.dir == k) then s.dir = k; changed = true end
      end
      ImGui.EndCombo(ctx)
    end
  end
  if changed then MC.save_settings(s) end
  dim("Hold Shift while switching for the other one (a cut instead of the transition, or the transition instead "
      .. "of a cut).")
end

local function draw_cut_tools(sw)
  ImGui.SeparatorText(ctx, "Cuts")
  if ImGui.Button(ctx, "< Previous") then MC.jump(sw, -1) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Next >") then MC.jump(sw, 1) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remove cut") then MC.remove_cut(sw) end
  ImGui.SameLine(ctx)
  local s = MC.settings()
  local style = s.style ~= 0 and s.style or s.alt_style
  if ImGui.Button(ctx, "Give it the transition") then MC.set_cut_transition(sw, style) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Make it a cut") then MC.set_cut_transition(sw, 0) end
  local c = MC.cut_before(sw, reaper.GetCursorPosition())
  if c then
    local st, fr, dr = MC.transition_at(sw, c.time)
    local what = st == 0 and "cut" or (MC.TRANSITIONS[st + 1] .. ", " .. fr .. " frames"
                 .. (st >= PUSH_FAMILY and (", " .. MC.DIRECTIONS[dr + 1]) or ""))
    dim(string.format("At the cursor: camera %d from %s (%s).", c.cam, reaper.format_timestr_pos(c.time, "", -1), what))
  end
end

-- Keys while this window has focus. Number keys elsewhere in REAPER: bind the Multicam camera actions.
local NUM = {}
for k = 1, 9 do NUM[k] = { ImGui["Key_" .. k], ImGui["Key_Keypad" .. k] } end
local function keys(sw)
  if not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then return end
  local other = shift_held()
  for k = 1, 9 do
    if ImGui.IsKeyPressed(ctx, NUM[k][1], false) or ImGui.IsKeyPressed(ctx, NUM[k][2], false) then
      MC.switch(sw, k, other)
    end
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then reaper.Main_OnCommand(40044, 0) end   -- play/stop
  if ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow) then MC.jump(sw, -1) end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow) then MC.jump(sw, 1) end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Delete, false) or ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace, false) then
    MC.remove_cut(sw)
  end
end

local function frame()
  local sw = MC.find()
  if not sw then draw_setup() return end
  local click = MC.poll_click()
  if click and click.cam >= 1 then MC.switch(sw, click.cam, click.shift, click.time) end
  local live = MC.live_at(sw, cursor_time())
  local _, name = reaper.GetTrackName(sw.track)
  ImGui.PushFont(ctx, FONT_B, 15)
  ImGui.Text(ctx, name)
  ImGui.PopFont(ctx)
  ImGui.SameLine(ctx)
  local switcher = MC.view(sw)
  ImGui.SetCursorPosX(ctx, ImGui.GetWindowWidth(ctx) - 250)
  if ImGui.RadioButton(ctx, "Switcher view", switcher) then MC.set_view(sw, true) end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Program view", not switcher) then MC.set_view(sw, false) end
  ImGui.Spacing(ctx)
  draw_cameras(sw, live)
  draw_transition()
  draw_cut_tools(sw)
  ImGui.Spacing(ctx)
  dim("Playing: press 1-9, click a camera here or in the video window (switcher view). Re-cutting over a section "
      .. "replaces its earlier cuts. Stopped: a number changes the shot at the cursor. Space plays and stops. "
      .. "Closing this window returns the video to Program view.")
  keys(sw)
end

local function loop()
  ImGui.PushFont(ctx, FONT, 14)
  local nc, nv = W.push_theme(ctx)
  ImGui.SetNextWindowSize(ctx, 560, 420, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Multicam - Larry Seyer Video Effects", true)
  if visible then
    frame()
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, nv)
  ImGui.PopStyleColor(ctx, nc)
  ImGui.PopFont(ctx)
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
