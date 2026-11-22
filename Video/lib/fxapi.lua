-- REAPER side of the Larry Seyer Video Effects panel: the current target (selected item's take or selected track),
-- its Video Processor instances, parameter access, and keyframes (envelope points at the edit cursor).

local A = {}

local VP = "Video processor"

-- Target -------------------------------------------------------------------------------------------

function A.current_target()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    local take = reaper.GetActiveTake(item)
    if take then
      return { kind = "take", take = take, item = item, track = reaper.GetMediaItem_Track(item) }
    end
  end
  local track = reaper.GetSelectedTrack(0, 0)
  if track then return { kind = "track", track = track } end
  return nil
end

function A.valid(t)
  if not t then return false end
  if t.kind == "take" then return reaper.ValidatePtr2(0, t.take, "MediaItem_Take*") end
  return reaper.ValidatePtr2(0, t.track, "MediaTrack*")
end

function A.same(a, b)
  if not a or not b or a.kind ~= b.kind then return false end
  return (a.kind == "take" and a.take == b.take) or (a.kind == "track" and a.track == b.track)
end

function A.describe(t)
  if not t then return "Nothing selected" end
  if t.kind == "take" then
    local _, nm = reaper.GetSetMediaItemTakeInfo_String(t.take, "P_NAME", "", false)
    if nm == "" then
      local src = reaper.GetMediaItemTake_Source(t.take)
      nm = (reaper.GetMediaSourceFileName(src) or ""):match("([^/\\]+)$") or "(unnamed)"
    end
    return "Item: " .. nm
  end
  local _, nm = reaper.GetTrackName(t.track)
  return "Track " .. math.floor(reaper.GetMediaTrackInfo_Value(t.track, "IP_TRACKNUMBER")) .. ": " .. nm
end

-- FX wrappers that work for both takes and tracks ------------------------------------------------------

local function F(t, take_fn, track_fn) return t.kind == "take" and take_fn or track_fn end
local function obj(t) return t.kind == "take" and t.take or t.track end

function A.count(t) return F(t, reaper.TakeFX_GetCount, reaper.TrackFX_GetCount)(obj(t)) end
function A.name(t, fx) return select(2, F(t, reaper.TakeFX_GetFXName, reaper.TrackFX_GetFXName)(obj(t), fx)) end
function A.preset(t, fx) return select(2, F(t, reaper.TakeFX_GetPreset, reaper.TrackFX_GetPreset)(obj(t), fx)) end
function A.get(t, fx, i) return (F(t, reaper.TakeFX_GetParam, reaper.TrackFX_GetParam)(obj(t), fx, i)) end
function A.set(t, fx, i, v) return F(t, reaper.TakeFX_SetParam, reaper.TrackFX_SetParam)(obj(t), fx, i, v) end
function A.enabled(t, fx) return F(t, reaper.TakeFX_GetEnabled, reaper.TrackFX_GetEnabled)(obj(t), fx) end
function A.set_enabled(t, fx, on) F(t, reaper.TakeFX_SetEnabled, reaper.TrackFX_SetEnabled)(obj(t), fx, on) end
function A.delete(t, fx) F(t, reaper.TakeFX_Delete, reaper.TrackFX_Delete)(obj(t), fx) end
function A.show(t, fx) F(t, reaper.TakeFX_Show, reaper.TrackFX_Show)(obj(t), fx, 3) end

function A.move(t, fx, to)
  if t.kind == "take" then reaper.TakeFX_CopyToTake(t.take, fx, t.take, to, true)
  else reaper.TrackFX_CopyToTrack(t.track, fx, t.track, to, true) end
end

-- Adds a Video Processor loaded with the named LS preset; returns its index or -1.
function A.add(t, preset_name)
  local o = obj(t)
  local fx = t.kind == "take" and reaper.TakeFX_AddByName(o, VP, -1) or reaper.TrackFX_AddByName(o, VP, false, -1)
  if fx < 0 then return -1 end
  F(t, reaper.TakeFX_SetPreset, reaper.TrackFX_SetPreset)(o, fx, preset_name)
  F(t, reaper.TakeFX_SetNamedConfigParm, reaper.TrackFX_SetNamedConfigParm)(o, fx, "renamed_name", preset_name)
  return fx
end

-- LS effect instances on the target: list of { fx = index, name = preset name } (others skipped).
function A.instances(t, byname)
  local out = {}
  for fx = 0, A.count(t) - 1 do
    local nm = A.name(t, fx)
    local e = byname[nm] or byname[A.preset(t, fx)]
    out[#out + 1] = { fx = fx, effect = e, label = e and e.title or nm }
  end
  return out
end

-- Keyframes ---------------------------------------------------------------------------------------

function A.env(t, fx, i, create)
  return F(t, reaper.TakeFX_GetEnvelope, reaper.GetFXEnvelope)(obj(t), fx, i, create or false)
end

-- Envelope time for project time `pos`, default the edit cursor (take envelopes are relative to the item start).
function A.env_time(t, pos)
  pos = pos or reaper.GetCursorPosition()
  if t.kind == "take" then
    local rate = reaper.GetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE")
    return (pos - reaper.GetMediaItemInfo_Value(t.item, "D_POSITION")) * rate
  end
  return pos
end

-- Project time the panel shows: the play position while playing or recording, otherwise the edit cursor.
local function view_pos()
  if reaper.GetPlayState() & 5 ~= 0 then return reaper.GetPlayPosition() end
  return reaper.GetCursorPosition()
end

-- Value of parameter i at project time `pos` (default: the time the panel shows). A keyframed parameter is read
-- from its envelope, because its live value is whatever the video thread last rendered: stale while stopped and
-- ahead of the play position (buffered frames) while playing.
function A.value(t, fx, i, pos)
  local env = A.env(t, fx, i, false)
  if env and reaper.CountEnvelopePoints(env) > 0
     and select(2, reaper.GetSetEnvelopeInfo_String(env, "ACTIVE", "", false)) ~= "0" then
    local _, v = reaper.Envelope_Evaluate(env, A.env_time(t, pos or view_pos()), 0, 0)
    return v
  end
  return A.get(t, fx, i)
end

local function point_at(env, time)
  local n = reaper.CountEnvelopePoints(env)
  for k = 0, n - 1 do
    local _, pt = reaper.GetEnvelopePoint(env, k)
    if math.abs(pt - time) < 0.0005 then return k end
  end
  return nil
end

function A.keyframe_count(t, fx, i)
  local env = A.env(t, fx, i, false)
  return env and reaper.CountEnvelopePoints(env) or 0
end

function A.has_key_here(t, fx, i)
  local env = A.env(t, fx, i, false)
  return env ~= nil and point_at(env, A.env_time(t)) ~= nil
end

-- Writes value v as a keyframe at the edit cursor (creating the envelope when needed).
function A.set_key(t, fx, i, v)
  local env = A.env(t, fx, i, true)
  if not env then return end
  local time = A.env_time(t)
  local k = point_at(env, time)
  if k then reaper.SetEnvelopePoint(env, k, time, v, 0, 0, false, true)
  else reaper.InsertEnvelopePoint(env, time, v, 0, 0, false, true) end
  reaper.Envelope_SortPoints(env)
end

function A.delete_key(t, fx, i)
  local env = A.env(t, fx, i, false)
  if not env then return end
  local time = A.env_time(t)
  reaper.DeleteEnvelopePointRange(env, time - 0.0005, time + 0.0005)
end

-- Moves the edit cursor to the previous/next keyframe of any parameter of this instance.
function A.jump_key(t, fx, nparams, dir)
  local now = A.env_time(t)
  local best
  for i = 0, nparams - 1 do
    local env = A.env(t, fx, i, false)
    if env then
      for k = 0, reaper.CountEnvelopePoints(env) - 1 do
        local _, pt = reaper.GetEnvelopePoint(env, k)
        if (dir > 0 and pt > now + 0.001) or (dir < 0 and pt < now - 0.001) then
          if not best or (dir > 0 and pt < best) or (dir < 0 and pt > best) then best = pt end
        end
      end
    end
  end
  if best then
    if t.kind == "take" then
      local rate = reaper.GetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE")
      best = reaper.GetMediaItemInfo_Value(t.item, "D_POSITION") + best / rate
    end
    reaper.SetEditCurPos(best, true, false)
  end
end

-- Layer order --------------------------------------------------------------------------------------

-- True when tracks higher in the list are in front (Project Settings > Video > Track order: "Items in lower
-- numbered tracks replace higher", REAPER's default); false when the bottom track is in front.
function A.front_is_top()
  local ok, flags = reaper.get_config_var_string("projvidflags")
  if not ok then return true end
  return (math.floor(tonumber(flags) or 256) & 256) ~= 0
end

-- Inserts a track named `name` directly in front of `track` in the layer order. Returns it.
function A.insert_in_front_of(track, name)
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
  if not A.front_is_top() then idx = idx + 1 end
  reaper.InsertTrackAtIndex(idx, true)
  local t = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(t, "P_NAME", name, true)
  return t
end

-- Still images ----------------------------------------------------------------------------------------

-- picture formats that are always a single frame (GIF and WebP can be animated, so they are left as they are)
local STILL = { png = true, jpg = true, jpeg = true, bmp = true, tif = true, tiff = true, heic = true }
local HOLD = 86400   -- seconds a held still image lasts

function A.is_still(take)
  local src = take and reaper.GetMediaItemTake_Source(take)
  if not src or reaper.GetMediaSourceType(src, "") ~= "VIDEO" then return false end
  local ext = (reaper.GetMediaSourceFileName(src) or ""):match("%.(%w+)$")
  return ext ~= nil and STILL[ext:lower()] == true
end

-- REAPER plays a still image as a 5 s source: with Loop source off it disappears after 5 s, with it on the picture
-- repeats and effects that animate over the item (Scrolling Credits, Pan & Zoom) restart every 5 s. Wrapping the
-- image in a long section makes it hold for the whole item with one continuous clock. Returns the item's active take
-- (the take is rebuilt from the item's state chunk, so an earlier take pointer may no longer be valid).
function A.hold_still(item, take)
  if not A.is_still(take) then return take end
  local _, guid = reaper.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
  local ok, chunk = reaper.GetItemStateChunk(item, "", false)
  local at = ok and chunk:find("\nGUID " .. guid, 1, true)
  local s = at and chunk:find("\n<SOURCE VIDEO\n", at, true)
  local e = s and chunk:find("\n>", s + 1, true)
  if not e then return take end
  local block = chunk:sub(s + 1, e + 1)
  chunk = chunk:sub(1, s) .. "<SOURCE SECTION\nLENGTH " .. HOLD .. "\nSTARTPOS 0\nOVERLAP 0\n" .. block
          .. "\n>" .. chunk:sub(e + 2)
  reaper.SetItemStateChunk(item, chunk, false)
  reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  return reaper.GetActiveTake(item)
end

-- Selection -------------------------------------------------------------------------------------------

-- Makes `item` the only selected item, so the panel (which follows the selection) shows it.
function A.select_only_item(item)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.UpdateArrange()
end

-- Makes `track` the only selected track and clears the item selection, so the panel shows the track.
function A.select_only_track(track)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetOnlyTrackSelected(track)
  reaper.UpdateArrange()
end

-- Title carriers ------------------------------------------------------------------------------------

-- First item on `track` overlapping pos..pos+len, or nil.
function A.overlapping(track, pos, len)
  for k = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, k)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < pos + len - 1e-6 and p + l > pos + 1e-6 then return it, p, l end
  end
end

-- Track for a new title or callout at pos..pos+len: the front-most track named "Titles..." that is free then
-- (a track shows one item at a time), otherwise a new "Titles" track at the front of the layer order.
function A.titles_track(pos, len)
  local n, top = reaper.CountTracks(0), A.front_is_top()
  for k = 0, n - 1 do
    local tr = reaper.GetTrack(0, top and k or (n - 1 - k))
    local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if name:match("^Titles") and not A.overlapping(tr, pos, len) then return tr end
  end
  local idx = top and 0 or n
  reaper.InsertTrackAtIndex(idx, true)
  local track = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Titles", true)
  return track
end

-- Inserts a transparent carrier item (for titles and callouts) at the edit cursor or time selection on a Titles
-- track (A.titles_track) and selects only it. Returns the new target.
function A.add_carrier(carrier_png, text, length)
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local pos, len = reaper.GetCursorPosition(), length
  if te > ts then pos, len = ts, te - ts end
  local track = A.titles_track(pos, len)
  local item = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  local fade = math.min(0.5, len / 4)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade)
  reaper.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", 0)
  reaper.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", 0)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, reaper.PCM_Source_CreateFromFile(carrier_png))
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", text, true)
  take = A.hold_still(item, take)
  A.select_only_item(item)
  return { kind = "take", take = take, item = item, track = track }
end

function A.take_text(t)
  if t.kind ~= "take" then return nil end
  return select(2, reaper.GetSetMediaItemTakeInfo_String(t.take, "P_NAME", "", false))
end

function A.set_take_text(t, s)
  if t.kind == "take" then
    reaper.GetSetMediaItemTakeInfo_String(t.take, "P_NAME", s, true)
    reaper.UpdateArrange()
  end
end

return A
