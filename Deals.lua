-- Goonberg Terminal: deal finder
-- Looks at the latest scan for listings priced well under what the item is worth:
--   Rare       - a seldom-listed item well under its usual (60-day) price and its usual lows
--   Flip       - under its market value (14-day, recent days weighted); relist near it
--   Vendor     - under what an NPC vendor pays for it; buy and vendor, no waiting
--   Disenchant - gear under its estimated disenchant value
-- A deal must leave a margin (5%+ by default) after the AH's 5% cut where you'd
-- resell on the AH. Total profit counts every unit under the deal price (from depth).
-- Disenchant deals are estimates, so they ask for more: a 10%+ margin, materials
-- priced in the last day, and only as many units as the materials' market can take.
---@type string, GoonbergTerminal
local _, FI = ...
local STRIDE_OF_HISTORY = 4
-- margin = what you pocket per item after any AH cut, divided by what you pay
---@class GT.Deals
local DL = { minMargin = 0.05, alertMargin = 0.10, maxAge = 3600 }
FI.Deals = DL
local CUT = 0.05
DL.DE_MIN_MARGIN = 0.10      -- disenchant deals: at least this margin, whatever the screen asks
DL.DE_PRICE_AGE = 24 * 3600  -- materials priced in the last day only
DL.DE_SELL_DAYS = 2          -- count only as many as the materials' AH sales cover in 2 days

---One deal: an item listed under what it's worth. Prices in copper.
---@class GT.Deal
---@field id integer
---@field kind "Rare"|"Flip"|"Vendor"|"Disenchant"
---@field price integer      the cheapest listing
---@field worth number       what you get for one after any AH cut
---@field ref number         headline value: market value, vendor price, disenchant value or usual price
---@field units integer      units listed under the deal price (Disenchant: at most `cap`)
---@field profit number      total on all of those units
---@field listed integer?    Disenchant: units listed under the deal price before the cap
---@field perItem number     profit on the cheapest one
---@field margin number      perItem / price, in percent
---@field discount number    percent under `ref`
---@field qtyKnown boolean   false for guild scans: only the lowest price is known
---@field levels number[]    the depth it was judged on: flat price, quantity pairs
---@field seen integer
---@field name string?       set when the search finishes
---@field soldPerDay number?
---@field relist number?     Flip and Rare: the price to relist at
---@field typicalLow number? Rare
---@field days integer?      Rare
---@field confidence "Solid"|"Thin"|nil
---@field trendDown boolean? Rare: the whole item is falling
---@field under number?      Rare: percent under the usual price
---@field cap integer?       Disenchant: most units whose materials sell within DE_SELL_DAYS
---@field pace number?       Disenchant: items' worth of materials the AH takes a day (nil = unknown)
---@field slowest integer?   Disenchant: the material that sets that pace
---@field sdEach number?     Disenchant: spread of one item's value after the cut (std. deviation)

local MIN_PROFIT = 100 -- 1s: ignore crumbs

DL.FLOOR = 0.05 -- deals are found once at the loosest margin; screens filter tighter
local PER_FRAME = 250

-- Caches. Vendor prices never change; market values (14-day averages) move slowly, so
-- they're refreshed every 3 hours instead of on every scan.
local vendorCache, fairCache = {}, {}
local FAIR_TTL = 3 * 3600

local function vendorPrice(id)
  local c = vendorCache[id]
  if c ~= nil then return c or nil end
  local name, _, _, _, _, _, _, _, _, _, sell = FI.GetItemInfo(id)
  if name then vendorCache[id] = (sell and sell > 0) and sell or false end
  return sell and sell > 0 and sell or nil
end

local function fairValue(id, it, now)
  local c = fairCache[id]
  if c and now - c.t < FAIR_TTL then return c.v, c.lt end
  local v = FI.History.FairValue(it, now)
  local lt = FI.History.LongTerm(it, now)
  fairCache[id] = { t = now, v = v, lt = lt }
  return v, lt
end

-- ---------------------------------------------------------------------------
-- Rare finds: items that are seldom listed, worth something, and showing up
-- well under their usual price AND under the cheapest they normally go for.
-- ---------------------------------------------------------------------------
function DL:RareSettings()
  local st = FI.settings
  return st.rarePct or 0.20, st.rareMinGold or 50000, st.rareMinDays or 3
end

-- How many days in the last 60 anything was scanned (yours, guild or imported)
local function scanDays60(realm, now)
  local n, today = 0, math.floor(now / 86400)
  for d in pairs(realm.scanDays or {}) do if today - d <= 60 then n = n + 1 end end
  return n
end
DL.scanDays60 = scanDays60

-- Is this item "rare"? Listed on at most half the days the AH was scanned, or
-- usually only a couple listed at a time.
local function isRare(it, lt, realmDays)
  if realmDays >= 5 and lt.days / realmDays <= 0.5 then return true end
  local h, n, total = it.h, 0, 0
  for i = 1, #h, STRIDE_OF_HISTORY do
    if h[i + 1] > 0 then n = n + 1; total = total + (h[i + 2] or 0) end
  end
  return n > 0 and total / n <= 3
end

-- Confidence from how many separate days back the "usual price"
local function confidence(days)
  if days >= 6 then return "Solid" end
  return "Thin"
end

-- Listings to judge: the scan's depth when it's current, else just the lowest price
-- (guild scans carry the lowest price but not depth). qtyKnown says which.
local function listings(it)
  if it.d and it.d[1] and it.dt and it.dt == it.seen then return it.d, true end
  return { it.min, 1 }, false
end

-- Units and profit for listings under `cutoff`, reselling at `worth` each
-- (at most `cap` units when given)
local function judge(levels, worth, cutoff, cap)
  local units, profit = 0, 0
  for i = 1, #levels, 2 do
    local p, q = levels[i], levels[i + 1]
    if p >= cutoff then break end -- levels are cheapest first
    if cap then q = math.min(q, cap - units) end
    if q <= 0 then break end
    units = units + q
    profit = profit + (worth - p) * q
  end
  return units, profit
end

-- Buy below this to make at least `margin` on each item you resell at `worth`
local function cutoffFor(worth, margin) return worth / (1 + margin) end

-- One item: its best deal at the loosest margin (DL.FLOOR), or nil
---@param id integer
---@param it GT.Item
---@param now integer
---@return GT.Deal?
local function evaluate(id, it, now)
  local levels, qtyKnown = listings(it)
  local cheapest = levels[1]
  -- the item can change between queuing and evaluating (a new scan landed)
  if not cheapest or not it.seen or now - it.seen > DL.maxAge then return nil end
  local best
  -- worth: what you get per item (after the AH cut when you resell on the AH)
  -- ref: the headline value (fair value, vendor price, disenchant value)
  local function consider(kind, worth, ref, cap)
    if not worth or worth <= 0 then return end
    local cutoff = cutoffFor(worth, kind == "Disenchant" and DL.DE_MIN_MARGIN or DL.FLOOR)
    if cheapest >= cutoff then return end
    local units, profit = judge(levels, worth, cutoff, cap)
    if profit >= MIN_PROFIT and (not best or profit > best.profit) then
      best = { kind = kind, worth = worth, ref = ref, units = units, profit = profit, cap = cap }
    end
  end
  local fair, lt = fairValue(id, it, now)

  -- Rare find?
  local rarePct, rareMin, rareDays = DL:RareSettings()
  if lt and lt.historical and lt.days >= rareDays and lt.historical >= rareMin
    and isRare(it, lt, DL.realmDays or 0)
    and cheapest <= lt.historical * (1 - rarePct) and cheapest < lt.typicalLow then
    local relist = lt.historical
    if qtyKnown then
      for i = 1, #levels, 2 do
        if levels[i] >= lt.typicalLow then relist = math.min(relist, levels[i] - 1); break end
      end
    end
    local worth = relist * (1 - CUT)
    local cutoff = math.min(lt.typicalLow, cutoffFor(worth, DL.FLOOR))
    local units, profit = judge(levels, worth, cutoff)
    if units > 0 and profit > 0 then
      best = {
        kind = "Rare", worth = worth, ref = lt.historical, units = units, profit = profit, relist = relist,
        typicalLow = lt.typicalLow, days = lt.days, confidence = confidence(lt.days),
        trendDown = lt.market and lt.market < lt.historical * 0.85 or false,
        under = (lt.historical - cheapest) / lt.historical * 100,
      }
    end
  end

  if fair and not best then
    -- Realistic relist price: fair value, unless other sellers are already listed
    -- below it (after the cheap ones you'd buy out). Then you'd have to undercut them.
    local relist = fair
    if qtyKnown then
      local dealLine = fair * (1 - CUT) / (1 + DL.FLOOR)
      for i = 1, #levels, 2 do
        if levels[i] >= dealLine then
          relist = math.min(fair, levels[i] - 1)
          break
        end
      end
    end
    consider("Flip", relist * (1 - CUT), fair)                     -- relist: AH takes 5%
    if best and best.kind == "Flip" then best.relist = relist end
  end
  local vendor = not (best and best.kind == "Rare") and vendorPrice(id)
  if vendor then consider("Vendor", vendor, vendor) end             -- NPC pays in full
  local DE = FI.Disenchant
  if not (best and best.kind == "Rare") and DE:Results(id) then
    -- mats sold on the AH, priced in the last day; count only as many units as the
    -- mats' sales cover in DE_SELL_DAYS (buying more would flood their market)
    local de, complete, parts = DE:Value(id, DL.DE_PRICE_AGE)
    if de and complete and parts and cheapest < cutoffFor(de * (1 - CUT), DL.DE_MIN_MARGIN) then
      local pace, slowest = DE:ItemsPerDay(parts, de, now)
      local cap = pace and math.max(1, math.floor(pace * DL.DE_SELL_DAYS + 1e-6)) -- 19.999... is 20
      consider("Disenchant", de * (1 - CUT), de, cap)
      if best and best.kind == "Disenchant" then
        best.pace, best.slowest = pace, slowest
        best.sdEach = DE:Spread(parts) * (1 - CUT)
      end
    end
  end
  if not best then return nil end
  best.id = id
  best.price = cheapest
  best.discount = (best.ref - cheapest) / best.ref * 100
  best.perItem = best.worth - cheapest                    -- on the cheapest one
  best.margin = best.perItem / cheapest * 100
  best.qtyKnown = qtyKnown
  best.levels = levels
  best.seen = it.seen
  return best
end

-- Units and profit of a deal at a stricter margin (e.g. 0.20); nil if it no longer
-- qualifies. Third value: units listed under that price before any cap.
---@param d GT.Deal
---@param minMargin number
---@return integer? units
---@return number? profit
---@return integer? listed
function DL:At(d, minMargin)
  if d.kind == "Rare" then return d.units, d.profit, d.units end -- judged by its own rule
  if d.kind == "Disenchant" then minMargin = math.max(minMargin, DL.DE_MIN_MARGIN) end
  local cutoff = cutoffFor(d.worth, minMargin)
  if d.price >= cutoff then return nil end
  local units, profit = judge(d.levels, d.worth, cutoff, d.cap)
  if profit < MIN_PROFIT then return nil end
  local listed = d.cap and judge(d.levels, d.worth, cutoff) or units
  return units, profit, listed
end

local function finish(d, now)
  if d.kind == "Disenchant" then
    -- what matters is selling the materials: items' worth of them sold a day
    d.soldPerDay = d.pace
  else
    local it = FI:Realm().items[d.id]
    d.soldPerDay = it and FI.History.Stats(it, now).soldPerDay
  end
  d.name, d.loading = FI:ItemName(d.id)
end

local function candidates(realm, now, maxAge)
  local ids = {}
  for id, it in pairs(realm.items) do
    if it.min and it.seen and now - it.seen <= maxAge then ids[#ids + 1] = id end
  end
  return ids
end

-- Applies a minimum margin to a raw list (units and total profit recomputed)
function DL:Filter(list, minMargin)
  local out = {}
  for _, d in ipairs(list) do
    local units, profit, listed = self:At(d, minMargin)
    if units then
      local c = setmetatable({ units = units, profit = profit, listed = listed }, { __index = d })
      out[#out + 1] = c
    end
  end
  return out
end

-- All deals right now at self.minMargin, in one go (commands, tests)
function DL:Find(now)
  now = now or time()
  local realm = FI:Realm()
  self.realmDays = scanDays60(realm, now)
  local raw = {}
  for _, id in ipairs(candidates(realm, now, self.maxAge)) do
    local d = evaluate(id, realm.items[id], now)
    if d then finish(d, now); raw[#raw + 1] = d end
  end
  self.last = { scan = realm.lastScan, raw = raw, at = now }
  return self:Filter(raw, self.minMargin)
end

-- The same search spread over many frames, so a big AH never freezes the game.
-- onDone(raw) runs when it's finished. A newer run replaces one still going.
local runner = CreateFrame("Frame")
runner:Hide()
function DL:Run(onDone)
  local realm = FI:Realm()
  local now = time()
  self.realmDays = scanDays60(realm, now)
  self.job = { ids = candidates(realm, now, self.maxAge), i = 0, raw = {}, now = now, scan = realm.lastScan, onDone = onDone }
  runner:Show()
end
function DL:Running() return self.job ~= nil end

runner:SetScript("OnUpdate", function(self)
  local job = DL.job
  if not job then self:Hide(); return end
  local items = FI:Realm().items
  local last = math.min(#job.ids, job.i + PER_FRAME)
  local start = debugprofilestop()
  for n = job.i + 1, last do
    -- at most ~6 ms of work per frame
    if n > job.i + 10 and debugprofilestop() - start > 6 then last = n - 1; break end
    local id = job.ids[n]
    local it = items[id]
    local d = it and evaluate(id, it, job.now)
    if d then job.raw[#job.raw + 1] = d end
  end
  job.i = last
  if job.i >= #job.ids then
    for _, d in ipairs(job.raw) do finish(d, job.now) end
    DL.last = { scan = job.scan, raw = job.raw, at = job.now }
    DL.job = nil
    self:Hide()
    if job.onDone then job.onDone(job.raw) end
    FI:Fire("FI_DEALS_READY")
  end
end)

-- Cached deals for the latest scan (nil while none have been found yet)
function DL:Latest()
  local realm = FI:Realm()
  if self.last and self.last.scan == realm.lastScan then return self.last.raw end
end

-- ---------------------------------------------------------------------------
-- Deal alerts: after a live scan, a pop-up when new deals add up to enough gold
-- ---------------------------------------------------------------------------
local function alert(raw)
  if FI.settings.dealAlerts == false then return end
  local threshold = FI.settings.dealAlertGold or 50000 -- 5g
  local deals = DL:Filter(raw, DL.alertMargin)
  local seen = DL.alerted or {}
  local fresh, total = 0, 0
  local top ---@type GT.Deal?
  local now = {}
  for _, d in ipairs(deals) do
    now[d.id] = true
    if not seen[d.id] then
      fresh = fresh + 1
      total = total + d.profit
      if not top or d.profit > top.profit then top = d end
    end
  end
  DL.alerted = now
  -- Rare finds: one pop-up for the best new one, whatever the total
  if FI.settings.rareAlerts ~= false then
    local rareSeen = DL.rareAlerted or {}
    local bestRare
    local nowRare = {}
    for _, d in ipairs(raw) do
      if d.kind == "Rare" then
        nowRare[d.id] = true
        if not rareSeen[d.id] and (not bestRare or d.profit > bestRare.profit) then bestRare = d end
      end
    end
    DL.rareAlerted = nowRare
    if bestRare then
      FI.Alerts:Toast(bestRare.id,
        ("Rare find: %s"):format(bestRare.name),
        ("%s, %d%% under its usual %s (seen %d days). Click to view."):format(FI.Coins(bestRare.price), math.floor(bestRare.under), FI.Coins(bestRare.ref), bestRare.days),
        function() FI.DealsTab.kind = "Rare"; FI.UI:Show("deals") end)
      return
    end
  end
  if top and fresh > 0 and total >= threshold then
    FI.Alerts:Toast(top.id,
      ("%d new deal%s worth %s"):format(fresh, fresh == 1 and "" or "s", FI.Coins(total)),
      ("Best: %s, +%s each (%d%% margin). Click to view."):format(top.name, FI.Coins(top.perItem), math.floor(top.margin)),
      function() FI.UI:Show("deals") end)
  end
end

-- After a scan (yours or a guildmate's), wait for things to settle, then search once.
-- Several guild scans arriving together cause one search, not several.
-- Pop-ups only come from your own scans: a guildmate's scan updates the Deals tab
-- quietly (/goon deals guildalerts on brings their pop-ups back).
local ownScan = false
FI:On("FI_SCAN_DONE", function(_, _, from)
  if from == nil or FI.settings.guildDealAlerts then ownScan = true end
  FI:Debounce("deals", 2, function()
    local loud = ownScan
    ownScan = false
    DL:Run(loud and alert or nil)
  end)
end)

-- Found out an item can't be disenchanted (or can): search again without alerts
FI:On("FI_DISENCHANT_LEARNED", function()
  FI:Debounce("deals", 1, function() DL:Run() end)
end)
