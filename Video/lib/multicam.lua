-- Multicam editing for Larry Seyer Video Effects: finds the Multicam Switcher and its camera tracks, sets them up
-- from selected tracks, and writes cuts. A cut is a point on the switcher's Camera envelope, with points at the
-- same time on its Transition, Transition frames and Direction envelopes, all square-shaped.

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
  for param, v in pairs({ [P_CAM] = 1, [P_TRANS] = 0, [P_FRAMES] = s.frames, [P_DIR] = s.dir }) do
    local e = env(sw, param, true)
    reaper.DeleteEnvelopePointRange(e, -1, math.huge)
    reaper.InsertEnvelopePoint(e, 0, v, 1, 0, false, true)
    reaper.Envelope_SortPoints(e)
  end
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

-- Cut points as { time, cam } in time order.
function M.cuts(sw)
  local e = env(sw, P_CAM)
  local out = {}
  if not e then return out end
  for k = 0, reaper.CountEnvelopePoints(e) - 1 do
    local _, t, v = reaper.GetEnvelopePoint(e, k)
    out[#out + 1] = { time = t, cam = math.floor(v + 0.5) }
  end
  table.sort(out, function(a, b) return a.time < b.time end)
  return out
end

-- Camera on air at time t.
function M.live_at(sw, t)
  local e = env(sw, P_CAM)
  if not e then return math.floor(reaper.TrackFX_GetParam(sw.track, sw.fx, P_CAM) + 0.5) end
  local _, v = reaper.Envelope_Evaluate(e, t, 0, 0)
  return math.floor(v + 0.5)
end

-- The cut at or before time t (within half a frame), as { time, cam } or nil.
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
  set_point(env(sw, P_CAM, true), t, cam, half)
  set_point(env(sw, P_TRANS, true), t, style, half)
  set_point(env(sw, P_FRAMES, true), t, frames, half)
  set_point(env(sw, P_DIR, true), t, dir, half)
end

local function clear_range(sw, t0, t1)
  for _, param in ipairs({ P_CAM, P_TRANS, P_FRAMES, P_DIR }) do
    local e = env(sw, param, false)
    if e then reaper.DeleteEnvelopePointRange(e, t0, t1) end
  end
end

local function sort_all(sw)
  for _, param in ipairs({ P_CAM, P_TRANS, P_FRAMES, P_DIR }) do
    local e = env(sw, param, false)
    if e then reaper.Envelope_SortPoints(e) end
  end
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

-- Moves each cut's Transition, Transition frames and Direction points to its Camera point after the Camera point
-- was dragged on its own in the arrange view (paired in time order); drops them when their Camera point was
-- deleted. Not an undo step of its own: Undo goes back to before the drag, where the points still match.
-- Returns true when it changed anything.
function M.follow_moved_cuts(sw)
  local ce = env(sw, P_CAM)
  if not ce then return false end
  local cams = points(ce)
  local _, tol = frame_time(0)
  local changed = false
  for _, param in ipairs({ P_TRANS, P_FRAMES, P_DIR }) do
    local e = env(sw, param)
    if e then
      local pts = points(e)
      local lost, dest = unmatched(pts, cams, tol), unmatched(cams, pts, tol)
      for i, p in ipairs(lost) do
        reaper.DeleteEnvelopePointRange(e, p.t - 1e-6, p.t + 1e-6)
        if dest[i] then reaper.InsertEnvelopePoint(e, dest[i].t, p.v, p.shape, p.tension, false, true) end
        changed = true
      end
      if #lost > 0 then reaper.Envelope_SortPoints(e) end
    end
  end
  return changed
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
    if c then set_point(e, c.time, cam, 0.0001)
    else reaper.InsertEnvelopePoint(e, 0, cam, 1, 0, false, true) end
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
  local half = 0.0001
  set_point(env(sw, P_TRANS, true), c.time, style, half)
  set_point(env(sw, P_FRAMES, true), c.time, s.frames, half)
  set_point(env(sw, P_DIR, true), c.time, s.dir, half)
  sort_all(sw)
  reaper.Undo_EndBlock("Larry Seyer Video Effects: multicam transition", -1)
end

-- Transition of the cut at or before time t: style, frames, direction.
function M.transition_at(sw, t)
  local function val(param, d)
    local e = env(sw, param)
    if not e then return d end
    local _, v = reaper.Envelope_Evaluate(e, t, 0, 0)
    return math.floor(v + 0.5)
  end
  return val(P_TRANS, 0), val(P_FRAMES, 12), val(P_DIR, 0)
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
