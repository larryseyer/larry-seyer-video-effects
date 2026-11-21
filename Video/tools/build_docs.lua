-- Generates the documentation from the effect files (the single source of truth):
--   docs/effects.json, docs/AI-REFERENCE.md, docs/MANUAL.md, ai/claude-skill/larry-seyer-video-effects/{SKILL.md,reference.md}
-- Run from anywhere with a plain Lua interpreter:  lua tools/build_docs.lua <pack folder>

local ROOT = (arg[1] or "."):gsub("/$", "") .. "/"
package.path = ROOT .. "lib/?.lua;" .. package.path
local L = require "lsvfx"

local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local function write(p, s) local f = assert(io.open(p, "wb")) f:write(s) f:close() end
local function list_files(dir)
  local out = {}
  local p = io.popen('ls "' .. dir .. '"')
  for f in p:lines() do out[#out + 1] = f end
  p:close()
  return out
end

local VERSION = read(ROOT .. "Larry Seyer Video Effects.lua"):match("@version%s+(%S+)") or "0"
local CONF = {}
for k, v in read(ROOT .. "tools/release.conf"):gmatch("([%w_]+)%s*=%s*([^\n]+)") do CONF[k] = v end
local INDEX_URL = "https://raw.githubusercontent.com/" .. CONF.repo .. "/main/index.xml"
local EFFECTS = L.load_all(ROOT .. "effects", list_files)

local PLACEMENT = { item = "an item (usually a transparent title item; see rule 3)", track = "a track", both = "an item or a track" }
local PLACEMENT_SHORT = { item = "Item (title item)", track = "Track", both = "Item or track" }

local function num(v)
  if v == math.floor(v) and math.abs(v) < 1e9 then return string.format("%d", v) end
  return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function fill(s) return (s:gsub("{{VERSION}}", VERSION):gsub("{{COUNT}}", tostring(#EFFECTS)):gsub("{{INDEX_URL}}", INDEX_URL)) end

-- Describes what kind of control a parameter is and which grouped widget (if any) it belongs to.
local function group_of(e, var)
  for _, c in ipairs(e.colors) do
    for k, v in ipairs(c.vars) do if v == var then return "color", c, k end end
  end
  for _, w in ipairs(e.wheels) do
    for k, v in ipairs(w.vars) do if v == var then return "wheel", w, k end end
    if w.master == var then return "wheelmaster", w end
  end
  for _, c in ipairs(e.curves) do for k, v in ipairs(c.vars) do if v == var then return "curve", c, k end end end
  for _, c in ipairs(e.huecurves) do for k, v in ipairs(c.vars) do if v == var then return "huecurve", c, k end end end
  return nil
end

local RGB = { "Red", "Green", "Blue" }
local CURVE_POS = { "0%", "17%", "33%", "50%", "67%", "83%", "100%" }
local HUES = { "red", "yellow", "green", "cyan", "blue", "magenta" }

local function meaning(e, p)
  local kind, g, k = group_of(e, p.var)
  local parts = {}
  if kind == "color" then parts[#parts + 1] = RGB[k] .. " part of " .. g.label .. " (0..1)."
  elseif kind == "wheel" then parts[#parts + 1] = RGB[k] .. " offset of the " .. g.label .. " wheel."
  elseif kind == "curve" then parts[#parts + 1] = g.label .. " curve output at input " .. CURVE_POS[k] .. "."
  elseif kind == "huecurve" then parts[#parts + 1] = g.label .. " for " .. HUES[k] .. "."
  end
  local h = e.help[p.var] or (g and g.vars and e.help[g.vars[1]])
  if h and not (kind == "color") then parts[#parts + 1] = h end
  if e.enums[p.var] then
    local o = {}
    for i, name in ipairs(e.enums[p.var]) do o[#o + 1] = (i - 1) .. " " .. name end
    parts[#parts + 1] = "Options: " .. table.concat(o, ", ") .. "."
  elseif e.toggles[p.var] then parts[#parts + 1] = "0 off, 1 on."
  end
  if #parts == 0 then parts[1] = p.label .. "." end
  return (table.concat(parts, " "):gsub("|", "\\|"))
end

local function api_call(e, ex)
  local set = {}
  for _, s in ipairs(ex.set) do set[#set + 1] = s.var .. " = " .. num(s.value) end
  local params = "{ " .. table.concat(set, ", ") .. " }"
  if e.text then
    local text = ex.notes:match('Item name: "([^"]+)"') or (e.category == "Title" and "Title | Subtitle" or "Label")
    return string.format('LS.add_title(track, pos, len, "%s", "%s", %s)', text, e.name, params)
  elseif e.where == "track" then
    return string.format('LS.add_to_track(track, "%s", %s)', e.name, params)
  end
  return string.format('LS.add_to_item(item, "%s", %s)', e.name, params)
end

-- AI reference ----------------------------------------------------------------------------------------

local function ai_section(e)
  local o = { "### " .. e.name, "", "*Placement:* " .. PLACEMENT[e.where or "both"] .. ".", "", e.about or "", "" }
  if e.text then o[#o + 1] = "*Text:* " .. e.text .. "." o[#o + 1] = "" end
  o[#o + 1] = "| API index | var | Control | Default | Range | Meaning |"
  o[#o + 1] = "|---|---|---|---|---|---|"
  for _, p in ipairs(e.params) do
    o[#o + 1] = string.format("| %d | `%s` | %s | %s | %s to %s | %s |", p.index - 1, p.var, p.label, num(p.def),
      num(p.min), num(p.max), meaning(e, p))
  end
  if #e.examples > 0 then
    o[#o + 1] = ""
    o[#o + 1] = "Examples:"
    o[#o + 1] = ""
    for _, ex in ipairs(e.examples) do
      o[#o + 1] = "- " .. ex.title .. ": `" .. api_call(e, ex) .. "`" .. (ex.notes ~= "" and (" " .. ex.notes) or "")
    end
  end
  if #e.tips > 0 then
    o[#o + 1] = ""
    for _, t in ipairs(e.tips) do o[#o + 1] = "- " .. t end
  end
  o[#o + 1] = ""
  return table.concat(o, "\n")
end

local function ai_reference()
  local o = { fill(read(ROOT .. "docs/src/ai-intro.md")), "" }
  o[#o + 1] = "| Preset name | Placement | What it does |"
  o[#o + 1] = "|---|---|---|"
  for _, e in ipairs(EFFECTS) do
    o[#o + 1] = string.format("| `%s` | %s | %s |", e.name, PLACEMENT_SHORT[e.where or "both"], (e.about or ""):gsub("|", "\\|"))
  end
  o[#o + 1] = ""
  for _, e in ipairs(EFFECTS) do o[#o + 1] = ai_section(e) end
  return table.concat(o, "\n")
end

-- Manual ------------------------------------------------------------------------------------------

local function slug(e) return (e.file:gsub("%.eel$", "")) end

local function manual_rows(e)
  local rows, seen = {}, {}
  for _, p in ipairs(e.params) do
    if not seen[p.var] then
      local kind, g = group_of(e, p.var)
      if kind == "color" or kind == "wheel" or kind == "curve" or kind == "huecurve" then
        for _, v in ipairs(g.vars) do seen[v] = true end
        local desc = e.help[g.vars[1]] or ""
        local first = e.byvar[g.vars[1]]
        local range = string.format("%s to %s each", num(first.min), num(first.max))
        if kind == "color" then desc, range = "Color picker.", "" end
        rows[#rows + 1] = string.format("| %s | %s | %s |", g.label, desc, range)
      else
        seen[p.var] = true
        local range = e.enums[p.var] and table.concat(e.enums[p.var], ", ")
                   or e.toggles[p.var] and ("off/on (" .. (p.def > 0.5 and "on" or "off") .. ")")
                   or string.format("%s to %s (%s)", num(p.min), num(p.max), num(p.def))
        rows[#rows + 1] = string.format("| %s | %s | %s |", p.label, (e.help[p.var] or ""):gsub("|", "\\|"), range)
      end
    end
  end
  return rows
end

local function manual_section(e)
  local o = { "### " .. e.title, "" }
  local img = io.open(ROOT .. "docs/images/" .. slug(e) .. ".jpg", "rb")
  if img then
    img:close()
    o[#o + 1] = "![" .. e.title .. "](images/" .. slug(e) .. ".jpg)"
    o[#o + 1] = ""
  end
  o[#o + 1] = (e.about or "") .. " **Goes on:** " .. PLACEMENT_SHORT[e.where or "both"]:lower() .. ". Preset name: `" .. e.name .. "`."
  o[#o + 1] = ""
  o[#o + 1] = "| Control | What it does | Range (default) |"
  o[#o + 1] = "|---|---|---|"
  for _, r in ipairs(manual_rows(e)) do o[#o + 1] = r end
  if #e.examples > 0 then
    o[#o + 1] = ""
    o[#o + 1] = "**Try this:**"
    o[#o + 1] = ""
    for _, ex in ipairs(e.examples) do
      local s = {}
      for _, kv in ipairs(ex.set) do
        local p = e.byvar[kv.var]
        local v = e.enums[kv.var] and e.enums[kv.var][math.floor(kv.value) + 1] or num(kv.value)
        s[#s + 1] = p.label .. " " .. v
      end
      o[#o + 1] = "- *" .. ex.title .. "* - " .. table.concat(s, ", ") .. "." .. (ex.notes ~= "" and (" " .. ex.notes) or "")
    end
  end
  if #e.tips > 0 then
    o[#o + 1] = ""
    for _, t in ipairs(e.tips) do o[#o + 1] = "- " .. t end
  end
  o[#o + 1] = ""
  return table.concat(o, "\n")
end

local function manual()
  local o = { fill(read(ROOT .. "docs/src/manual-intro.md")), "" }
  local cat
  for _, e in ipairs(EFFECTS) do
    if e.category ~= cat then cat = e.category o[#o + 1] = "## " .. cat .. "\n" end
    o[#o + 1] = manual_section(e)
  end
  return table.concat(o, "\n")
end

-- JSON --------------------------------------------------------------------------------------------

local function jstr(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" }
    return map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function jval(v, ind)
  ind = ind or ""
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local parts = {}
      for _, x in ipairs(v) do parts[#parts + 1] = ind .. "  " .. jval(x, ind .. "  ") end
      return #parts == 0 and "[]" or ("[\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "]")
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = ind .. "  " .. jstr(k) .. ": " .. jval(v[k], ind .. "  ") end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. ind .. "}"
  elseif t == "number" then return num(v)
  elseif t == "boolean" then return tostring(v)
  end
  return jstr(v)
end

local function json()
  local list = {}
  for _, e in ipairs(EFFECTS) do
    local controls = {}
    for _, p in ipairs(e.params) do
      controls[#controls + 1] = { index = p.index - 1, var = p.var, label = p.label, default = p.def, min = p.min,
        max = p.max, help = meaning(e, p), options = e.enums[p.var], toggle = e.toggles[p.var] or false }
    end
    local examples = {}
    for _, ex in ipairs(e.examples) do
      local set = {}
      for _, s in ipairs(ex.set) do set[s.var] = s.value end
      examples[#examples + 1] = { title = ex.title, set = set, notes = ex.notes }
    end
    list[#list + 1] = { name = e.name, title = e.title, category = e.category, placement = e.where or "both",
      about = e.about or "", text = e.text or false, file = e.file, controls = controls, examples = examples, tips = e.tips }
  end
  return jval({ version = VERSION, effects = list }) .. "\n"
end

-- Claude skill -------------------------------------------------------------------------------------

local function skill()
  return fill(read(ROOT .. "docs/src/skill.md"))
end

local ai = ai_reference()
write(ROOT .. "docs/effects.json", json())
write(ROOT .. "docs/AI-REFERENCE.md", ai)
write(ROOT .. "docs/MANUAL.md", manual())
os.execute('mkdir -p "' .. ROOT .. 'ai/claude-skill/larry-seyer-video-effects"')
write(ROOT .. "ai/claude-skill/larry-seyer-video-effects/SKILL.md", skill())
write(ROOT .. "ai/claude-skill/larry-seyer-video-effects/reference.md", ai)
print(string.format("docs built: %d effects, version %s", #EFFECTS, VERSION))
