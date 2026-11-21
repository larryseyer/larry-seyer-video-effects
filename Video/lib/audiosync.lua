-- Lines recordings up by their audio. For each item, a coarse pass cross-correlates onset envelopes (10 frames a
-- second) of the item and the reference track over their whole length with an FFT, which finds offsets of any
-- size; a fine pass then cross-correlates the whitened waveforms (2 kHz) in three short windows around that match,
-- accurate to about half a millisecond, and the three must agree (allowing for clock drift). Plain Lua apart from
-- the REAPER audio accessors.

local M = {}

local RATE = 2000          -- analysis sample rate
local HOP = 200            -- samples per envelope frame
local ENV_RATE = RATE / HOP
local BLOCK = 8000         -- samples per accessor read (a whole number of envelope frames)
local FINE_WIN = 3.6       -- seconds per fine window (with FINE_RANGE, fits a 8192-point transform)
local FINE_RANGE = 0.15    -- seconds searched each side of the coarse match
local WHITEN = 0.8         -- spectral whitening of the fine match (1 = full phase transform; a little less is
                           -- steadier where a frequency carries almost nothing)
local CANDIDATES = 5       -- coarse peaks checked by the fine pass (rhythmic music correlates at many offsets)
-- A match is trusted when its three fine windows agree and in each the whitened correlation peaks at least this
-- many standard deviations above the other lags searched.
local MIN_CONFIDENCE = 8
local AGREE = 0.002        -- seconds the middle window may sit off the line through the outer two
local DRIFT_NOTE = 0.010   -- drift over the item worth telling the user about (seconds)
local SILENT = 1e-4        -- peak level below which a recording counts as silent (-80 dB)

local READ = {}            -- yielded by the analysis coroutine to ask its driver for samples

local function progress(p)
  if coroutine.isyieldable() then coroutine.yield(p) end
end

-- Audio reading ------------------------------------------------------------------------------------------

-- Reads m stereo frames at RATE from accessor time t and returns them interleaved. GetAudioAccessorSamples
-- returns nothing and fills nothing when called inside a coroutine, so there the read is handed to the driver
-- (M.start's step), which runs it on the main thread.
local block_buf
local function fetch(acc, t, m)
  block_buf = block_buf or reaper.new_array(BLOCK*2)
  block_buf.clear()
  local rv = reaper.GetAudioAccessorSamples(acc, RATE, 2, t, m, block_buf)
  if rv == nil or rv < 0 then error("audio sync: could not read audio (GetAudioAccessorSamples returned "
    .. tostring(rv) .. ")") end
  return block_buf.table(1, m*2)
end

local function read_block(acc, t, m)
  if coroutine.isyieldable() then return coroutine.yield(READ, acc, t, m) end
  return fetch(acc, t, m)
end

-- Returns read(t, n, out): fills out[1..n] with mono samples at RATE starting at accessor time t (zeros where the
-- accessor has no audio).
local function reader(acc)
  return function(t, n, out)
    local pos = 0
    while pos < n do
      local m = math.min(BLOCK, n - pos)
      local tb = read_block(acc, t + pos/RATE, m)
      for i = 1, m do out[pos + i] = (tb[2*i - 1] + tb[2*i])*0.5 end
      pos = pos + m
    end
  end
end

-- Onset envelope (rise in log energy of the differentiated signal) from t0 for dur seconds, mean removed, and the
-- peak sample level.
local function onset_envelope(read, t0, dur, report)
  local frames = math.max(math.floor(dur*ENV_RATE), 1)
  local per = BLOCK // HOP
  local env, chunk = {}, {}
  local prev_x, prev_le, peak = 0, nil, 0
  local f = 0
  while f < frames do
    local nf = math.min(per, frames - f)
    read(t0 + f/ENV_RATE, nf*HOP, chunk)
    for k = 0, nf - 1 do
      local e = 1e-6
      for i = k*HOP + 1, (k + 1)*HOP do
        local x = chunk[i]
        if x > peak then peak = x elseif -x > peak then peak = -x end
        local d = x - prev_x
        prev_x = x
        e = e + d*d
      end
      local le = math.log(e)
      env[f + k + 1] = prev_le and math.max(le - prev_le, 0) or 0
      prev_le = le
    end
    f = f + nf
    report(f/frames)
  end
  local s = 0
  for i = 1, #env do s = s + env[i] end
  local mean = s/#env
  for i = 1, #env do env[i] = env[i] - mean end
  return env, peak
end

-- FFT and correlation ------------------------------------------------------------------------------------

-- cos and sin of 2*pi*k/n for k < n/2, kept per size.
local twiddle_cache = {}
local function twiddles(n)
  local t = twiddle_cache[n]
  if not t then
    local cs, sn = {}, {}
    for k = 0, n//2 - 1 do cs[k], sn[k] = math.cos(2*math.pi*k/n), math.sin(2*math.pi*k/n) end
    t = { cs, sn }
    twiddle_cache[n] = t
  end
  return t[1], t[2]
end

-- In-place radix-2 complex FFT of re/im (1-based tables of length n, a power of two). Unscaled.
local function fft(re, im, n, inverse)
  local j = 0
  for i = 0, n - 2 do
    if i < j then
      re[i + 1], re[j + 1] = re[j + 1], re[i + 1]
      im[i + 1], im[j + 1] = im[j + 1], im[i + 1]
    end
    local m = n >> 1
    while m >= 1 and (j & m) ~= 0 do j = j ~ m; m = m >> 1 end
    j = j | m
  end
  local cs, sn = twiddles(n)
  local sign = inverse and 1 or -1
  local len = 2
  while len <= n do
    local half, step = len >> 1, n // len
    for st = 0, n - 1, len do
      for k = 0, half - 1 do
        local a, b = st + k + 1, st + k + half + 1
        local cr, ci = cs[k*step], sign*sn[k*step]
        local xr = re[b]*cr - im[b]*ci
        local xi = re[b]*ci + im[b]*cr
        re[b] = re[a] - xr; im[b] = im[a] - xi
        re[a] = re[a] + xr; im[a] = im[a] + xi
      end
    end
    len = len << 1
  end
end

-- Cross-correlation c[k] = sum_j R[j + k]*A[j] by FFT; returns get(k), valid for -#A < k < #R, or with `ahead`
-- only for 0 <= k <= #R - #A (half the transform size, enough when A slides within R). With `whiten`
-- each frequency is divided by its magnitude to the power WHITEN (generalized cross-correlation with phase
-- transform): pitched sound then gives one sharp peak instead of one at every period of the pitch.
local function xcorr(R, A, whiten, ahead)
  local n = 1
  while n < (ahead and #R or #R + #A) do n = n*2 end
  local rr, ri, ar, ai = {}, {}, {}, {}
  for i = 1, n do rr[i] = R[i] or 0; ri[i] = 0; ar[i] = A[i] or 0; ai[i] = 0 end
  fft(rr, ri, n)
  progress(nil)
  fft(ar, ai, n)
  progress(nil)
  local eps = 0
  if whiten then
    for i = 1, n do
      local xr, xi, yr, yi = rr[i], ri[i], ar[i], ai[i]
      eps = math.max(eps, math.sqrt((xr*xr + xi*xi)*(yr*yr + yi*yi)))
    end
    eps = eps*1e-6
  end
  for i = 1, n do
    local xr, xi, yr, yi = rr[i], ri[i], ar[i], -ai[i]
    local cr, ci = xr*yr - xi*yi, xr*yi + xi*yr
    if whiten then
      local g = (math.sqrt(cr*cr + ci*ci) + eps)^-WHITEN
      cr, ci = cr*g, ci*g
    end
    rr[i], ri[i] = cr, ci
  end
  fft(rr, ri, n, true)
  progress(nil)
  return function(k) return rr[(k % n) + 1] end
end

-- Best lag in kmin..kmax and its height above the other lags in standard deviations. With `either_sign` a
-- strongly negative peak (polarity reversed) counts too.
local function best_lag(c, kmin, kmax, either_sign)
  local best, bk, s, s2, cnt = -math.huge, 0, 0, 0, 0
  for k = kmin, kmax do
    local v = c(k)
    if either_sign then v = math.abs(v) end
    if v > best then best, bk = v, k end
    s = s + v; s2 = s2 + v*v; cnt = cnt + 1
  end
  local mean = s/cnt
  local sd = math.sqrt(math.max(s2/cnt - mean*mean, 1e-30))
  return bk, (best - mean)/sd
end

-- The `count` highest local peaks of c over kmin..kmax, best first.
local function peaks(c, kmin, kmax, count)
  local found = {}
  local prev, cur = -math.huge, c(kmin)
  for k = kmin, kmax do
    local nxt = k < kmax and c(k + 1) or -math.huge
    if cur >= prev and cur > nxt then found[#found + 1] = { k = k, v = cur } end
    prev, cur = cur, nxt
  end
  table.sort(found, function(x, y) return x.v > y.v end)
  local out = {}
  for i = 1, math.min(count, #found) do out[i] = found[i].k end
  return out
end

-- Fine match: item time tau0..tau0+FINE_WIN against the reference around project time pos + tau0. Returns the
-- refined position, the normalized waveform correlation there (0..1) and how sharply the whitened correlation
-- peaks there (standard deviations above the other lags searched).
local function fine_window(read_ref, read_item, pos, tau0)
  local n = math.floor(FINE_WIN*RATE)
  local L = math.floor(FINE_RANGE*RATE)
  local a, r = {}, {}
  read_item(tau0, n, a)
  read_ref(pos + tau0 - FINE_RANGE, n + 2*L, r)
  local d, sharp = best_lag(xcorr(r, a, true, true), 0, 2*L, true)
  local s, ea, er = 0, 0, 0
  for j = 1, n do
    local x, y = a[j], r[j + d]
    s = s + x*y; ea = ea + x*x; er = er + y*y
  end
  return pos - FINE_RANGE + d/RATE, math.abs(s)/math.sqrt(math.max(ea*er, 1e-30)), sharp
end

-- Checks a coarse match (item placed at project time `coarse`) with fine windows at a quarter, half and three
-- quarters of the part that overlaps the reference. Returns { pos, score, confidence, drift }, or nil and why not.
local function verify(read_ref, read_item, coarse, len, r0, r1)
  local o0 = math.max(0, r0 - coarse) + FINE_RANGE
  local o1 = math.min(len, r1 - coarse) - FINE_RANGE - FINE_WIN
  if o1 <= o0 then return nil, "overlap" end
  local w = {}
  for i, frac in ipairs({ 0.25, 0.5, 0.75 }) do
    local tau = o0 + (o1 - o0)*frac
    local p, score, sharp = fine_window(read_ref, read_item, coarse, tau)
    w[i] = { tau = tau, pos = p, score = score, sharp = sharp }
  end
  local drift = (w[3].pos - w[1].pos)/(w[3].tau - w[1].tau)
  local off_line = math.abs(w[2].pos - (w[1].pos + drift*(w[2].tau - w[1].tau)))
  local sharp = math.min(w[1].sharp, w[2].sharp, w[3].sharp)
  if off_line > AGREE or sharp < MIN_CONFIDENCE then return nil, "match" end
  return { pos = w[2].pos, score = math.min(w[1].score, w[2].score, w[3].score), confidence = sharp,
    drift = drift }
end

-- Analysis ------------------------------------------------------------------------------------------------

local function take_name(item)
  local take = reaper.GetActiveTake(item)
  local _, nm = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  return nm
end

-- Finds where `item` belongs against the reference `ref` ({ read, env, t0, t1 }) and fills `res`.
local function match_item(res, item, ref, report)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then
    res.note = "no audio"
    return
  end
  local acc = reaper.CreateTakeAudioAccessor(take)
  local len = reaper.GetAudioAccessorEndTime(acc) - reaper.GetAudioAccessorStartTime(acc)
  local read = reader(acc)
  local A, peak = onset_envelope(read, 0, len, function(p) report(p*0.4) end)
  local best, why = nil, "overlap"
  if peak < SILENT then
    why = "silent"
  else
    local cands = peaks(xcorr(ref.env, A), -(#A - 1), #ref.env - 1, CANDIDATES)
    for i, k in ipairs(cands) do
      local v, reason = verify(ref.read, read, ref.t0 + k/ENV_RATE, len, ref.t0, ref.t1)
      if v and (not best or v.confidence > best.confidence) then best = v end
      if reason == "match" then why = "match" end
      report(0.4 + 0.6*i/#cands)
    end
    if #cands == 0 then why = "match" end
  end
  reaper.DestroyAudioAccessor(acc)
  if not best then
    res.note = ({ silent = "its audio is silent", overlap = "overlaps the reference too little",
      match = "no clear match in the audio" })[why]
    return
  end
  res.pos, res.score, res.confidence = best.pos, best.score, best.confidence
  res.shift = res.pos - reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local over = best.drift*len
  if math.abs(over) > DRIFT_NOTE then
    res.note = string.format("its clock runs %.0f ms %s over its length; lined up at its middle",
      math.abs(over)*1000, over > 0 and "slow" or "fast")
  end
end

-- Works out where each item belongs against the audio of `ref_track`. `items` is a list of { item, label }.
-- Returns one result per item: { item, label, pos (new position, or nil when no confident match), shift,
-- confidence, score, note }. Blocks until done; M.start runs the same work a slice at a time.
function M.analyze(ref_track, items)
  local acc = reaper.CreateTrackAudioAccessor(ref_track)
  local ref = { read = reader(acc), t0 = reaper.GetAudioAccessorStartTime(acc),
    t1 = reaper.GetAudioAccessorEndTime(acc) }
  local total = #items + 1
  local function stage(k) return function(p) progress(((k - 1) + (p or 0))/total) end end
  local peak
  ref.env, peak = onset_envelope(ref.read, ref.t0, ref.t1 - ref.t0, stage(1))
  local results = {}
  for idx, it in ipairs(items) do
    local res = { item = it.item, label = it.label or take_name(it.item) }
    results[#results + 1] = res
    if peak < SILENT then
      res.note = "the reference track has no sound"
    else
      match_item(res, it.item, ref, stage(idx + 1))
    end
  end
  reaper.DestroyAudioAccessor(acc)
  return results
end

-- Starts M.analyze as a job for a script that must stay responsive. Call job:step(seconds) once per defer cycle:
-- it works for about that long and returns true when finished. job.progress (0..1), job.results once done.
function M.start(ref_track, items)
  local job = { progress = 0, done = false }
  local co = coroutine.create(function() return M.analyze(ref_track, items) end)
  function job:step(budget)
    if self.done then return true end
    local deadline = reaper.time_precise() + budget
    local send
    repeat
      local ok, a, acc, t, m = coroutine.resume(co, send)
      send = nil
      if not ok then self.done = true; error(debug.traceback(co, a), 0) end
      if coroutine.status(co) == "dead" then
        self.results, self.progress, self.done = a, 1, true
        return true
      end
      if a == READ then
        send = fetch(acc, t, m)
      elseif a then
        self.progress = a
      end
    until send == nil and reaper.time_precise() >= deadline
    return false
  end
  return job
end

-- Moves the items to the positions found. An item that belongs before the project start is trimmed at its start
-- instead, so it stays in sync. Call inside an undo block.
function M.apply(results)
  for _, res in ipairs(results) do
    if res.pos then
      local item = res.item
      if res.pos >= 0 then
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", res.pos)
      else
        local cut = -res.pos
        local take = reaper.GetActiveTake(item)
        local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS",
          reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + cut*rate)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len - cut)
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", 0)
        res.note = string.format("trimmed %.3f s at its start (it began before the project start)", cut)
      end
    end
  end
  reaper.UpdateArrange()
end

return M
