-- @description Larry Seyer Video Effects: control panel for the Larry Seyer Video Effects Video Processor effects
-- @version 1.1.0
-- @author Larry Seyer
-- @about Library of video effects for REAPER's Video Processor with color wheels, curve editors, a frame pad
--   for positions and regions, keyframes at the edit cursor, and one-click titles and callouts.

local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
reaper.SetExtState("LS_VIDEO_FX", "path", DIR, true)  -- lets scripts and AI agents find this folder
if not reaper.ImGui_GetBuiltinPath then
  reaper.MB("Larry Seyer Video Effects needs the ReaImGui extension (install it with ReaPack).", "Larry Seyer Video Effects", 0)
  return
end
package.path = DIR .. "lib/?.lua;" .. reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ImGui = require "imgui" "0.10"
local L = require "lsvfx"
local A = require "fxapi"
local W = require "widgets"
W.init(ImGui)

local EFFECTS_DIR = DIR .. "effects"
local CARRIER = DIR .. "LS Title Carrier.png"
local INI = reaper.GetResourcePath() .. "/presets/builtin_video_processor.ini"

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

local EFFECTS = L.load_all(EFFECTS_DIR, list_files)
local BYNAME = {}
for _, e in ipairs(EFFECTS) do
  BYNAME[e.name] = e
  for _, old in ipairs(e.formerly) do BYNAME[old] = e end   -- instances saved under an earlier preset name
end
if L.needs_install(INI, EFFECTS) then L.install(INI, EFFECTS) end

local ctx = ImGui.CreateContext("Larry Seyer Video Effects")
local FONT = ImGui.CreateFont("sans-serif")
local FONT_B = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold)
ImGui.Attach(ctx, FONT)
ImGui.Attach(ctx, FONT_B)

local S = { locked = nil, sel = nil, filter = "", curve_tab = 1, hue_tab = 1, pending_undo = nil }

-- Helpers ------------------------------------------------------------------------------------------

local function target()
  if S.locked and A.valid(S.locked) then return S.locked end
  S.locked = nil
  return A.current_target()
end

local function undo_point(label)
  reaper.Undo_OnStateChange2(0, "Larry Seyer Video Effects: " .. label)
end

-- Writes a parameter; when it already has keyframes the value is keyed at the edit cursor.
local function write(t, fx, p, v)
  A.set(t, fx, p.index - 1, v)
  if A.keyframe_count(t, fx, p.index - 1) > 0 then A.set_key(t, fx, p.index - 1, v) end
end

local function read_all(t, fx, e)
  local vals = {}
  for _, p in ipairs(e.params) do vals[p.var] = A.get(t, fx, p.index - 1) or p.def end
  return vals
end

-- Screen position (0..1 of the frame) for a point parameter, following each effect's convention.
local function to_screen(p, v)
  if p.def == 0 and p.min < 0 then return 0.5 + v * ((p.max == 1) and 0.5 or 1) end
  return v
end
local function from_screen(p, s)
  local v = s
  if p.def == 0 and p.min < 0 then v = (s - 0.5) / ((p.max == 1) and 0.5 or 1) end
  return math.max(p.min, math.min(p.max, v))
end

local function small_text(s)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, W.TEXT_DIM)
  ImGui.TextWrapped(ctx, s)
  ImGui.PopStyleColor(ctx)
end

-- Keyframe diamond: hollow = no keyframes, filled = has keyframes, accent = keyframe at the cursor.
local function key_button(t, fx, p, v)
  local n = A.keyframe_count(t, fx, p.index - 1)
  local here = n > 0 and A.has_key_here(t, fx, p.index - 1)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local sz = ImGui.GetFrameHeight(ctx)
  ImGui.InvisibleButton(ctx, "##key" .. p.var, sz * 0.8, sz)
  local dl = ImGui.GetWindowDrawList(ctx)
  local cx, cy, r = x + sz * 0.4, y + sz / 2, sz * 0.26
  local col = here and W.ACCENT or (n > 0 and 0xC8CDD2FF or 0x5A626BFF)
  if n > 0 then ImGui.DrawList_AddQuadFilled(dl, cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy, col)
  else
    local pts = reaper.new_array({ cx, cy - r, cx + r, cy, cx, cy + r, cx - r, cy })
    ImGui.DrawList_AddPolyline(dl, pts, col, ImGui.DrawFlags_Closed, 1.5)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, here and "Remove keyframe at edit cursor" or "Add keyframe at edit cursor")
  end
  if ImGui.IsItemClicked(ctx) then
    if here then A.delete_key(t, fx, p.index - 1) else A.set_key(t, fx, p.index - 1, v) end
    undo_point("keyframe " .. p.label)
  end
end

local function after_edit(label)
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then undo_point(label) end
end

-- Parameter widgets --------------------------------------------------------------------------------

local function param_widget(t, fx, e, p, vals)
  key_button(t, fx, p, vals[p.var])
  ImGui.SameLine(ctx, 0, 4)
  local avail = ImGui.GetContentRegionAvail(ctx)
  ImGui.SetNextItemWidth(ctx, math.max(120, avail * 0.62))
  local v = vals[p.var]
  local changed, nv
  if e.enums[p.var] then
    changed, nv = ImGui.Combo(ctx, p.label .. "##" .. p.var, math.floor(v + 0.5), table.concat(e.enums[p.var], "\0") .. "\0")
  elseif e.toggles[p.var] then
    local c, b = ImGui.Checkbox(ctx, p.label .. "##" .. p.var, v > 0.5)
    changed, nv = c, b and 1 or 0
  elseif p.step == 1 then
    changed, nv = ImGui.SliderInt(ctx, p.label .. "##" .. p.var, math.floor(v + 0.5), math.floor(p.min), math.floor(p.max))
  else
    local fmt = (p.max - p.min) > 50 and "%.1f" or "%.3f"
    changed, nv = ImGui.SliderDouble(ctx, p.label .. "##" .. p.var, v, p.min, p.max, fmt)
  end
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) and not e.enums[p.var] then
    changed, nv = true, p.def
    undo_point("reset " .. p.label)
  end
  if changed then write(t, fx, p, nv); vals[p.var] = nv end
  if e.help[p.var] and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort) then ImGui.SetTooltip(ctx, e.help[p.var]) end
  after_edit(p.label)
end

local function color_widget(t, fx, e, c, vals)
  local pr, pg, pb = e.byvar[c.vars[1]], e.byvar[c.vars[2]], e.byvar[c.vars[3]]
  local function b(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
  local rgb = (b(vals[pr.var]) << 16) | (b(vals[pg.var]) << 8) | b(vals[pb.var])
  ImGui.Dummy(ctx, ImGui.GetFrameHeight(ctx) * 0.8, 1)
  ImGui.SameLine(ctx, 0, 4)
  local changed, nrgb = ImGui.ColorEdit3(ctx, c.label .. "##" .. c.vars[1], rgb, ImGui.ColorEditFlags_NoInputs)
  if e.help[c.vars[1]] and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort) then ImGui.SetTooltip(ctx, e.help[c.vars[1]]) end
  if changed then
    write(t, fx, pr, ((nrgb >> 16) & 255) / 255)
    write(t, fx, pg, ((nrgb >> 8) & 255) / 255)
    write(t, fx, pb, (nrgb & 255) / 255)
  end
  after_edit(c.label)
end

local function wheels_row(t, fx, e, vals)
  local avail = ImGui.GetContentRegionAvail(ctx)
  local n = #e.wheels
  local size = math.min(170, (avail - (n - 1) * 10) / n)
  for k, wh in ipairs(e.wheels) do
    if k > 1 then ImGui.SameLine(ctx, 0, 10) end
    ImGui.BeginGroup(ctx)
    local pr = e.byvar[wh.vars[1]]
    local range = pr.max * 0.7
    local changed, r, g, b = W.wheel(ctx, "##wheel" .. k, wh.label, vals[wh.vars[1]], vals[wh.vars[2]], vals[wh.vars[3]], range, size)
    if e.help[wh.vars[1]] and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort) then ImGui.SetTooltip(ctx, e.help[wh.vars[1]]) end
    if changed then
      write(t, fx, e.byvar[wh.vars[1]], r); write(t, fx, e.byvar[wh.vars[2]], g); write(t, fx, e.byvar[wh.vars[3]], b)
      S.pending_undo = wh.label
    end
    local pm = e.byvar[wh.master]
    ImGui.SetNextItemWidth(ctx, size)
    local mc, mv = ImGui.SliderDouble(ctx, "##m" .. k, vals[wh.master], pm.min, pm.max, wh.label .. " %.3f")
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then mc, mv = true, pm.def end
    if mc then write(t, fx, pm, mv) end
    after_edit(wh.label .. " master")
    ImGui.EndGroup(ctx)
  end
end

local CURVE_COLORS = { 0xE6EAEEFF, 0xFF5A5AFF, 0x4CD964FF, 0x4C8DFFFF }

local function curves_block(t, fx, e, vals)
  for k, c in ipairs(e.curves) do
    if k > 1 then ImGui.SameLine(ctx) end
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, S.curve_tab == k and W.ACCENT_DIM or 0x2B3138FF)
    if ImGui.Button(ctx, c.label .. "##ct" .. k) then S.curve_tab = k end
    ImGui.PopStyleColor(ctx)
  end
  local list = {}
  for k, c in ipairs(e.curves) do
    local vs = {}
    for i, var in ipairs(c.vars) do vs[i] = vals[var] end
    list[k] = { label = c.label, color = CURVE_COLORS[k] or W.ACCENT, values = vs }
  end
  local w = math.min(ImGui.GetContentRegionAvail(ctx), 420)
  local idx, v = W.curve_editor(ctx, "##curves", list, S.curve_tab, w, w * 0.62)
  if idx then
    write(t, fx, e.byvar[e.curves[S.curve_tab].vars[idx]], v)
    S.pending_undo = "curve"
  end
  small_text("Drag points up or down. Double-click a point to reset it.")
end

local function hue_block(t, fx, e, vals)
  for k, c in ipairs(e.huecurves) do
    if k > 1 then ImGui.SameLine(ctx) end
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, S.hue_tab == k and W.ACCENT_DIM or 0x2B3138FF)
    if ImGui.Button(ctx, c.label .. "##ht" .. k) then S.hue_tab = k end
    ImGui.PopStyleColor(ctx)
  end
  local c = e.huecurves[S.hue_tab]
  local p1 = e.byvar[c.vars[1]]
  local vs = {}
  for i, var in ipairs(c.vars) do vs[i] = vals[var] end
  local w = math.min(ImGui.GetContentRegionAvail(ctx), 480)
  local idx, v = W.hue_curve_editor(ctx, "##hue", vs, p1.min, p1.max, p1.def, w, w * 0.4)
  if idx then write(t, fx, e.byvar[c.vars[idx]], v); S.pending_undo = "hue curve" end
end

local function pad_block(t, fx, e, vals)
  local handles, map = {}, {}
  for _, r in ipairs(e.rects) do
    handles[#handles + 1] = { kind = "rect", label = r.label, x = vals[r.vars[1]], y = vals[r.vars[2]],
                              w = vals[r.vars[3]], h = vals[r.vars[4]] }
    map[#handles] = { kind = "rect", vars = r.vars }
  end
  for _, pt in ipairs(e.points) do
    local px, py = e.byvar[pt.vars[1]], e.byvar[pt.vars[2]]
    handles[#handles + 1] = { kind = "point", label = pt.label, x = to_screen(px, vals[px.var]), y = to_screen(py, vals[py.var]) }
    map[#handles] = { kind = "point", vars = pt.vars }
  end
  local w = math.min(ImGui.GetContentRegionAvail(ctx), 460)
  local i, x, y, ww, hh = W.frame_pad(ctx, "##pad", handles, w, 16 / 9)
  if i then
    local m = map[i]
    if m.kind == "rect" then
      write(t, fx, e.byvar[m.vars[1]], x); write(t, fx, e.byvar[m.vars[2]], y)
      write(t, fx, e.byvar[m.vars[3]], ww); write(t, fx, e.byvar[m.vars[4]], hh)
    else
      write(t, fx, e.byvar[m.vars[1]], from_screen(e.byvar[m.vars[1]], x))
      write(t, fx, e.byvar[m.vars[2]], from_screen(e.byvar[m.vars[2]], y))
    end
    S.pending_undo = "position"
  end
  small_text("Drag on the frame: move points and regions, resize regions from the corner square.")
end

-- Editor for one effect instance -------------------------------------------------------------------

local function consumed_vars(e)
  local used = {}
  for _, wh in ipairs(e.wheels) do for _, v in ipairs(wh.vars) do used[v] = true end used[wh.master] = true end
  for _, c in ipairs(e.curves) do for _, v in ipairs(c.vars) do used[v] = true end end
  for _, c in ipairs(e.huecurves) do for _, v in ipairs(c.vars) do used[v] = true end end
  return used
end

local function color_group_of(e, var)
  for _, c in ipairs(e.colors) do for _, v in ipairs(c.vars) do if v == var then return c end end end
end

local function editor_header(t, fx, e)
  ImGui.PushFont(ctx, FONT_B, 18)
  ImGui.Text(ctx, e.title)
  ImGui.PopFont(ctx)
  small_text(e.about or "")
  if ImGui.Button(ctx, "< Key") then A.jump_key(t, fx, #e.params, -1) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Move the edit cursor to the previous keyframe") end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Keyframe all") then
    for _, p in ipairs(e.params) do A.set_key(t, fx, p.index - 1, A.get(t, fx, p.index - 1)) end
    undo_point("keyframe all")
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Key every control at the edit cursor") end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Key >") then A.jump_key(t, fx, #e.params, 1) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Reset") then
    for _, p in ipairs(e.params) do write(t, fx, p, p.def) end
    undo_point("reset " .. e.title)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "FX window") then A.show(t, fx) end
  if e.text then
    if t.kind == "take" then
      ImGui.SetNextItemWidth(ctx, -1)
      local changed, s = ImGui.InputText(ctx, "##text", A.take_text(t) or "")
      if changed then A.set_take_text(t, s) end
      after_edit("text")
      small_text(e.text .. ". Use | to start a new line.")
    else
      small_text("Text comes from the item name: add this effect to an item (or use the Title buttons).")
    end
  end
end

local function draw_editor(t, fx, e)
  editor_header(t, fx, e)
  local vals = read_all(t, fx, e)
  ImGui.Spacing(ctx)
  if #e.wheels > 0 then wheels_row(t, fx, e, vals) end
  if #e.curves > 0 then curves_block(t, fx, e, vals) end
  if #e.huecurves > 0 then hue_block(t, fx, e, vals) end
  if #e.rects + #e.points > 0 then pad_block(t, fx, e, vals) end
  local done = consumed_vars(e)
  local function emit(var)
    if done[var] then return end
    local cg = color_group_of(e, var)
    if cg then
      for _, v in ipairs(cg.vars) do done[v] = true end
      color_widget(t, fx, e, cg, vals)
    elseif e.byvar[var] then
      done[var] = true
      param_widget(t, fx, e, e.byvar[var], vals)
    end
  end
  for _, sec in ipairs(e.sections) do
    ImGui.SeparatorText(ctx, sec.label)
    for _, var in ipairs(sec.vars) do emit(var) end
  end
  local rest = {}
  for _, p in ipairs(e.params) do if not done[p.var] and not p.hidden then rest[#rest + 1] = p.var end end
  if #rest > 0 then
    ImGui.SeparatorText(ctx, #e.sections > 0 and "More" or "Settings")
    for _, var in ipairs(rest) do emit(var) end
  end
  if S.pending_undo and ImGui.IsMouseReleased(ctx, ImGui.MouseButton_Left) then
    undo_point(S.pending_undo)
    S.pending_undo = nil
  end
end

-- Library ------------------------------------------------------------------------------------------

local function add_effect(t, e)
  reaper.Undo_BeginBlock()
  local dest = t
  if e.where == "item" and (not t or t.kind ~= "take") then
    dest = A.add_carrier(CARRIER, e.text and (e.category == "Title" and "Title | Subtitle" or "Label") or "", 5)
    S.locked = dest
  elseif e.where == "track" and t and t.kind == "take" then
    dest = { kind = "track", track = t.track }
    S.locked = dest
  end
  if not dest then
    reaper.Undo_EndBlock("Larry Seyer Video Effects: add " .. e.title, -1)
    reaper.MB("Select a track or an item first.", "Larry Seyer Video Effects", 0)
    return
  end
  local fx = A.add(dest, e.name)
  S.sel = fx
  reaper.Undo_EndBlock("Larry Seyer Video Effects: add " .. e.title, -1)
end

local function draw_library(t)
  ImGui.SetNextItemWidth(ctx, -1)
  local _, f = ImGui.InputTextWithHint(ctx, "##filter", "Search effects", S.filter)
  S.filter = f
  local q = S.filter:lower()
  local cat
  local open = true
  for _, e in ipairs(EFFECTS) do
    local match = e.where ~= "monitor"   -- Monitoring FX effects are managed by their own actions
      and (q == "" or e.title:lower():find(q, 1, true) or (e.about or ""):lower():find(q, 1, true))
    if match then
      if e.category ~= cat then
        cat = e.category
        open = ImGui.CollapsingHeader(ctx, cat, nil, (q ~= "" or cat == "Transform") and ImGui.TreeNodeFlags_DefaultOpen or 0)
      end
      if open then
        if ImGui.Selectable(ctx, "  " .. e.title .. "##lib" .. e.file) then add_effect(t, e) end
        if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_DelayShort) then
          local where = e.where == "item" and "Adds a title item if no item is selected."
                     or e.where == "track" and "Goes on the track (works on crossfades between its items)."
                     or "Goes on the selected item, or the selected track."
          ImGui.SetTooltip(ctx, (e.about or "") .. "\n\n" .. where)
        end
      end
    end
  end
end

-- Chain list ---------------------------------------------------------------------------------------

local function draw_chain(t, inst)
  if #inst == 0 then
    small_text("No effects here yet. Pick one from the library on the left.")
    return
  end
  for k, it in ipairs(inst) do
    ImGui.PushID(ctx, k)
    local on = A.enabled(t, it.fx)
    local c, nv = ImGui.Checkbox(ctx, "##on", on)
    if c then A.set_enabled(t, it.fx, nv); undo_point("toggle " .. it.label) end
    ImGui.SameLine(ctx)
    local label = it.effect and it.label or (it.label .. "  (not an LS effect)")
    if ImGui.Selectable(ctx, label, S.sel == it.fx, 0, ImGui.GetContentRegionAvail(ctx) - 150) then S.sel = it.fx end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Up") and k > 1 then A.move(t, it.fx, it.fx - 1); S.sel = it.fx - 1; undo_point("move") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Down") and k < #inst then A.move(t, it.fx, it.fx + 1); S.sel = it.fx + 1; undo_point("move") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "X") then A.delete(t, it.fx); undo_point("remove " .. it.label); S.sel = nil end
    ImGui.PopID(ctx)
  end
end

-- Main window --------------------------------------------------------------------------------------

local function toolbar(t)
  ImGui.PushFont(ctx, FONT_B, 15)
  ImGui.TextColored(ctx, W.ACCENT, "Larry Seyer Video Effects")
  ImGui.PopFont(ctx)
  ImGui.SameLine(ctx)
  ImGui.TextColored(ctx, W.TEXT_DIM, "  " .. A.describe(t))
  ImGui.SameLine(ctx)
  local lk = S.locked ~= nil
  local c, nv = ImGui.Checkbox(ctx, "Lock", lk)
  if c then S.locked = nv and t or nil end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Keep editing this item or track while you select others") end
  ImGui.SameLine(ctx)
  for _, q in ipairs({ { "Lower third", "LS Title: Lower Third", "Your Name | Subtitle" },
                       { "Title", "LS Title: Title & Subtitle", "Title | Subtitle" },
                       { "Callout", "LS Tutorial: Callout", "Label" } }) do
    if ImGui.SmallButton(ctx, "+ " .. q[1]) then
      reaper.Undo_BeginBlock()
      local dest = A.add_carrier(CARRIER, q[3], 5)
      S.sel = A.add(dest, q[2]); S.locked = dest
      reaper.Undo_EndBlock("Larry Seyer Video Effects: add " .. q[1], -1)
    end
    ImGui.SameLine(ctx)
  end
  if ImGui.SmallButton(ctx, "Multicam") then
    reaper.Main_OnCommand(reaper.AddRemoveReaScript(true, 0, DIR .. "Larry Seyer Video Effects - Multicam.lua", true), 0)
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open the multicam switcher: cut between camera tracks with the number keys or clicks") end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Help") then
    if reaper.CF_ShellExecute then reaper.CF_ShellExecute(L.MANUAL_URL) else os.execute('open "' .. L.MANUAL_URL .. '"') end
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open the illustrated manual in your browser") end
  ImGui.Separator(ctx)
end

local function frame()
  local t = target()
  toolbar(t)
  local avail_w, avail_h = ImGui.GetContentRegionAvail(ctx)
  if ImGui.BeginChild(ctx, "lib", 230, avail_h, ImGui.ChildFlags_Borders) then
    draw_library(t)
    ImGui.EndChild(ctx)
  end
  ImGui.SameLine(ctx)
  if ImGui.BeginChild(ctx, "main", avail_w - 238, avail_h, ImGui.ChildFlags_Borders) then
    if t then
      local inst = A.instances(t, BYNAME)
      draw_chain(t, inst)
      ImGui.Separator(ctx)
      local cur
      for _, it in ipairs(inst) do if it.fx == S.sel then cur = it end end
      if not cur then
        for _, it in ipairs(inst) do if it.effect then cur = it; S.sel = it.fx; break end end
      end
      if cur and cur.effect then draw_editor(t, cur.fx, cur.effect)
      elseif cur then small_text("This plug-in is not part of Larry Seyer Video Effects; open it with its own window.") end
    else
      small_text("Select a track or an item to add and edit video effects.")
    end
    ImGui.EndChild(ctx)
  end
end

local function loop()
  ImGui.PushFont(ctx, FONT, 14)
  local nc, nv = W.push_theme(ctx)
  ImGui.SetNextWindowSize(ctx, 900, 780, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "Larry Seyer Video Effects", true)
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
