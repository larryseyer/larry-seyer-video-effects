-- Multicam editing for Larry Seyer Video Effects: finds the Multicam Switcher and its camera tracks, sets them up
-- from selected tracks, and writes cuts. A cut is one square point on the switcher's Camera envelope whose value
-- also carries the cut's transition (see M.encode), so dragging, copying or ripple editing the point keeps them
-- together. A whole-number point (typed by hand, or written before 1.1.7) uses the switcher's Transition,
-- Transition frames and Direction controls instead.

local AS = require "audiosync"

local M = {}

M.SWITCHER = "LS Transform: Multicam Switcher"
M.CAMERA = "LS Transform: Multicam Camera"
M.CLICKS = "LS Transform: Multicam Clicks"
M.GMEM = "LSVFX_Multicam"
M.TRANSITIONS = { "Cut", "Cross dissolve", "Dip to black", "Dip to white", "Additive dissolve", "Blur dissolve",
                  "Luma dissolve", "Push", "Slide in", "Slide out", "Split open", "Squeeze" }
M.DIRECTIONS = { "Left", "Right", "Up", "Down" }

-- Switcher parameter indexes (Video Processor param N is index N-1).
local P_CAM, P_SHOW, P_TRANS, P_FRAMES, P_DIR = 0, 1, 2, 3, 4
local EXT = "LSVFX_Multicam"
local VP = "Video processor"
local MONITOR = 0x1000000

-- Settings kept between sessions: style is the transition used when Shift is not held (0 = Cut); alt_style is the
-- one used for a transition when style is Cut; sync = 1 lines the cameras up by their audio after setup.
local SETTINGS = { style = 0, alt_style = 1, frames = 12, dir = 0, sync = 1 }

function M.settings()
  local s = {}
  for k, d in pairs(SETTINGS) do s[k] = tonumber(reaper.GetExtState(EXT, k)) or d end
  return s
end

function M.save_settings(s)
  for k in pairs(SETTINGS) do reaper.SetExtState(EXT, k, tostring(s[k]), true) end
end

-- Finding things -----------------------------------------------------------------------------------

local function fx_named(track, name)
  for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
    local _, nm = reaper.TrackFX_GetFXName(track, fx)
    if nm == name then return fx end
  end
  return nil
end

-- The switcher to work on: the selected track's, else the first in the project. Returns { track, fx } or nil.
function M.find()
  local sel = reaper.GetSelectedTrack(0, 0)
  if sel then
    local fx = fx_named(sel, M.SWITCHER)
    if fx then return { track = sel, fx = fx } end
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local fx = fx_named(tr, M.SWITCHER)
    if fx then return { track = tr, fx = fx } end
  end
  return nil
end

-- Camera tracks (tracks with a Multicam Camera effect), sorted by camera number: { id, track, fx, name }.
function M.cameras()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local fx = fx_named(tr, M.CAMERA)
    if fx then
      local id = math.floor(reaper.TrackFX_GetParam(tr, fx, 0) + 0.5)
      local _, nm = reaper.GetTrackName(tr)
      out[#out + 1] = { id = id, track = tr, fx = fx, name = nm }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- The switcher reads the last effect on each camera track, so the camera tag must stay last.
function M.keep_tags_last()
  for _, c in ipairs(M.cameras()) do
    local last = reaper.TrackFX_GetCount(c.track) - 1
    if c.fx ~= last then reaper.TrackFX_CopyToTrack(c.track, c.fx, c.track, last, true) end
  end
end

local function env(sw, param, create)
  return reaper.GetFXEnvelope(sw.track, sw.fx, param, create or false)
end

-- Camera point values: camera + code/100000, code = 1 + style + 12*((frames - 1) + 120*dir), 1 to 5760, so the
-- point sits at most 0.06 above its camera. The switcher decodes the same way.
function M.encode(cam, style, frames, dir)
  local function clamp(v, lo, hi) return math.min(math.max(math.floor(v + 0.5), lo), hi) end
  style, frames, dir = clamp(style, 0, 11), clamp(frames, 1, 120), clamp(dir, 0, 3)
  return cam + (1 + style + 12*((frames - 1) + 120*dir))/100000
end

-- Camera, then style, frames and direction (nil for a whole-number point).
function M.decode(v)
  local cam = math.floor(v + 0.001)
  local code = math.floor((v - cam)*100000 + 0.5)
  if code < 1 then return cam end
  local r = (code - 1)//12
  return cam, (code - 1) % 12, r % 120 + 1, r//120
end

-- Setup ----------------------------------------------------------------------------------------------

local function add_preset(track, name)
  local fx = reaper.TrackFX_AddByName(track, VP, false, -1)
  if fx < 0 then return nil end
  reaper.TrackFX_SetPreset(track, fx, name)
  reaper.TrackFX_SetNamedConfigParm(track, fx, "renamed_name", name)
  return fx
end

-- The switcher on `track`, or nil.
function M.on_track(track)
  local fx = fx_named(track, M.SWITCHER)
  return fx and { track = track, fx = fx } or nil
end

-- Turns camera tracks (2 to 9; default: the selected tracks, top to bottom) into a multicam: tags them as cameras
-- 1, 2, ... in that order and puts a Multicam track carrying the switcher in front of all of them.
-- `insert_in_front_of(track, name)` is fxapi's layer-order-aware track insert. Returns the switcher, or nil and a
-- message.
function M.setup(insert_in_front_of, tracks)
  if not tracks then
    tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i) end
  end
  if #tracks < 2 or #tracks > 9 then return nil, "Select your camera tracks first (2 to 9 tracks)." end
  for _, tr in ipairs(tracks) do
    if fx_named(tr, M.SWITCHER) then return nil, "One of the selected tracks already has a Multicam Switcher." end
  end
  reaper.Undo_BeginBlock()
  for id, tr in ipairs(tracks) do
    local fx = fx_named(tr, M.CAMERA) or add_preset(tr, M.CAMERA)
    reaper.TrackFX_SetParam(tr, fx, 0, id)
  end
  local front_is_top = true
  local ok, flags = reaper.get_config_var_string("projvidflags")
  if ok then front_is_top = (math.floor(tonumber(flags) or 256) & 256) ~= 0 end
  local front = tracks[1]
  for _, tr in ipairs(tracks) do
    local n, f = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"), reaper.GetMediaTrackInfo_Value(front, "IP_TRACKNUMBER")
    if (front_is_top and n < f) or (not front_is_top and n > f) then front = tr end
  end
  local mc = insert_in_front_of(front, "Multicam")
  local fx = add_preset(mc, M.SWITCHER)
  reaper.TrackFX_SetParam(mc, fx, P_SHOW, 1)
  local sw = { track = mc, fx = fx }
  local s = M.settings()
  local e = env(sw, P_CAM, true)
  reaper.DeleteEnvelopePointRange(e, -1, math.huge)
  reaper.InsertEnvelopePoint(e, 0, M.encode(1, 0, s.frames, s.dir), 1, 0, false, true)
  reaper.Envelope_SortPoints(e)
  reaper.SetOnlyTrackSelected(mc)
  M.keep_tags_last()
  reaper.TrackList_AdjustWindows(false)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: set up multicam", -1)
  return sw
end

-- Reading the cut list --------------------------------------------------------------------------------

local function frame_time(t)
  local fr = reaper.TimeMap_curFrameRate(0)
  if not fr or fr <= 0 then fr = 30 end
  return math.floor(t*fr + 0.5)/fr, 0.5/fr
end

-- Cut points as { time, cam, value } in time order.
function M.cuts(sw)
  local e = env(sw, P_CAM)
  local out = {}
  if not e then return out end
  for k = 0, reaper.CountEnvelopePoints(e) - 1 do
    local _, t, v = reaper.GetEnvelopePoint(e, k)
    out[#out + 1] = { time = t, cam = M.decode(v), value = v }
  end
  table.sort(out, function(a, b) return a.time < b.time end)
  return out
end

-- Camera on air at time t.
function M.live_at(sw, t)
  local e = env(sw, P_CAM)
  if not e then return M.decode(reaper.TrackFX_GetParam(sw.track, sw.fx, P_CAM)) end
  local _, v = reaper.Envelope_Evaluate(e, t, 0, 0)
  return (M.decode(v))
end

-- The cut at or before time t (within half a frame), as { time, cam, value } or nil.
function M.cut_before(sw, t)
  local _, half = frame_time(t)
  local best
  for _, c in ipairs(M.cuts(sw)) do
    if c.time <= t + half then best = c end
  end
  return best
end

-- Writing cuts ------------------------------------------------------------------------------------------

local function set_point(e, t, v, half)
  reaper.DeleteEnvelopePointRange(e, t - half, t + half)
  reaper.InsertEnvelopePoint(e, t, v, 1, 0, false, true)
end

local function write_cut(sw, t, half, cam, style, frames, dir)
  set_point(env(sw, P_CAM, true), t, M.encode(cam, style, frames, dir), half)
end

local function clear_range(sw, t0, t1)
  local e = env(sw, P_CAM, false)
  if e then reaper.DeleteEnvelopePointRange(e, t0, t1) end
end

local function sort_all(sw)
  local e = env(sw, P_CAM, false)
  if e then reaper.Envelope_SortPoints(e) end
end

-- Points as { t, v, shape, tension } in time order.
local function points(e)
  local out = {}
  for k = 0, reaper.CountEnvelopePoints(e) - 1 do
    local _, t, v, shape, tension = reaper.GetEnvelopePoint(e, k)
    out[#out + 1] = { t = t, v = v, shape = shape, tension = tension }
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

-- The points of `list` with no point of `other` within `tol` seconds (both in time order).
local function unmatched(list, other, tol)
  local out, j = {}, 1
  for _, p in ipairs(list) do
    while other[j] and other[j].t < p.t - tol do j = j + 1 end
    if not (other[j] and other[j].t <= p.t + tol) then out[#out + 1] = p end
  end
  return out
end

-- Moves the Transition, Transition frames and Direction points of old-style cuts to their Camera points when a
-- Camera point was dragged on its own (paired in time order); drops them when their Camera point was deleted.
local function realign_lanes(sw, cams, tol)
  for _, param in ipairs({ P_TRANS, P_FRAMES, P_DIR }) do
    local e = env(sw, param)
    if e then
      local pts = points(e)
      local lost, dest = unmatched(pts, cams, tol), unmatched(cams, pts, tol)
      for i, p in ipairs(lost) do
        reaper.DeleteEnvelopePointRange(e, p.t - 1e-6, p.t + 1e-6)
        if dest[i] then reaper.InsertEnvelopePoint(e, dest[i].t, p.v, p.shape, p.tension, false, true) end
      end
      if #lost > 0 then reaper.Envelope_SortPoints(e) end
    end
  end
end

-- Value of switcher control `param` at time t: its envelope when it has points, else the control.
local function control_at(sw, param, t)
  local e = env(sw, param)
  if e and reaper.CountEnvelopePoints(e) > 0 then
    local _, v = reaper.Envelope_Evaluate(e, t, 0, 0)
    return math.floor(v + 0.5)
  end
  return math.floor(reaper.TrackFX_GetParam(sw.track, sw.fx, param) + 0.5)
end

-- Gives every whole-number Camera point (old projects, or typed by hand) the transition it plays with now, so it
-- carries it from then on, and empties the Transition, Transition frames and Direction envelopes once no point
-- needs them. Not an undo step of its own: Undo returns to a state that plays the same. Returns true when it
-- changed anything.
function M.convert_old_cuts(sw)
  local ce = env(sw, P_CAM)
  if not ce then return false end
  local cams = points(ce)
  local old = {}
  for _, p in ipairs(cams) do
    if not select(2, M.decode(p.v)) then old[#old + 1] = p end
  end
  if #old == 0 then return false end
  local _, tol = frame_time(0)
  realign_lanes(sw, cams, tol)
  for _, p in ipairs(old) do
    local v = M.encode(M.decode(p.v), control_at(sw, P_TRANS, p.t), control_at(sw, P_FRAMES, p.t),
                       control_at(sw, P_DIR, p.t))
    reaper.DeleteEnvelopePointRange(ce, p.t - 1e-6, p.t + 1e-6)
    reaper.InsertEnvelopePoint(ce, p.t, v, p.shape, p.tension, false, true)
  end
  reaper.Envelope_SortPoints(ce)
  for _, param in ipairs({ P_TRANS, P_FRAMES, P_DIR }) do
    local e = env(sw, param)
    if e then   -- point by point: a range delete leaves the point at 0
      for k = reaper.CountEnvelopePoints(e) - 1, 0, -1 do reaper.DeleteEnvelopePointEx(e, -1, k) end
    end
  end
  return true
end

-- Writes a cut at project time t (for scripts and agents): camera, transition style (0 = cut), frames, direction.
function M.add_cut(sw, t, cam, style, frames, dir)
  local ft, half = frame_time(t)
  reaper.Undo_BeginBlock()
  write_cut(sw, ft, half, cam, style or 0, frames or 12, dir or 0)
  sort_all(sw)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: multicam cut", -1)
end

-- The transition a new cut gets: the chosen style, or with `other` (Shift) a cut when the style is a transition
-- and the chosen transition when the style is Cut.
function M.style_for(s, other)
  if not other then return s.style end
  if s.style == 0 then return s.alt_style end
  return 0
end

-- The first switch of a pass also replaces cuts this many seconds before it: an earlier take of the same switch,
-- pressed a little sooner, would otherwise stay on as a flash of another camera.
local PASS_LEAD = 0.5

-- Switches to camera `cam`. While playing: cuts at time `t` (default: play position). Cutting again in the same
-- pass replaces the earlier cuts between your previous switch and this one, so you can re-cut over a section.
-- While stopped: changes the camera of the shot at time `t` (default: edit cursor).
function M.switch(sw, cam, other, t)
  local playing = reaper.GetPlayState() & 1 == 1
  t = t or (playing and reaper.GetPlayPosition() or reaper.GetCursorPosition())
  local ft, half = frame_time(t)
  reaper.Undo_BeginBlock()
  if playing then
    local now = reaper.time_precise()
    local last_t = tonumber(reaper.GetExtState(EXT, "pass_t"))
    local last_clock = tonumber(reaper.GetExtState(EXT, "pass_clock"))
    local rate = reaper.Master_GetPlayRate(0)
    if last_t and last_clock and ft > last_t and math.abs((ft - last_t) - (now - last_clock)*rate) < 0.35 then
      clear_range(sw, last_t + half, ft + half)
    elseif ft > half then
      clear_range(sw, math.max(ft - PASS_LEAD, half), ft)   -- keeps the first shot's point at 0
    end
    reaper.SetExtState(EXT, "pass_t", tostring(ft), false)
    reaper.SetExtState(EXT, "pass_clock", tostring(now), false)
    local s = M.settings()
    write_cut(sw, ft, half, cam, M.style_for(s, other), s.frames, s.dir)
  else
    local c = M.cut_before(sw, ft)
    local e = env(sw, P_CAM, true)
    local s = M.settings()
    if c then
      local _, style, frames, dir = M.decode(c.value)
      set_point(e, c.time, style and M.encode(cam, style, frames, dir) or cam, 0.0001)
    else
      reaper.InsertEnvelopePoint(e, 0, M.encode(cam, 0, s.frames, s.dir), 1, 0, false, true)
    end
  end
  sort_all(sw)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: multicam camera " .. cam, -1)
end

-- Gives the cut at or before the edit cursor the current transition settings (style, frames, direction).
function M.set_cut_transition(sw, style)
  local c = M.cut_before(sw, reaper.GetCursorPosition())
  if not c then return end
  local s = M.settings()
  reaper.Undo_BeginBlock()
  set_point(env(sw, P_CAM, true), c.time, M.encode(c.cam, style, s.frames, s.dir), 0.0001)
  sort_all(sw)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: multicam transition", -1)
end

-- Transition of cut `c` (from M.cuts or M.cut_before): style, frames, direction.
function M.transition(sw, c)
  local _, style, frames, dir = M.decode(c.value)
  if style then return style, frames, dir end
  return control_at(sw, P_TRANS, c.time), control_at(sw, P_FRAMES, c.time), control_at(sw, P_DIR, c.time)
end

-- Removes the cut at or before the edit cursor (the first shot stays; set its camera instead).
function M.remove_cut(sw)
  local c = M.cut_before(sw, reaper.GetCursorPosition())
  if not c or c.time <= 0.0001 then return false end
  reaper.Undo_BeginBlock()
  clear_range(sw, c.time - 0.0001, c.time + 0.0001)
  sort_all(sw)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: remove multicam cut", -1)
  return true
end

-- Moves the edit cursor to the previous (dir < 0) or next cut.
function M.jump(sw, dir)
  local now = reaper.GetCursorPosition()
  local best
  for _, c in ipairs(M.cuts(sw)) do
    if dir > 0 and c.time > now + 0.001 and not best then best = c.time end
    if dir < 0 and c.time < now - 0.001 then best = c.time end
  end
  if best then reaper.SetEditCurPos(best, true, true) end
end

-- Lining up by audio ---------------------------------------------------------------------------------

-- The default reference for lining up: camera 1's track, or nil.
function M.reference()
  local cams = M.cameras()
  return cams[1] and cams[1].track or nil
end

-- What to line up against `ref_track`: every item on the camera tracks except the reference track's own, as
-- { item, label } for lib/audiosync.lua.
function M.sync_items(ref_track)
  local out = {}
  for _, c in ipairs(M.cameras()) do
    if c.track ~= ref_track then
      for i = 0, reaper.CountTrackMediaItems(c.track) - 1 do
        local item = reaper.GetTrackMediaItem(c.track, i)
        local take = reaper.GetActiveTake(item)
        local nm = take and select(2, reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)) or ""
        if nm == "" and take then
          nm = reaper.GetMediaSourceFileName(reaper.GetMediaItemTake_Source(take)):match("[^/\\]*$")
        end
        out[#out + 1] = { item = item, label = string.format("Camera %d (%s)", c.id, nm) }
      end
    end
  end
  return out
end

-- Starts lining the cameras up against `ref_track` (see audiosync's M.start); nil and a message when there is
-- nothing to line up.
function M.sync_start(ref_track)
  local items = M.sync_items(ref_track)
  if #items == 0 then return nil, "No camera clips to line up besides the reference track's." end
  return AS.start(ref_track, items)
end

-- The same, start to finish, for scripts: returns the results, or nil and a message.
function M.sync_now(ref_track)
  local items = M.sync_items(ref_track)
  if #items == 0 then return nil, "No camera clips to line up besides the reference track's." end
  local results = AS.analyze(ref_track, items)
  M.sync_apply(results)
  return results
end

-- Moves the clips to where their audio matched, as one undo step.
function M.sync_apply(results)
  reaper.Undo_BeginBlock()
  AS.apply(results)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: line up cameras by audio", -1)
end

-- View and clicks ------------------------------------------------------------------------------------

function M.view(sw) return reaper.TrackFX_GetParam(sw.track, sw.fx, P_SHOW) > 0.5 end
function M.set_view(sw, switcher) reaper.TrackFX_SetParam(sw.track, sw.fx, P_SHOW, switcher and 1 or 0) end

-- Adds the Multicam Clicks effect to Monitoring FX if it is not there. Returns true when it added it.
function M.add_clicks()
  local master = reaper.GetMasterTrack(0)
  for i = 0, reaper.TrackFX_GetRecCount(master) - 1 do
    local _, nm = reaper.TrackFX_GetFXName(master, MONITOR + i)
    if nm == M.CLICKS then return false end
  end
  local fx = reaper.TrackFX_AddByName(master, VP, true, -1)
  if fx < 0 then return false end
  if fx < MONITOR then fx = fx + MONITOR end   -- the returned index may lack the Monitoring FX flag
  reaper.TrackFX_SetPreset(master, fx, M.CLICKS)
  reaper.TrackFX_SetNamedConfigParm(master, fx, "renamed_name", M.CLICKS)
  return true
end

function M.remove_clicks()
  local master = reaper.GetMasterTrack(0)
  for i = reaper.TrackFX_GetRecCount(master) - 1, 0, -1 do
    local _, nm = reaper.TrackFX_GetFXName(master, MONITOR + i)
    if nm == M.CLICKS then reaper.TrackFX_Delete(master, MONITOR + i) end
  end
end

-- Returns { cam, time, shift } for a click in the video window since the last call, or nil.
function M.poll_click()
  reaper.gmem_attach(M.GMEM)
  local n = reaper.gmem_read(1)
  local seen = tonumber(reaper.GetExtState(EXT, "clicks_seen"))
  reaper.SetExtState(EXT, "clicks_seen", tostring(n), false)
  if not seen or n == seen then return nil end
  return { cam = math.floor(reaper.gmem_read(2) + 0.5), time = reaper.gmem_read(3), shift = reaper.gmem_read(4) > 0.5 }
end

return M
