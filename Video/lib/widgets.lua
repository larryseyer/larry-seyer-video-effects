-- Custom ReaImGui controls for the Larry Seyer Video Effects panel: color wheels, curve editors, a frame pad for
-- positions and regions, and the panel theme. Every widget returns changed values; the caller writes them.

local W = {}
local ImGui

function W.init(imgui) ImGui = imgui end

-- Colors -------------------------------------------------------------------------------------------

W.ACCENT = 0x3DDDA8FF
W.ACCENT_DIM = 0x2A9C77FF
W.TEXT_DIM = 0x9AA3ADFF
W.BG = 0x15181CFF
W.PANEL = 0x1D2126FF
W.FRAME = 0x262B31FF

function W.rgba(r, g, b, a)
  local function c(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
  return (c(r) << 24) | (c(g) << 16) | (c(b) << 8) | c(a or 1)
end

function W.hsv(h, s, v, a)
  h = (h % 360) / 60
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  local r, g, b
  if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
  return W.rgba(r, g, b, a)
end

function W.push_theme(ctx)
  local C = {
    { ImGui.Col_WindowBg, W.BG }, { ImGui.Col_ChildBg, W.PANEL }, { ImGui.Col_PopupBg, 0x1A1E23F8 },
    { ImGui.Col_Border, 0x30363DFF }, { ImGui.Col_FrameBg, W.FRAME }, { ImGui.Col_FrameBgHovered, 0x313840FF },
    { ImGui.Col_FrameBgActive, 0x39414AFF }, { ImGui.Col_TitleBg, W.BG }, { ImGui.Col_TitleBgActive, 0x1B2025FF },
    { ImGui.Col_Button, 0x2B3138FF }, { ImGui.Col_ButtonHovered, 0x36404AFF }, { ImGui.Col_ButtonActive, W.ACCENT_DIM },
    { ImGui.Col_Header, 0x2B3138FF }, { ImGui.Col_HeaderHovered, 0x34404AFF }, { ImGui.Col_HeaderActive, W.ACCENT_DIM },
    { ImGui.Col_SliderGrab, W.ACCENT_DIM }, { ImGui.Col_SliderGrabActive, W.ACCENT }, { ImGui.Col_CheckMark, W.ACCENT },
    { ImGui.Col_Separator, 0x30363DFF }, { ImGui.Col_Text, 0xE6EAEEFF }, { ImGui.Col_TextDisabled, 0x6B747EFF },
    { ImGui.Col_Tab, 0x2B3138FF },
  }
  for _, c in ipairs(C) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  local V = {
    { ImGui.StyleVar_WindowRounding, 8 }, { ImGui.StyleVar_ChildRounding, 8 }, { ImGui.StyleVar_FrameRounding, 5 },
    { ImGui.StyleVar_GrabRounding, 5 }, { ImGui.StyleVar_WindowPadding, 12, 12 }, { ImGui.StyleVar_FramePadding, 8, 5 },
    { ImGui.StyleVar_ItemSpacing, 8, 7 },
  }
  for _, v in ipairs(V) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
  return #C, #V
end

-- Color wheel --------------------------------------------------------------------------------------
-- RGB offsets map to a point on the wheel: red at the top, green lower right, blue lower left.

local DIRS = { { 0, -1 }, { math.cos(math.rad(30)), math.sin(math.rad(30)) }, { math.cos(math.rad(150)), math.sin(math.rad(150)) } }

local function rgb_to_xy(r, g, b)
  return r * DIRS[1][1] + g * DIRS[2][1] + b * DIRS[3][1], r * DIRS[1][2] + g * DIRS[2][2] + b * DIRS[3][2]
end

local function xy_to_rgb(x, y)
  local out = {}
  for k = 1, 3 do out[k] = (x * DIRS[k][1] + y * DIRS[k][2]) * 2 / 3 end
  return out[1], out[2], out[3]
end

-- Draws a wheel of diameter `size`; `range` is the offset at the rim. Returns changed, r, g, b.
function W.wheel(ctx, id, label, r, g, b, range, size)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local cx, cy, rad = x0 + size / 2, y0 + size / 2, size / 2 - 4
  local seg = 72
  for k = 0, seg - 1 do
    local a1, a2 = (k / seg) * 2 * math.pi - math.pi / 2, ((k + 1) / seg) * 2 * math.pi - math.pi / 2
    local col = W.hsv(k / seg * 360, 0.75, 0.85, 0.95)
    ImGui.DrawList_AddTriangleFilled(dl, cx, cy, cx + math.cos(a1) * rad, cy + math.sin(a1) * rad,
      cx + math.cos(a2) * rad, cy + math.sin(a2) * rad, col)
  end
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, rad * 0.86, 0x1C2024E6, 64)
  for k = 1, 3 do
    ImGui.DrawList_AddLine(dl, cx, cy, cx + DIRS[k][1] * rad * 0.86, cy + DIRS[k][2] * rad * 0.86, 0xFFFFFF14, 1)
  end
  ImGui.DrawList_AddCircle(dl, cx, cy, rad * 0.43, 0xFFFFFF14, 48, 1)
  ImGui.InvisibleButton(ctx, id, size, size)
  local changed = false
  if ImGui.IsItemActive(ctx) then
    local mx, my = ImGui.GetMousePos(ctx)
    local dx, dy = (mx - cx) / (rad * 0.86), (my - cy) / (rad * 0.86)
    local l = math.sqrt(dx * dx + dy * dy)
    if l > 1 then dx, dy = dx / l, dy / l end
    if ImGui.GetKeyMods(ctx) & ImGui.Mod_Shift ~= 0 then dx, dy = dx * 0.25, dy * 0.25 end
    r, g, b = xy_to_rgb(dx * range, dy * range)
    changed = true
  end
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    r, g, b, changed = 0, 0, 0, true
  end
  local px, py = rgb_to_xy(r, g, b)
  local qx, qy = cx + px / range * rad * 0.86, cy + py / range * rad * 0.86
  ImGui.DrawList_AddLine(dl, cx, cy, qx, qy, 0xFFFFFF55, 1)
  ImGui.DrawList_AddCircleFilled(dl, qx, qy, 6, 0xFFFFFFFF, 16)
  ImGui.DrawList_AddCircle(dl, qx, qy, 6, 0x000000AA, 16, 1.5)
  local tw = ImGui.CalcTextSize(ctx, label)
  ImGui.DrawList_AddText(dl, cx - tw / 2, cy + rad * 0.5, 0xFFFFFF90, label)
  return changed, r, g, b
end

-- Curves -------------------------------------------------------------------------------------------

-- Same monotone cubic the Curves effect uses (7 evenly spaced points).
function W.mono_curve(pts, v)
  local seg = math.min(math.floor(v * 6), 5)
  local t, hx = v * 6 - seg, 1 / 6
  local y0, y1 = pts[seg + 1], pts[seg + 2]
  local k = (y1 - y0) / hx
  local d0 = seg > 0 and (pts[seg + 1] - pts[seg]) / hx or k
  local d1 = seg < 5 and (pts[seg + 3] - pts[seg + 2]) / hx or k
  local m0 = d0 * k <= 0 and 0 or (d0 + k) / 2
  local m1 = d1 * k <= 0 and 0 or (d1 + k) / 2
  if k == 0 then m0, m1 = 0, 0 end
  if math.abs(m0) > 3 * math.abs(k) then m0 = 3 * k end
  if math.abs(m1) > 3 * math.abs(k) then m1 = 3 * k end
  local t2, t3 = t * t, t * t * t
  return y0 * (2 * t3 - 3 * t2 + 1) + hx * m0 * (t3 - 2 * t2 + t) + y1 * (-2 * t3 + 3 * t2) + hx * m1 * (t3 - t2)
end

-- Periodic Catmull-Rom through 6 hue points, same as the Hue Curves effect.
function W.hue_interp(pts, deg)
  local seg = math.floor(deg / 60) % 6
  local t = deg / 60 - math.floor(deg / 60)
  local p0, p1, p2, p3 = pts[(seg + 5) % 6 + 1], pts[seg + 1], pts[(seg + 1) % 6 + 1], pts[(seg + 2) % 6 + 1]
  return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
end

-- Curve editor for 7-point curves. `curves` = list of { label, color, values{7} }, `sel` index edited.
-- Returns index of changed point (1..7) and its new value, or nil.
function W.curve_editor(ctx, id, curves, sel, w, h)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, 0x111417FF, 6)
  for k = 1, 3 do
    ImGui.DrawList_AddLine(dl, x0 + w * k / 4, y0, x0 + w * k / 4, y0 + h, 0xFFFFFF10, 1)
    ImGui.DrawList_AddLine(dl, x0, y0 + h * k / 4, x0 + w, y0 + h * k / 4, 0xFFFFFF10, 1)
  end
  ImGui.DrawList_AddLine(dl, x0, y0 + h, x0 + w, y0, 0xFFFFFF18, 1)
  for ci, c in ipairs(curves) do
    local col = ci == sel and c.color or ((c.color & 0xFFFFFF00) | 0x50)
    local pts = reaper.new_array(130)
    for s = 0, 64 do
      local v = s / 64
      local y = math.max(0, math.min(1, W.mono_curve(c.values, v)))
      pts[s * 2 + 1], pts[s * 2 + 2] = x0 + v * w, y0 + (1 - y) * h
    end
    ImGui.DrawList_AddPolyline(dl, pts, col, 0, ci == sel and 2.5 or 1.2)
  end
  ImGui.InvisibleButton(ctx, id, w, h)
  local c = curves[sel]
  local hovered_pt
  local mx, my = ImGui.GetMousePos(ctx)
  for k = 1, 7 do
    local px, py = x0 + (k - 1) / 6 * w, y0 + (1 - c.values[k]) * h
    if math.abs(mx - px) < w / 14 then hovered_pt = k end
    ImGui.DrawList_AddCircleFilled(dl, px, py, 5, c.color, 12)
    ImGui.DrawList_AddCircle(dl, px, py, 5, 0x000000AA, 12, 1.5)
  end
  if ImGui.IsItemActivated(ctx) then W._drag_pt = hovered_pt end
  if ImGui.IsItemActive(ctx) and W._drag_pt then
    local v = math.max(0, math.min(1, 1 - (my - y0) / h))
    return W._drag_pt, v
  end
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) and hovered_pt then
    return hovered_pt, (hovered_pt - 1) / 6
  end
  return nil
end

-- Hue curve editor: 6 points over the hue circle. Returns changed point index and value, or nil.
function W.hue_curve_editor(ctx, id, values, vmin, vmax, vdef, w, h)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + h, 0x111417FF, 6)
  local band = 10
  for s = 0, 59 do
    ImGui.DrawList_AddRectFilled(dl, x0 + w * s / 60, y0 + h - band, x0 + w * (s + 1) / 60 + 1, y0 + h,
      W.hsv(s * 6, 0.8, 0.9, 1))
  end
  local function ypos(v) return y0 + (1 - (v - vmin) / (vmax - vmin)) * (h - band) end
  ImGui.DrawList_AddLine(dl, x0, ypos(vdef), x0 + w, ypos(vdef), 0xFFFFFF22, 1)
  local pts = reaper.new_array(146)
  for s = 0, 72 do
    local d = s * 5
    pts[s * 2 + 1], pts[s * 2 + 2] = x0 + d / 360 * w, ypos(math.max(vmin, math.min(vmax, W.hue_interp(values, d))))
  end
  ImGui.DrawList_AddPolyline(dl, pts, W.ACCENT, 0, 2.2)
  ImGui.InvisibleButton(ctx, id, w, h)
  local mx, my = ImGui.GetMousePos(ctx)
  local hovered_pt
  for k = 1, 6 do
    local cx = x0 + (k - 1) * 60 / 360 * w
    if math.abs(mx - cx) < w / 12 then hovered_pt = k end
    ImGui.DrawList_AddCircleFilled(dl, cx, ypos(values[k]), 5, W.hsv((k - 1) * 60, 0.8, 1, 1), 12)
    ImGui.DrawList_AddCircle(dl, cx, ypos(values[k]), 5, 0x000000AA, 12, 1.5)
  end
  if ImGui.IsItemActivated(ctx) then W._drag_hue = hovered_pt end
  if ImGui.IsItemActive(ctx) and W._drag_hue then
    local v = vmin + (1 - (my - y0) / (h - band)) * (vmax - vmin)
    return W._drag_hue, math.max(vmin, math.min(vmax, v))
  end
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) and hovered_pt then
    return hovered_pt, vdef
  end
  return nil
end

-- Frame pad ----------------------------------------------------------------------------------------
-- A picture-shaped area for dragging points and regions. `handles` is a list of
-- { kind = "point"|"rect", label, x, y, w, h } in screen-normalized 0..1 coordinates.
-- Returns index of the edited handle and its new normalized values (x, y, w, h), or nil.

function W.frame_pad(ctx, id, handles, w, aspect)
  local h = w / aspect
  local dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddRectFilledMultiColor(dl, x0, y0, x0 + w, y0 + h, 0x22272DFF, 0x22272DFF, 0x16191DFF, 0x16191DFF)
  for k = 1, 2 do
    ImGui.DrawList_AddLine(dl, x0 + w * k / 3, y0, x0 + w * k / 3, y0 + h, 0xFFFFFF12, 1)
    ImGui.DrawList_AddLine(dl, x0, y0 + h * k / 3, x0 + w, y0 + h * k / 3, 0xFFFFFF12, 1)
  end
  ImGui.DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, 0xFFFFFF30, 4, 0, 1)
  ImGui.DrawList_PushClipRect(dl, x0 - 8, y0 - 8, x0 + w + 8, y0 + h + 8, true)
  for _, hd in ipairs(handles) do
    if hd.kind == "rect" then
      local ax, ay, bx, by = x0 + hd.x * w, y0 + hd.y * h, x0 + (hd.x + hd.w) * w, y0 + (hd.y + hd.h) * h
      ImGui.DrawList_AddRectFilled(dl, ax, ay, bx, by, 0x3DDDA826, 3)
      ImGui.DrawList_AddRect(dl, ax, ay, bx, by, W.ACCENT, 3, 0, 1.5)
      ImGui.DrawList_AddRectFilled(dl, bx - 5, by - 5, bx + 5, by + 5, W.ACCENT, 2)
      ImGui.DrawList_AddText(dl, ax + 4, ay + 2, 0xFFFFFFB0, hd.label)
    else
      local px, py = x0 + hd.x * w, y0 + hd.y * h
      ImGui.DrawList_AddCircleFilled(dl, px, py, 7, 0xFFFFFFE6, 16)
      ImGui.DrawList_AddCircle(dl, px, py, 7, W.ACCENT, 16, 2)
      ImGui.DrawList_AddText(dl, px + 10, py - 7, 0xFFFFFFB0, hd.label)
    end
  end
  ImGui.DrawList_PopClipRect(dl)
  ImGui.InvisibleButton(ctx, id, w, h)
  local mx, my = ImGui.GetMousePos(ctx)
  local nx, ny = (mx - x0) / w, (my - y0) / h
  if ImGui.IsItemActivated(ctx) then
    W._pad = nil
    for i = #handles, 1, -1 do
      local hd = handles[i]
      if hd.kind == "rect" then
        local bx, by = hd.x + hd.w, hd.y + hd.h
        if math.abs(nx - bx) * w < 9 and math.abs(ny - by) * h < 9 then W._pad = { i = i, mode = "size" } break end
        if nx >= hd.x and nx <= bx and ny >= hd.y and ny <= by then
          W._pad = { i = i, mode = "move", ox = nx - hd.x, oy = ny - hd.y } break
        end
      elseif math.abs(nx - hd.x) * w < 11 and math.abs(ny - hd.y) * h < 11 then
        W._pad = { i = i, mode = "point" } break
      end
    end
  end
  if ImGui.IsItemActive(ctx) and W._pad then
    local hd = handles[W._pad.i]
    if W._pad.mode == "point" then return W._pad.i, nx, ny end
    if W._pad.mode == "move" then
      return W._pad.i, math.max(0, math.min(1 - hd.w, nx - W._pad.ox)), math.max(0, math.min(1 - hd.h, ny - W._pad.oy)), hd.w, hd.h
    end
    return W._pad.i, hd.x, hd.y, math.max(0.01, math.min(1 - hd.x, nx - hd.x)), math.max(0.01, math.min(1 - hd.y, ny - hd.y))
  end
  return nil
end

return W
