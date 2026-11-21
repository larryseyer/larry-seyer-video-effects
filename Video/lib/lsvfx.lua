-- Larry Seyer Video Effects shared library: reads effect files, parses their panel metadata, and installs them as
-- REAPER Video Processor presets (presets/builtin_video_processor.ini).
-- Plain Lua: works inside REAPER and from a standalone Lua interpreter.

local M = {}

M.HOME = "https://github.com/larryseyer/Reaper"   -- keep in step with tools/release.conf
M.MANUAL_URL = M.HOME .. "/blob/main/Video/docs/MANUAL.md"

M.CATEGORY_ORDER = { "Transform", "Color", "Look", "Transition", "Title", "Tutorial", "Compose", "Time" }
M.PRESET_PATTERN = "^LS [%a]+: "   -- names this installer owns

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function ensure_dir(path)
  local dir = path:match("^(.*)[/\\][^/\\]*$")
  if not dir then return end
  if reaper and reaper.RecursiveCreateDirectory then reaper.RecursiveCreateDirectory(dir, 0)
  else os.execute('mkdir -p "' .. dir .. '"') end
end

local function write_file(path, data)
  ensure_dir(path)   -- a fresh REAPER has no presets folder until something is saved there
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function split_lines(s)
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  if out[#out] == "" then out[#out] = nil end
  return out
end

-- Inline `// #include "lib/x.eel"` lines (relative to the effects folder), each file at most once.
function M.expand(effects_dir, path, seen)
  seen = seen or {}
  local src = read_file(path)
  if not src then error("cannot read " .. path) end
  local out = {}
  for _, line in ipairs(split_lines(src)) do
    local inc = line:match('^%s*//%s*#include%s+"([^"]+)"%s*$')
    if inc then
      local full = effects_dir .. "/" .. inc
      if not seen[full] then
        seen[full] = true
        for _, l in ipairs(M.expand(effects_dir, full, seen)) do out[#out + 1] = l end
      end
    else
      out[#out + 1] = line
    end
  end
  return out
end

-- Split a metadata argument string into words, keeping "quoted strings" together.
local function words(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '"' then
      local j = s:find('"', i + 1, true) or (#s + 1)
      out[#out + 1] = s:sub(i + 1, j - 1)
      i = j + 1
    elseif c:match("%s") then
      i = i + 1
    else
      local j = s:find("%s", i) or (#s + 1)
      out[#out + 1] = s:sub(i, j - 1)
      i = j
    end
  end
  return out
end

-- Parse one effect file into { file, name, category, title, about, where, text, params, meta, code }.
function M.read_effect(effects_dir, file)
  local code = M.expand(effects_dir, effects_dir .. "/" .. file)
  local e = { file = file, params = {}, byvar = {}, enums = {}, toggles = {}, colors = {}, wheels = {},
              curves = {}, huecurves = {}, rects = {}, points = {}, sections = {}, help = {}, examples = {},
              tips = {}, code = code }
  for _, line in ipairs(code) do
    local idx, var, rest = line:match("^%s*//@param%s*(%d+)%s*:%s*([%w_.]+)%s+(.*)$")
    if idx then
      local label, nums
      if rest:sub(1, 1) == "'" or rest:sub(1, 1) == '"' then
        local q = rest:sub(1, 1)
        local j = rest:find(q, 2, true)
        label, nums = rest:sub(2, j - 1), rest:sub(j + 1)
      else
        label, nums = rest:match("^(%S+)%s*(.*)$")
      end
      local n = {}
      for v in nums:gmatch("%S+") do n[#n + 1] = tonumber(v) end
      local p = { index = tonumber(idx), var = var, label = label, def = n[1] or 0, min = n[2] or 0,
                  max = n[3] or 1, step = n[5] or 0 }
      e.params[#e.params + 1] = p
      e.byvar[var] = p
    end
    local key, args = line:match("^%s*//@ls%s+(%S+)%s*(.*)$")
    if key then
      local w = words(args)
      if key == "category" then e.category = args
      elseif key == "title" then e.title = args
      elseif key == "about" then e.about = args
      elseif key == "where" then e.where = args
      elseif key == "text" then e.text = w[1] or args
      elseif key == "enum" then
        local opts = {}
        for o in args:sub(#w[1] + 2):gmatch("[^|]+") do opts[#opts + 1] = o end
        e.enums[w[1]] = opts
      elseif key == "toggle" then e.toggles[w[1]] = true
      elseif key == "color" then e.colors[#e.colors + 1] = { label = w[1], vars = { w[2], w[3], w[4] } }
      elseif key == "wheel" then e.wheels[#e.wheels + 1] = { label = w[1], vars = { w[2], w[3], w[4] }, master = w[5] }
      elseif key == "curve" or key == "huecurve" then
        local vars = {}
        for k = 2, #w do vars[#vars + 1] = w[k] end
        local list = key == "curve" and e.curves or e.huecurves
        list[#list + 1] = { label = w[1], vars = vars }
      elseif key == "rect" then e.rects[#e.rects + 1] = { label = w[1], vars = { w[2], w[3], w[4], w[5] } }
      elseif key == "point" then e.points[#e.points + 1] = { label = w[1], vars = { w[2], w[3] } }
      elseif key == "help" then e.help[w[1]] = args:match("^%S+%s+(.*)$") or ""
      elseif key == "tip" then e.tips[#e.tips + 1] = args
      elseif key == "example" then
        local title, assigns, notes = args:match("^(.-)%s*::%s*(.-)%s*::%s*(.*)$")
        if not title then title, assigns = args:match("^(.-)%s*::%s*(.*)$") end
        local set = {}
        for k, v in (assigns or ""):gmatch("([%w_.]+)=(%-?[%d.]+)") do set[#set + 1] = { var = k, value = tonumber(v) } end
        e.examples[#e.examples + 1] = { title = title or args, set = set, notes = notes or "" }
      elseif key == "section" then
        local vars = {}
        for k = 2, #w do vars[#vars + 1] = w[k] end
        e.sections[#e.sections + 1] = { label = w[1], vars = vars }
      end
    end
  end
  table.sort(e.params, function(a, b) return a.index < b.index end)
  e.name = "LS " .. (e.category or "Misc") .. ": " .. (e.title or file)
  return e
end

-- `list_files(dir)` returns file names in dir; supplied by the caller (REAPER or standalone).
function M.load_all(effects_dir, list_files)
  local order = {}
  for i, c in ipairs(M.CATEGORY_ORDER) do order[c] = i end
  local list = {}
  for _, f in ipairs(list_files(effects_dir)) do
    if f:match("%.eel$") then list[#list + 1] = M.read_effect(effects_dir, f) end
  end
  table.sort(list, function(a, b)
    local oa, ob = order[a.category] or 99, order[b.category] or 99
    if oa ~= ob then return oa < ob end
    return a.title < b.title
  end)
  return list
end

local function fmtnum(v)
  if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
  local s = string.format("%.10g", v)
  return s
end

-- Binary preset payload exactly as REAPER stores Video Processor presets.
function M.preset_payload(e)
  local parts = { "<CODE\0" }
  for _, line in ipairs(e.code) do parts[#parts + 1] = "|" .. line .. "\0" end
  parts[#parts + 1] = ">\0"
  local vals = {}
  for i = 1, 40 do vals[i] = 0 end
  for _, p in ipairs(e.params) do if p.index >= 1 and p.index <= 40 then vals[p.index] = p.def end end
  local nums = {}
  for i = 1, 40 do nums[i] = fmtnum(vals[i]) end
  parts[#parts + 1] = "CODEPARM " .. table.concat(nums, " ") .. "\0"
  return table.concat(parts)
end

-- Ini lines for one preset: Data/Data_1/... hex chunks of 16384 bytes, each followed by its checksum byte.
function M.preset_ini_lines(section, payload, name)
  local lines = { "[" .. section .. "]" }
  local CH = 16384
  local k = 0
  for pos = 1, #payload, CH do
    local chunk = payload:sub(pos, pos + CH - 1)
    local sum = 0
    for i = 1, #chunk do sum = (sum + chunk:byte(i)) % 256 end
    local hex = chunk:gsub(".", function(c) return string.format("%02X", c:byte()) end) .. string.format("%02X", sum)
    lines[#lines + 1] = (k == 0 and "Data=" or ("Data_" .. k .. "=")) .. hex
    k = k + 1
  end
  lines[#lines + 1] = "Len=" .. #payload
  lines[#lines + 1] = "Name=" .. name
  return lines
end

-- Parse the ini into { general = {lines}, presets = { {name=, lines={...}} } } keeping preset bodies verbatim.
local function parse_ini(text)
  local res = { general = {}, presets = {} }
  local cur
  for _, line in ipairs(split_lines(text or "")) do
    local sec = line:match("^%[(.-)%]%s*$")
    if sec then
      if sec == "General" then cur = "general"
      else
        cur = { lines = {} }
        res.presets[#res.presets + 1] = cur
      end
    elseif cur == "general" then
      if line ~= "" and not line:match("^NbPresets=") then res.general[#res.general + 1] = line end
    elseif cur and line ~= "" then
      cur.lines[#cur.lines + 1] = line
      local nm = line:match("^Name=(.*)$")
      if nm then cur.name = nm end
    end
  end
  return res
end

-- True when any effect is missing from the preset file or differs from the installed version.
function M.needs_install(ini_path, effects)
  local ini = parse_ini(read_file(ini_path))
  local installed = {}
  for _, p in ipairs(ini.presets) do
    if p.name and p.name:match(M.PRESET_PATTERN) then installed[p.name] = table.concat(p.lines, "\n") end
  end
  for _, e in ipairs(effects) do
    local want = table.concat(M.preset_ini_lines("x", M.preset_payload(e), e.name), "\n"):gsub("^%[x%]\n", "")
    if installed[e.name] ~= want then return true end
  end
  return false
end

-- Install or update all effects as presets. Existing presets named "LS <Category>: ..." are replaced;
-- everything else (other packs' presets, your own presets) is kept byte for byte. Returns count and backup path.
function M.install(ini_path, effects)
  local text = read_file(ini_path)
  local backup
  if text then
    backup = ini_path:gsub("%.ini$", "") .. ".before-LS-Video-FX.ini"
    if not read_file(backup) then write_file(backup, text) end
  end
  local ini = parse_ini(text)
  local keep = {}
  for _, p in ipairs(ini.presets) do
    if not (p.name and p.name:match(M.PRESET_PATTERN)) then keep[#keep + 1] = p end
  end
  local out = { "[General]" }
  for _, l in ipairs(ini.general) do out[#out + 1] = l end
  out[#out + 1] = "NbPresets=" .. (#keep + #effects)
  out[#out + 1] = ""
  local n = 0
  for _, p in ipairs(keep) do
    out[#out + 1] = "[Preset" .. n .. "]"
    for _, l in ipairs(p.lines) do out[#out + 1] = l end
    out[#out + 1] = ""
    n = n + 1
  end
  for _, e in ipairs(effects) do
    for _, l in ipairs(M.preset_ini_lines("Preset" .. n, M.preset_payload(e), e.name)) do out[#out + 1] = l end
    out[#out + 1] = ""
    n = n + 1
  end
  write_file(ini_path, table.concat(out, "\n"))
  return #effects, backup
end

return M
