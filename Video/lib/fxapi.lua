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

-- Envelope time for the edit cursor (take envelopes are relative to the item start).
function A.env_time(t)
  local cur = reaper.GetCursorPosition()
  if t.kind == "take" then
    local rate = reaper.GetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE")
    return (cur - reaper.GetMediaItemInfo_Value(t.item, "D_POSITION")) * rate
  end
  return cur
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

-- Title carriers ------------------------------------------------------------------------------------

-- Inserts a transparent carrier item (for titles and callouts) at the edit cursor or time selection,
-- on the selected track or a new "Titles" track at the front of the layer order. Returns the new target.
function A.add_carrier(carrier_png, text, length)
  local track = reaper.GetSelectedTrack(0, 0)
  if not track then
    local idx = A.front_is_top() and 0 or reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    track = reaper.GetTrack(0, idx)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "Titles", true)
  end
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local pos, len = reaper.GetCursorPosition(), length
  if te > ts then pos, len = ts, te - ts end
  -- a track shows one item at a time: put overlapping graphics on a new track in front of it
  for k = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, k)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p < pos + len - 1e-6 and p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") > pos + 1e-6 then
      track = A.insert_in_front_of(track, "Titles")
      break
    end
  end
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
  reaper.SetMediaItemSelected(item, true)
  reaper.UpdateArrange()
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
