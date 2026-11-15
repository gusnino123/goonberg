-- Goonberg Terminal: price history, statistics and the Goonberg Index level
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.History
local H = {}
FI.History = H

---One item's price data on one realm (GT.Realm.items[itemID]). Prices in copper.
---@class GT.Item
---@field h number[]       history, STRIDE numbers per scan: time, market price (0 = none listed), quantity listed, est. sold
---@field mkt integer?     market price the last time it was listed
---@field min integer?     lowest unit price in the latest scan (nil when not listed)
---@field qty integer?     units listed in the latest scan
---@field cnt integer?     auctions in the latest scan
---@field d number[]?      market depth: flat price, quantity pairs, cheapest first
---@field dt integer?      when `d` was taken; only trusted when it equals `seen`
---@field seen integer?    last time it was listed
---@field adds integer?    points added since the history was last compacted
---@field n string?        cached name
---@field imported integer? newest point from Auctionator, seed or Blizzard data
---@field shared boolean?  the latest price came from a guildmate's scan

---@class GT.LongTerm
---@field historical number  60-day median of daily prices ("usual price")
---@field typicalLow number  10th-percentile daily low ("cheapest typical")
---@field days integer       separate days it was seen
---@field market number?     14-day market value

-- Each item keeps a flat history array, 4 numbers per scan:
--   time, market price (copper, 0 = nothing listed), quantity listed, est. sold since previous scan
H.STRIDE = 4
local STRIDE = H.STRIDE
local DAY = 86400
H.DAY = DAY

-- Market price: average unit price of the cheapest 15% of units listed (at least 1).
-- Steadier than the single lowest listing, which one troll posting can swing.
-- `pairs` is a sorted flat array: unitPrice, count, unitPrice, count...
---@param pairsArr number[]  unit price, count pairs, cheapest first
---@param totalQty integer
---@return integer copper
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
---@param realm GT.Realm
---@param itemID integer
---@param now integer
---@param mkt integer
---@param minPrice integer?
---@param qty integer
---@param listings integer
---@param depth number[]?
---@return GT.Item
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
    it.src = nil
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
-- Index of the last point at or before t (history is in time order): a binary
-- search, so looking up old prices stays fast however long the history gets.
local function lastAtOrBefore(h, t)
  local n = #h / STRIDE
  if n < 1 or h[1] > t then return nil end
  local lo, hi = 1, n
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if h[(mid - 1) * STRIDE + 1] <= t then lo = mid else hi = mid - 1 end
  end
  return (lo - 1) * STRIDE + 1
end

-- the last price (> 0) at or before t, and not older than `oldest` if given
local function priceAt(h, t, oldest)
  local i = lastAtOrBefore(h, t)
  while i and i >= 1 do
    if oldest and h[i] < oldest then return nil end
    if h[i + 1] > 0 then return h[i + 1] end
    i = i - STRIDE
  end
  return nil
end

-- Market price of an item as it was at time t (nil if no data that old). With
-- maxAge, the point must be no older than t - maxAge (no stale stand-ins).
---@param it GT.Item
---@param t integer
---@param maxAge integer?
---@return integer?
function H.PriceAt(it, t, maxAge)
  if not it then return nil end
  return priceAt(it.h or {}, t, maxAge and (t - maxAge) or nil)
end

local function change(from, to)
  if not from or not to or from <= 0 or to <= 0 then return nil end
  return (to - from) / from * 100
end

H.WINDOWS = { c15 = 900, c1 = 3600, c6 = 6 * 3600, c12 = 12 * 3600, c24 = DAY, c7 = 7 * DAY }
-- the same windows, shortest first, for the single pass in Stats
local WIN_LIST = {}
for key, w in pairs(H.WINDOWS) do WIN_LIST[#WIN_LIST + 1] = { key, w } end
table.sort(WIN_LIST, function(a, b) return a[2] < b[2] end)
local LONGEST = WIN_LIST[#WIN_LIST][2]

-- Everything the tooltip, overview and chart header need for one item.
-- One backward pass over the last 14 days of history (older points are never
-- touched), which matters with thousands of items.
---@param it GT.Item
---@param now integer?
---@return table stats  price, min, qty, listings, seen, change per window (c15, c1, ...), sold per window, soldPerDay
function H.Stats(it, now)
  now = now or time()
  local h = it.h or {}
  local s = { price = it.mkt, min = it.min, qty = it.qty or 0, listings = it.cnt or 0, seen = it.seen }
  -- Changes are measured back from the item's latest price (not from "now"), so an
  -- item last seen yesterday shows how it moved up to then. The reference price for
  -- a window of length w is the last point at or before ref - w but no older than
  -- ref - 2w; too old a point would turn a "1h change" into a "3 days change".
  local ref = it.seen or it.imported or now
  s.age = now - ref
  s.stale = s.age > 6 * 3600

  -- Est. sold: units that left the AH between two scans no more than 12 hours
  -- apart. "Per day" divides by the time actually watched that way.
  local sold15, sold1, sold6, sold12, sold24, sold7, watched = 0, 0, 0, 0, 0, 0, 0
  local found, nextW, nWin = {}, 1, #WIN_LIST
  local stopT = math.min(ref - 2 * LONGEST, now - 7 * DAY)
  local n = #h
  local i = n - STRIDE + 1
  while i >= 1 do
    local t = h[i]
    if t < stopT then break end
    local m, sold = h[i + 1], h[i + 3]
    local age = now - t
    if age <= 7 * DAY then
      sold7 = sold7 + sold
      if age <= DAY then sold24 = sold24 + sold end
      if age <= 12 * 3600 then sold12 = sold12 + sold end
      if age <= 6 * 3600 then sold6 = sold6 + sold end
      if age <= 3600 then sold1 = sold1 + sold end
      if age <= 900 then sold15 = sold15 + sold end
      if i > STRIDE then
        local gap = t - h[i - STRIDE]
        if gap <= 12 * 3600 then watched = watched + gap end
      end
    end
    -- windows are sorted shortest first, so only the next unresolved one can match
    while nextW <= nWin and m > 0 and t <= ref - WIN_LIST[nextW][2] do
      local w = WIN_LIST[nextW][2]
      found[WIN_LIST[nextW][1]] = (t >= ref - 2 * w) and m or false
      nextW = nextW + 1
    end
    if nextW > nWin and age > 7 * DAY then break end
    i = i - STRIDE
  end
  for k = 1, #WIN_LIST do
    local key = WIN_LIST[k][1]
    s[key] = found[key] and change(found[key], it.mkt) or nil
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
    if t > now then break end -- the window can end in the past (chart panned back)
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
-- The Goonberg Index: a chain-linked index of the realm's busiest trade goods,
-- starting at 100. Each scan moves it by the weighted average price change of
-- those items since the previous scan (weights = gold traded over 7 days).
-- Only deep, liquid markets count (no gear, 20+ listed in both scans, 20+ sold
-- in a week), and each item's move is capped at -20%/+25% per scan, so a few
-- one-off listings can't drag the whole index around.
-- ---------------------------------------------------------------------------
H.INDEX_SIZE = 25
H.INDEX_VERSION = 2
local INDEX_MIN_QTY, INDEX_MIN_SOLD = 20, 20

function H.UpdateIndex(realm, prevPrices, now)
  local idx = realm.index
  local last = idx[#idx] or 100
  local cands = {}
  for itemID, prev in pairs(prevPrices) do
    local it = realm.items[itemID]
    if it and it.seen == now and it.mkt and it.mkt > 0 and prev > 0 and (it.qty or 0) >= INDEX_MIN_QTY then
      local _, _, _, _, _, classID = FI.GetItemInfoInstant(itemID)
      local h = it.h
      local prevQty = h and #h >= 2 * STRIDE and h[#h - 2 * STRIDE + 3] or 0
      if classID ~= 2 and classID ~= 4 and prevQty >= INDEX_MIN_QTY then
        local s = H.Stats(it, now)
        if s.sold7 >= INDEX_MIN_SOLD then
          cands[#cands + 1] = { w = prev * s.sold7, r = math.max(0.8, math.min(1.25, it.mkt / prev)) }
        end
      end
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

-- The index method changed: start every realm's index again from 100
FI:On("ADDON_LOADED", function(_, name)
  if not FI.db or FI.db.indexVersion == H.INDEX_VERSION then return end
  for _, r in pairs(FI.db.realms or {}) do r.index, r.indexAdds = {}, 0 end
  FI.db.indexVersion = H.INDEX_VERSION
end)

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
local function newBuild(realm, now)
  return { realm = realm, scan = realm.lastScan, now = now, rows = {}, listed = 0,
    gold = { sold15 = 0, sold1 = 0, sold6 = 0, sold12 = 0, sold24 = 0, sold7 = 0 } }
end

local function addItem(b, itemID, it)
  local now, realm = b.now, b.realm
  local s = H.Stats(it, now)
  -- listed now, sold lately, or (imported) seen within the week
  local recent = (it.seen and now - it.seen < 7 * DAY) or (it.imported and now - it.imported < 7 * DAY)
  if (s.qty > 0 or s.sold7 > 0 or recent) and s.price then
    s.id = itemID
    s.cat = FI:Category(itemID)
    b.rows[#b.rows + 1] = s
    -- "on the AH now": listed in a recent scan. Items that aren't have no
    -- current price to compare, so their changes are blank ("-"), not stale moves.
    s.onAH = s.qty > 0 and it.seen ~= nil and (realm.lastScan or 0) - it.seen < 3 * 3600
    if s.onAH then
      b.listed = b.listed + s.qty
    else
      for key in pairs(H.WINDOWS) do s[key] = nil end
    end
    s.thin = s.qty < 3 -- one or two listings: a price "move" may just be one seller
    local gold = b.gold
    for k in pairs(gold) do gold[k] = gold[k] + s.price * s[k] end
  end
end

local function finishBuild(b)
  H.cache = {
    realm = b.realm, scan = b.scan, rows = b.rows,
    listed = b.listed, gold = b.gold, gold24 = b.gold.sold24, gold7 = b.gold.sold7,
  }
  return H.cache
end

function H.Overview(realm, now)
  if H.cache and H.cache.realm == realm and H.cache.scan == realm.lastScan then return H.cache end
  local b = newBuild(realm, now)
  for itemID, it in pairs(realm.items) do addItem(b, itemID, it) end
  return finishBuild(b)
end

-- Same as Overview, but spread over several frames (~8 ms each) so opening the
-- window or finishing a scan never freezes the game. Returns the current rows if
-- they're up to date; otherwise returns the previous rows (or nil the first time)
-- and fires FI_OVERVIEW_READY when the new ones are done.
local builder = CreateFrame("Frame")
builder:Hide()
local BUILD_MS = 8
builder:SetScript("OnUpdate", function(self)
  local b = H.building
  if not b or b.realm ~= FI:Realm() then H.building = nil; self:Hide(); return end
  local start = debugprofilestop()
  local items = b.realm.items
  local n = 0
  while true do
    b.i = b.i + 1
    local id = b.ids[b.i]
    if id == nil then
      H.building = nil
      self:Hide()
      finishBuild(b)
      FI:Fire("FI_OVERVIEW_READY")
      return
    end
    local it = items[id]
    if it then addItem(b, id, it) end
    n = n + 1
    if n % 25 == 0 and debugprofilestop() - start > BUILD_MS then return end
  end
end)

function H.OverviewAsync(realm, now)
  local c = H.cache
  if c and c.realm == realm and c.scan == realm.lastScan then return c, false end
  local b = H.building
  -- small realms: just build it now, it takes no time
  local count = 0
  for _ in pairs(realm.items) do count = count + 1; if count > 1500 then break end end
  if count <= 1500 then H.building = nil; return H.Overview(realm, now), false end
  if not (b and b.realm == realm and b.scan == realm.lastScan) then
    -- snapshot the item IDs: scans and syncs may add items while we work
    b = newBuild(realm, now)
    b.ids, b.i = {}, 0
    for id in pairs(realm.items) do b.ids[#b.ids + 1] = id end
    H.building = b
    builder:Show()
  end
  return (c and c.realm == realm) and c or nil, true
end

-- Adds outside history to an item. `points` is a list of { t, mkt, qty }.
-- By default (Auctionator, daily data) a point is skipped when the item already has
-- data that day. With opts.fine (guild catch-up, intraday data) a point is skipped
-- only when one already exists within 10 minutes of it. Importing twice, or next to
-- your own scans, never double counts. Returns how many points were added.
local OWN_PRICE_WINS = 2 * DAY -- a scan of yours (or a guildmate's) this recent is the price
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
  -- quick check before any copying: is there anything new at all?
  if not opts.fine then
    local any = false
    for _, p in ipairs(points) do
      if p[2] and p[2] > 0 and not days[math.floor(p[1] / DAY)] then any = true; break end
    end
    if not any then return 0 end
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
      it.mkt, it.qty, it.seen, it.min, it.shared, it.src = last[2], last[3], last[1], nil, true, nil
    end
  elseif last[1] > (it.seen or 0) and not (it.seen and time() - it.seen < OWN_PRICE_WINS) then
    -- Daily data from elsewhere (Auctionator, older guild history) only becomes the
    -- current price when you have no recent price of your own: Auctionator keeps the
    -- lowest single listing it saw that day, which can be one cheap auction that was
    -- bought right away, so it must never replace a real scan's market price.
    it.mkt = last[2]
    it.imported = math.min(last[1], time()) -- (points sit at midday: never "newer than now")
    it.src = opts.source or "import"
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
  it.src = nil
  it.adds = (it.adds or 0) + 1
  if it.adds >= 24 then
    it.h = H.Compact(h, t, STRIDE, 4)
    it.adds = 0
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Baselines, the way TradeSkillMaster does it:
--   Market     - a 14-day average of daily values, weighting the last 3 days more
--   Historical - the 60-day median of daily values (for rare items, which may only
--                show up a few days a month)
-- A "daily value" is the average market price of that day's scans. The latest scan
-- is left out, so a cheap listing being judged can't drag its own yardstick down.
-- ---------------------------------------------------------------------------
local function dailyValues(it, now, days)
  local h = it.h
  if not h then return {} end
  local byDay, order = {}, {}
  for i = 1, #h, STRIDE do
    local t, m = h[i], h[i + 1]
    if m > 0 and now - t <= days * DAY and t ~= it.seen then
      local d = math.floor(t / DAY)
      local e = byDay[d]
      if not e then
        e = { day = d, sum = 0, n = 0, low = m }
        byDay[d] = e
        order[#order + 1] = e
      end
      e.sum, e.n = e.sum + m, e.n + 1
      if m < e.low then e.low = m end
    end
  end
  for _, e in ipairs(order) do e.value = e.sum / e.n end
  return order
end
H.DailyValues = dailyValues

local function median(list)
  local n = #list
  if n == 0 then return nil end
  table.sort(list)
  local mid = math.floor((n + 1) / 2)
  if n % 2 == 1 then return list[mid] end
  return (list[mid] + list[mid + 1]) / 2
end

-- Market value (14 days, recent 3 days count triple). Needs at least 3 earlier
-- points spanning 12 hours; nil otherwise. (Called "fair value" on the Deals tab.)
---@param it GT.Item
---@param now integer
---@return number? copper
function H.FairValue(it, now)
  local h = it.h
  if not h then return nil end
  local first, last, points = nil, nil, 0
  for i = 1, #h, STRIDE do
    if h[i + 1] > 0 and now - h[i] <= 14 * DAY and h[i] ~= it.seen then
      first = first or h[i]
      last = h[i]
      points = points + 1
    end
  end
  if points < 3 or (last - first) < 12 * 3600 then return nil end
  local today = math.floor(now / DAY)
  local sum, weight = 0, 0
  for _, e in ipairs(dailyValues(it, now, 14)) do
    local w = (today - e.day <= 2) and 3 or 1
    sum, weight = sum + e.value * w, weight + w
  end
  return weight > 0 and sum / weight or nil
end

-- Long-term picture for rare finds: the 60-day median of daily values, the item's
-- "cheapest typical" price (its 10th-percentile daily low: cheaper than 90% of its
-- days), how many separate days it was seen, and the 14-day market value for trend.
---@param it GT.Item
---@param now integer
---@return GT.LongTerm?
function H.LongTerm(it, now)
  local days = dailyValues(it, now, 60)
  if #days == 0 then return nil end
  local values, lows = {}, {}
  for _, e in ipairs(days) do
    values[#values + 1] = e.value
    lows[#lows + 1] = e.low
  end
  table.sort(lows)
  local idx = math.max(1, math.floor(#lows * 0.10 + 0.5))
  return {
    historical = median(values),
    typicalLow = lows[idx],
    days = #days,
    market = H.FairValue(it, now),
  }
end

-- One-time repair (0.26.2): before, a day of Auctionator data newer than your last
-- scan replaced the scan's market price with Auctionator's lowest listing of that day.
-- Where a scan of yours from within 2 days of it is in the history, its price comes back.
function H.RepairImportedPrices(realm)
  local fixed = 0
  for _, it in pairs(realm.items) do
    if it.imported and it.seen and it.imported > it.seen and it.imported - it.seen < OWN_PRICE_WINS and not it.src then
      local h = it.h or {}
      for i = #h - STRIDE + 1, 1, -STRIDE do
        if h[i] == it.seen then
          if h[i + 1] and h[i + 1] > 0 and h[i + 1] ~= it.mkt then it.mkt = h[i + 1]; fixed = fixed + 1 end
          break
        end
      end
      it.imported = nil
    end
  end
  return fixed
end
FI:On("PLAYER_LOGIN", function()
  if not FI.db or FI.db.repairedImports then return end
  local ok, fixed = pcall(H.RepairImportedPrices, FI:Realm())
  FI.db.repairedImports = true
  if ok and fixed > 0 then
    FI:Print("Fixed %s prices that an Auctionator import had replaced with a single cheap listing.", FI.Number(fixed))
  end
end)
