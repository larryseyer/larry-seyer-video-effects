-- Larry Seyer Video Effects scripting API, meant for automation and AI agents.
--
--   local LS = dofile(reaper.GetExtState("LS_VIDEO_FX", "path") .. "lib/agent.lua")
--   local fx = LS.add_to_item(item, "LS Color: Color Grade", { temp = 0.25, sat = 1.1 })
--   local title, tfx = LS.add_title(track, 2.0, 5.0, "Jane Doe | Drums", "LS Title: Lower Third", { align = 0 })
--   LS.keyframe(item, fx, "exposure", 3.0, 0.5)
--
-- Controls are named by their variable name (see docs/AI-REFERENCE.md); values are in the ranges listed there.
-- Every call checks names and ranges and raises an error that lists the valid choices.

local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local ROOT = DIR:gsub("lib[/\\]$", "")
package.path = DIR .. "?.lua;" .. package.path
local L = require "lsvfx"
local A = require "fxapi"

local M = {}
M.ROOT = ROOT
M.CARRIER = ROOT .. "LS Title Carrier.png"

local cache

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

-- All effects, parsed from the effect files.
function M.effects()
  cache = cache or L.load_all(ROOT .. "effects", list_files)
  return cache
end

-- Finds an effect by preset name ("LS Color: Color Grade") or title ("Color Grade"), case-insensitive.
function M.effect(name)
  local q = name:lower()
  for _, e in ipairs(M.effects()) do
    if e.name:lower() == q or e.title:lower() == q then return e end
  end
  local names = {}
  for _, e in ipairs(M.effects()) do names[#names + 1] = e.name end
  error("Larry Seyer Video Effects: no effect named '" .. name .. "'. Available:\n  " .. table.concat(names, "\n  "), 2)
end

-- Installs or updates the Video Processor presets in this REAPER if needed.
function M.ensure_presets()
  local ini = reaper.GetResourcePath() .. "/presets/builtin_video_processor.ini"
  if L.needs_install(ini, M.effects()) then L.install(ini, M.effects()) end
end

local function target_of(obj)
  if reaper.ValidatePtr2(0, obj, "MediaItem*") then
    local take = reaper.GetActiveTake(obj)
    if not take then error("Larry Seyer Video Effects: item has no take", 3) end
    return { kind = "take", take = take, item = obj, track = reaper.GetMediaItem_Track(obj) }
  elseif reaper.ValidatePtr2(0, obj, "MediaTrack*") then
    return { kind = "track", track = obj }
  end
  error("Larry Seyer Video Effects: expected a MediaItem or MediaTrack", 3)
end

local function control(e, var)
  local p = e.byvar[var]
  if not p then
    local vars = {}
    for _, q in ipairs(e.params) do vars[#vars + 1] = q.var end
    error("Larry Seyer Video Effects: '" .. e.name .. "' has no control '" .. tostring(var) .. "'. Controls: " .. table.concat(vars, ", "), 3)
  end
  return p
end

local function check_value(e, p, v)
  if type(v) ~= "number" then error("Larry Seyer Video Effects: value for '" .. p.var .. "' must be a number", 4) end
  if v < p.min - 1e-9 or v > p.max + 1e-9 then
    error(string.format("Larry Seyer Video Effects: %s '%s' must be between %g and %g (got %g)", e.name, p.var, p.min, p.max, v), 4)
  end
end

-- Finds which LS effect an FX instance is, from its renamed name or preset.
local function effect_at(t, fx)
  local nm = A.name(t, fx)
  for _, e in ipairs(M.effects()) do if e.name == nm or e.name == A.preset(t, fx) then return e end end
  error("Larry Seyer Video Effects: FX " .. fx .. " is not an Larry Seyer Video Effects effect", 3)
end

local function apply(t, fx, e, params)
  for var, v in pairs(params or {}) do
    local p = control(e, var)
    check_value(e, p, v)
    A.set(t, fx, p.index - 1, v)
  end
end

local function add(obj, name, params)
  M.ensure_presets()
  local e = M.effect(name)
  local t = target_of(obj)
  local fx = A.add(t, e.name)
  if fx < 0 then error("Larry Seyer Video Effects: could not add a Video processor", 3) end
  apply(t, fx, e, params)
  return fx
end

-- Adds an effect to an item (only that clip). Returns the FX index on the item's active take.
function M.add_to_item(item, name, params) return add(item, name, params) end

-- Adds an effect to a track (everything on it, and for overlays/transitions, the tracks behind it). Returns the FX index.
function M.add_to_track(track, name, params) return add(track, name, params) end

-- Sets controls on an existing effect: target is the item or track, fx its index.
function M.set(obj, fx, params)
  local t = target_of(obj)
  apply(t, fx, effect_at(t, fx), params)
end

-- Returns the first item on `track` overlapping pos..pos+len, or nil.
local function overlapping(track, pos, len)
  for k = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, k)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < pos + len - 1e-6 and p + l > pos + 1e-6 then return it, p, l end
  end
end

-- True when the top of the track list is in front (REAPER's default Track order); false when the bottom is.
function M.front_is_top() return A.front_is_top() end

-- Inserts a track named `name` directly in front of `track` in the layer order (above it with the default
-- Track order, below it with the reversed one). Returns the new track.
function M.add_track_in_front_of(track, name) return A.insert_in_front_of(track, name or "") end

-- Inserts a track named `name` at position `index` (0 = top; default: after the last track). Returns the track.
function M.add_track(name, index)
  index = index or reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(0, index)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name or "", true)
  return track
end

-- Puts a media file on `track` at `pos` for `len` seconds, starting `offset` seconds into the file. Without `len`
-- the item is as long as the file (5 s for still images). Sets no fades. Returns the item.
function M.add_media(track, path, pos, len, offset)
  local src = reaper.PCM_Source_CreateFromFile(path)
  if not src then error("Larry Seyer Video Effects: cannot open media '" .. tostring(path) .. "'", 2) end
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, src)
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", offset or 0)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos or 0)
  local srclen = reaper.GetMediaSourceLength(src) - (offset or 0)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len or (srclen > 0.05 and srclen or 5))
  reaper.UpdateArrange()
  return item
end

-- Makes two overlapping items on one track crossfade: sets the first item's fade-out and the second's fade-in
-- to the overlap (linear). Transition effects on the track run during exactly this crossfade.
function M.crossfade(item_a, item_b)
  local a0 = reaper.GetMediaItemInfo_Value(item_a, "D_POSITION")
  local a1 = a0 + reaper.GetMediaItemInfo_Value(item_a, "D_LENGTH")
  local b0 = reaper.GetMediaItemInfo_Value(item_b, "D_POSITION")
  if b0 < a0 then item_a, item_b, a0, b0 = item_b, item_a, b0, a0
    a1 = a0 + reaper.GetMediaItemInfo_Value(item_a, "D_LENGTH") end
  local overlap = a1 - b0
  if overlap <= 0 then error("Larry Seyer Video Effects: crossfade needs overlapping items (move the second item earlier)", 2) end
  reaper.SetMediaItemInfo_Value(item_a, "D_FADEOUTLEN", overlap)
  reaper.SetMediaItemInfo_Value(item_b, "D_FADEINLEN", overlap)
  reaper.SetMediaItemInfo_Value(item_a, "C_FADEOUTSHAPE", 0)
  reaper.SetMediaItemInfo_Value(item_b, "C_FADEINSHAPE", 0)
  reaper.UpdateArrange()
  return overlap
end

-- Creates a transparent title item (text = item name, | for a new line) at `pos` for `len` seconds on `track`,
-- with fade-in/out (default 0.5 s, these drive the animation), and adds the effect. Returns item, fx.
function M.add_title(track, pos, len, text, name, params, fade_in, fade_out)
  local other, op, ol = overlapping(track, pos, len)
  if other then
    error(string.format("Larry Seyer Video Effects: this title (%.2f-%.2f s) overlaps another item (%.2f-%.2f s) on the same track. " ..
      "A track shows one item at a time, so graphics that overlap in time need separate tracks " ..
      "(for example LS.add_track_in_front_of(track, \"Titles 2\")).", pos, pos + len, op, op + ol), 2)
  end
  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in or 0.5)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out or 0.5)
  reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
  reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, reaper.PCM_Source_CreateFromFile(M.CARRIER))
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", text or "", true)
  local fx = add(item, name, params)
  reaper.UpdateArrange()
  return item, fx
end

-- Writes a keyframe: control `var` reaches `value` at project time `time` (seconds).
function M.keyframe(obj, fx, var, time, value)
  local t = target_of(obj)
  local e = effect_at(t, fx)
  local p = control(e, var)
  check_value(e, p, value)
  local env = A.env(t, fx, p.index - 1, true)
  if t.kind == "take" then
    time = (time - reaper.GetMediaItemInfo_Value(t.item, "D_POSITION")) * reaper.GetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE")
  end
  reaper.InsertEnvelopePoint(env, time, value, 0, 0, false, true)
  reaper.Envelope_SortPoints(env)
end

-- Control list for an effect: { {var, label, index, min, max, default, help, options}, ... }.
function M.controls(name)
  local e = M.effect(name)
  local out = {}
  for _, p in ipairs(e.params) do
    out[#out + 1] = { var = p.var, label = p.label, index = p.index - 1, min = p.min, max = p.max, default = p.def,
                      help = e.help[p.var], options = e.enums[p.var] }
  end
  return out
end

return M
