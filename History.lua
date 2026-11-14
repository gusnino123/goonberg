-- Goonberg Terminal: price history, statistics and the Goonberg Index level
local _, FI = ...
local H = {}
FI.History = H

-- Each item keeps a flat history array, 4 numbers per scan:
--   time, market price (copper, 0 = nothing listed), quantity listed, est. sold since previous scan
H.STRIDE = 4
local STRIDE = H.STRIDE
local DAY = 86400
H.DAY = DAY

-- Market price: average unit price of the cheapest 15% of units listed (at least 1).
-- Steadier than the single lowest listing, which one troll posting can swing.
-- `pairs` is a sorted flat array: unitPrice, count, unitPrice, count...
function H.MarketPrice(pairsArr, totalQty)
  local want = math.max(1, math.ceil(totalQty * 0.15))
  local got, sum = 0, 0
  for i = 1, #pairsArr, 2 do
    local take = math.min(pairsArr[i + 1], want - got)
    sum = sum + pairsArr[i] * take
    got = got + take
    if got >= want then break end
  end
  if got == 0 then return 0 end
  return math.floor(sum / got + 0.5)
end

-- Groups listings into price levels, cheapest first, up to `max` levels: flat price, qty, ...
function H.Depth(pairsArr, max)
  local out = {}
  for i = 1, #pairsArr, 2 do
    local p, q = pairsArr[i], pairsArr[i + 1]
    local n = #out
    if n >= 2 and out[n - 1] == p then
      out[n] = out[n] + q
    elseif n / 2 < max then
      out[n + 1] = p
      out[n + 2] = q
    else
      break
    end
  end
  return out
end

-- Thins old history so saved data stays small:
-- every scan for 2 days, one point per 6 hours up to 14 days, one per day up to 90 days.
-- Merged points keep the latest price and quantity and add up est. sold.
function H.Compact(h, now, stride, sumField)
  stride = stride or STRIDE
  local out = {}
  local lastBucket, lastIdx
  for i = 1, #h, stride do
    local t = h[i]
    local age = now - t
    if age <= 90 * DAY then
      local bucket
      if age > 14 * DAY then bucket = "d" .. math.floor(t / DAY)
      elseif age > 2 * DAY then bucket = "q" .. math.floor(t / 21600) end
      if bucket and bucket == lastBucket then
        local prevSum = sumField and out[lastIdx + sumField - 1] or 0
        for k = 0, stride - 1 do
          local v = h[i + k]
          if k == 1 and stride == STRIDE and v == 0 then v = out[lastIdx + 1] end
          out[lastIdx + k] = v
        end
        if sumField then out[lastIdx + sumField - 1] = prevSum + h[i + sumField - 1] end
      else
        lastIdx = #out + 1
        for k = 0, stride - 1 do out[lastIdx + k] = h[i + k] end
        lastBucket = bucket
      end
    end
  end
  return out
end

-- Adds one scan's result for an item. qty 0 means it wasn't listed this scan.
function H.Record(realm, itemID, now, mkt, minPrice, qty, listings, depth)
  local it = realm.items[itemID]
  if not it then
    it = { h = {} }
    realm.items[itemID] = it
  end
  local h = it.h
  local n = #h
  local sold = 0
  if n >= STRIDE then
    local prevT, prevQ = h[n - STRIDE + 1], h[n - STRIDE + 3]
    -- Units that vanished since the last scan were bought (or cancelled/expired).
    -- Only trusted when scans are close together.
    if now - prevT <= 12 * 3600 and prevQ > qty then sold = prevQ - qty end
  end
  h[n + 1] = now
  h[n + 2] = mkt
  h[n + 3] = qty
  h[n + 4] = sold

  if qty > 0 then
    it.mkt = mkt
    it.min = minPrice
    it.seen = now
  else
    it.min = nil
  end
  it.qty = qty
  it.cnt = listings
  it.d = depth
  it.dt = depth and now or nil -- depth is only trusted from the scan that made it

  it.adds = (it.adds or 0) + 1
  if it.adds >= 24 then
    it.h = H.Compact(h, now, STRIDE, 4)
    it.adds = 0
  end
  return it
end

-- Price at or before time `t` (the last point with something listed)
local function priceAt(h, t)
  local p
  for i = 1, #h, STRIDE do
    if h[i] > t then break end
    if h[i + 1] > 0 then p = h[i + 1] end
  end
  return p
end

-- Market price of an item as it was at time t (nil if no data that old). With
-- maxAge, the point must be no older than t - maxAge (no stale stand-ins).
function H.PriceAt(it, t, maxAge)
  if not it then return nil end
  local h = it.h or {}
  if not maxAge then return priceAt(h, t) end
  local p
  for i = 1, #h, STRIDE do
    if h[i] > t then break end
    if h[i + 1] > 0 and h[i] >= t - maxAge then p = h[i + 1] end
  end
  return p
end

-- Price from roughly `ago` seconds before `ref`: the last point at or before
-- ref - ago, but no older than ref - 2*ago. Too old a point would turn a "1h change"
-- into a "3 days change", so then there's no answer (nil) rather than a wrong one.
local function priceAgo(h, ref, ago)
  local t, oldest = ref - ago, ref - 2 * ago
  local p
  for i = 1, #h, STRIDE do
    if h[i] > t then break end
    if h[i + 1] > 0 and h[i] >= oldest then p = h[i + 1] end
  end
  return p
end

local function change(from, to)
  if not from or not to or from <= 0 or to <= 0 then return nil end
  return (to - from) / from * 100
end

H.WINDOWS = { c15 = 900, c1 = 3600, c6 = 6 * 3600, c12 = 12 * 3600, c24 = DAY, c7 = 7 * DAY }

-- Everything the tooltip, overview and chart header need for one item
function H.Stats(it, now)
  now = now or time()
  local h = it.h or {}
  local s = { price = it.mkt, min = it.min, qty = it.qty or 0, listings = it.cnt or 0, seen = it.seen }
  -- Changes are measured back from the item's latest price (not from "now"), so an
  -- item last seen yesterday shows how it moved up to then, not a mix of old and new.
  local ref = it.seen or it.imported or now
  for key, w in pairs(H.WINDOWS) do s[key] = change(priceAgo(h, ref, w), it.mkt) end
  s.age = now - ref
  s.stale = s.age > 6 * 3600 -- the "current" price is more than 6 hours old

  -- Est. sold: units that left the AH between two scans no more than 12 hours
  -- apart. "Per day" divides by the time actually watched that way, so days with
  -- no scans (or imported daily prices, which carry no sales) don't dilute it.
  local sold15, sold1, sold6, sold12, sold24, sold7 = 0, 0, 0, 0, 0, 0
  local watched = 0
  for i = 1, #h, STRIDE do
    local age, sold = now - h[i], h[i + 3]
    if age <= 900 then sold15 = sold15 + sold end
    if age <= 3600 then sold1 = sold1 + sold end
    if age <= 6 * 3600 then sold6 = sold6 + sold end
    if age <= 12 * 3600 then sold12 = sold12 + sold end
    if age <= DAY then sold24 = sold24 + sold end
    if age <= 7 * DAY then
      sold7 = sold7 + sold
      if i > STRIDE then
        local gap = h[i] - h[i - STRIDE]
        if gap <= 12 * 3600 then watched = watched + gap end
      end
    end
  end
  s.sold15, s.sold1, s.sold6, s.sold12, s.sold24, s.sold7 = sold15, sold1, sold6, sold12, sold24, sold7
  s.watched = watched
  s.soldPerDay = watched >= 3 * 3600 and (sold7 / (watched / DAY)) or nil
  return s
end

-- Up to `n` values across the last `span` seconds (last price in each slot)
function H.Spark(it, now, span, n)
  local h = it.h or {}
  local out = {}
  local start = now - span
  local lastSlot = -1
  for i = 1, #h, STRIDE do
    local t, m = h[i], h[i + 1]
    if t >= start and m > 0 then
      local slot = math.min(n - 1, math.floor((t - start) / span * n))
      if slot == lastSlot then out[#out] = m else out[#out + 1] = m end
      lastSlot = slot
    end
  end
  return out
end

-- Candles for the chart: `n` slots across `span` seconds ending now.
-- Returns list of { slot, o, c, hi, lo, v } (empty slots are skipped).
function H.Candles(it, now, span, n)
  local h = it.h or {}
  local start = now - span
  local list, bySlot = {}, {}
  for i = 1, #h, STRIDE do
    local t, m, s = h[i], h[i + 1], h[i + 3]
    if t >= start then
      local slot = math.min(n - 1, math.max(0, math.floor((t - start) / span * n)))
      local c = bySlot[slot]
      if not c then
        c = { slot = slot, v = 0 }
        bySlot[slot] = c
        list[#list + 1] = c
      end
      c.v = c.v + s
      if m > 0 then
        if not c.o then c.o, c.hi, c.lo = m, m, m end
        c.c = m
        if m > c.hi then c.hi = m end
        if m < c.lo then c.lo = m end
      end
    end
  end
  -- A slot can have sales but no price (item sold out): borrow the previous close
  local prev = priceAt(h, start)
  for _, c in ipairs(list) do
    if not c.o then
      if prev then c.o, c.c, c.hi, c.lo = prev, prev, prev, prev end
    else
      -- open where the previous candle closed so candles connect like a stock chart
      if prev then
        c.o = prev
        if prev > c.hi then c.hi = prev end
        if prev < c.lo then c.lo = prev end
      end
    end
    prev = c.c or prev
  end
  local out = {}
  for _, c in ipairs(list) do if c.o then out[#out + 1] = c end end
  return out
end

-- The span of history an item has, for the "All" timeframe
function H.Span(it, now)
  local h = it.h or {}
  if not h[1] then return DAY end
  return math.max(DAY, now - h[1])
end

-- ---------------------------------------------------------------------------
-- The Goonberg Index: a chain-linked index of the realm's 25 most-traded items,
-- starting at 100. Each scan moves it by the weighted average price change of
-- those items since the previous scan (weights = gold traded over 7 days).
-- ---------------------------------------------------------------------------
H.INDEX_SIZE = 25

function H.UpdateIndex(realm, prevPrices, now)
  local idx = realm.index
  local last = idx[#idx] or 100
  local cands = {}
  for itemID, prev in pairs(prevPrices) do
    local it = realm.items[itemID]
    if it and it.seen == now and it.mkt and it.mkt > 0 and prev > 0 then
      local s = H.Stats(it, now)
      cands[#cands + 1] = { w = prev * (s.sold7 + 1), r = math.max(0.5, math.min(2, it.mkt / prev)) }
    end
  end
  table.sort(cands, function(a, b) return a.w > b.w end)
  local sw, sr = 0, 0
  for i = 1, math.min(H.INDEX_SIZE, #cands) do
    sw = sw + cands[i].w
    sr = sr + cands[i].w * cands[i].r
  end
  local level = last
  if sw > 0 then level = last * (sr / sw) end
  idx[#idx + 1] = now
  idx[#idx + 1] = level
  realm.indexAdds = (realm.indexAdds or 0) + 1
  if realm.indexAdds >= 24 then
    realm.index = H.Compact(idx, now, 2)
    realm.indexAdds = 0
  end
  return level
end

function H.IndexLevel(realm)
  local idx = realm.index
  return idx[#idx]
end

function H.IndexChange(realm, now, window)
  local idx = realm.index
  if #idx < 2 then return nil end
  local ref
  for i = 1, #idx, 2 do
    if idx[i] <= now - window then ref = idx[i + 1] else break end
  end
  ref = ref or idx[2]
  return change(ref, idx[#idx])
end

-- Rows for the overview, rebuilt once per scan (it walks every item)
function H.Overview(realm, now)
  if H.cache and H.cache.realm == realm and H.cache.scan == realm.lastScan then return H.cache end
  local rows = {}
  local listed = 0
  local gold = { sold15 = 0, sold1 = 0, sold6 = 0, sold12 = 0, sold24 = 0, sold7 = 0 }
  for itemID, it in pairs(realm.items) do
    local s = H.Stats(it, now)
    -- listed now, sold lately, or (imported) seen within the week
    local recent = (it.seen and now - it.seen < 7 * DAY) or (it.imported and now - it.imported < 7 * DAY)
    if (s.qty > 0 or s.sold7 > 0 or recent) and s.price then
      s.id = itemID
      s.cat = FI:Category(itemID)
      rows[#rows + 1] = s
      -- only items from a recent scan count as "on the AH now"
      if it.seen and (realm.lastScan or 0) - it.seen < 3 * 3600 then listed = listed + s.qty end
      for k in pairs(gold) do gold[k] = gold[k] + s.price * s[k] end
    end
  end
  H.cache = {
    realm = realm, scan = realm.lastScan, rows = rows,
    listed = listed, gold = gold, gold24 = gold.sold24, gold7 = gold.sold7,
  }
  return H.cache
end

-- Adds outside history to an item. `points` is a list of { t, mkt, qty }.
-- By default (Auctionator, daily data) a point is skipped when the item already has
-- data that day. With opts.fine (guild catch-up, intraday data) a point is skipped
-- only when one already exists within 10 minutes of it. Importing twice, or next to
-- your own scans, never double counts. Returns how many points were added.
function H.Merge(realm, itemID, points, opts)
  opts = opts or {}
  local it = realm.items[itemID]
  if not it then
    it = { h = {} }
    realm.items[itemID] = it
  end
  local h = it.h
  local days, times = {}, {}
  for i = 1, #h, STRIDE do
    days[math.floor(h[i] / DAY)] = true
    times[#times + 1] = h[i]
  end
  local function taken(t)
    if not opts.fine then return days[math.floor(t / DAY)] end
    for _, x in ipairs(times) do if math.abs(x - t) < 600 then return true end end
    return false
  end
  local merged = {}
  for i = 1, #h, STRIDE do merged[#merged + 1] = { h[i], h[i + 1], h[i + 2], h[i + 3] } end
  local added = 0
  for _, p in ipairs(points) do
    if p[2] and p[2] > 0 and not taken(p[1]) then
      days[math.floor(p[1] / DAY)] = true
      times[#times + 1] = p[1]
      merged[#merged + 1] = { p[1], p[2], p[3] or 0, 0 }
      added = added + 1
    end
  end
  if added == 0 then return 0 end
  table.sort(merged, function(a, b) return a[1] < b[1] end)
  if opts.fine then
    -- sales between close points can be estimated across the merged series
    for i = 2, #merged do
      local a, b = merged[i - 1], merged[i]
      if b[1] - a[1] <= 12 * 3600 and a[3] > b[3] then b[4] = a[3] - b[3] else b[4] = 0 end
    end
  end
  local out = {}
  for _, m in ipairs(merged) do
    out[#out + 1] = m[1]; out[#out + 1] = m[2]; out[#out + 1] = m[3]; out[#out + 1] = m[4]
  end
  it.h = out
  local last = merged[#merged]
  if opts.fine then
    -- guild data: the newest point becomes the current price (lowest-now is unknown)
    if not it.seen or last[1] > it.seen then
      it.mkt, it.qty, it.seen, it.min, it.shared = last[2], last[3], last[1], nil, true
    end
  elseif not it.seen or last[1] > it.seen then
    -- an item we've never scanned ourselves takes its latest imported price
    it.mkt = last[2]
    it.imported = last[1]
  end
  return added
end

-- A point from a guildmate's scan at time t. Skipped if we already have a point
-- within 10 minutes of it (our own scan, or another guildmate's of the same moment).
-- Returns true when it was added.
function H.RecordShared(realm, itemID, t, mkt, minPrice, qty, listings)
  local it = realm.items[itemID]
  if not it then
    it = { h = {} }
    realm.items[itemID] = it
  end
  local h = it.h
  local n = #h
  for i = n - STRIDE + 1, math.max(1, n - STRIDE * 8), -STRIDE do
    if h[i] and math.abs(h[i] - t) < 600 then return false end
  end
  if n > 0 and h[n - STRIDE + 1] > t then
    -- older than what we have: slot it in by day
    return H.Merge(realm, itemID, { { t, mkt, qty } }) > 0
  end
  local sold = 0
  if n >= STRIDE then
    local prevT, prevQ = h[n - STRIDE + 1], h[n - STRIDE + 3]
    if t - prevT <= 12 * 3600 and prevQ > qty then sold = prevQ - qty end
  end
  h[n + 1], h[n + 2], h[n + 3], h[n + 4] = t, mkt, qty, sold
  it.mkt, it.min, it.qty, it.cnt, it.seen = mkt, minPrice, qty, listings, t
  it.shared = true
  it.adds = (it.adds or 0) + 1
  if it.adds >= 24 then
    it.h = H.Compact(h, t, STRIDE, 4)
    it.adds = 0
  end
  return true
end

-- Fair value: the median market price over the last 7 days, leaving out the
-- latest scan (so today's cheap listings don't drag the yardstick down).
-- Needs at least 3 earlier points spanning 12 hours; nil otherwise.
function H.FairValue(it, now)
  local h = it.h
  if not h then return nil end
  local vals, first, last = {}, nil, nil
  for i = 1, #h, STRIDE do
    local t, m = h[i], h[i + 1]
    if m > 0 and now - t <= 7 * DAY and t ~= it.seen then
      vals[#vals + 1] = m
      first = first or t
      last = t
    end
  end
  if #vals < 3 or (last - first) < 12 * 3600 then return nil end
  table.sort(vals)
  local mid = math.floor((#vals + 1) / 2)
  if #vals % 2 == 1 then return vals[mid] end
  return (vals[mid] + vals[mid + 1]) / 2
end
