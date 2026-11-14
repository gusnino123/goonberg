-- Goonberg Terminal: deal finder
-- Looks at the latest scan for listings priced well under what the item is worth:
--   Flip       - under its 7-day fair value; relist near fair value
--   Vendor     - under what an NPC vendor pays for it; buy and vendor, no waiting
--   Disenchant - gear under its estimated disenchant value
-- A deal must leave a margin (5%+ by default) after the AH's 5% cut where you'd
-- resell on the AH. Total profit counts every unit under the deal price (from depth).
local _, FI = ...
-- margin = what you pocket per item after any AH cut, divided by what you pay
local DL = { minMargin = 0.05, alertMargin = 0.10, maxAge = 3600 }
FI.Deals = DL
local CUT = 0.05
local MIN_PROFIT = 100 -- 1s: ignore crumbs

DL.FLOOR = 0.05 -- deals are found once at the loosest margin; screens filter tighter
local PER_FRAME = 250

-- Caches. Vendor prices never change; fair values (7-day medians) move slowly, so
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
  if c and now - c.t < FAIR_TTL then return c.v end
  local v = FI.History.FairValue(it, now)
  fairCache[id] = { t = now, v = v }
  return v
end

-- Listings to judge: the scan's depth when it's current, else just the lowest price
-- (guild scans carry the lowest price but not depth). qtyKnown says which.
local function listings(it)
  if it.d and it.d[1] and it.dt and it.dt == it.seen then return it.d, true end
  return { it.min, 1 }, false
end

-- Units and profit for listings under `cutoff`, reselling at `worth` each
local function judge(levels, worth, cutoff)
  local units, profit = 0, 0
  for i = 1, #levels, 2 do
    local p, q = levels[i], levels[i + 1]
    if p >= cutoff then break end -- levels are cheapest first
    units = units + q
    profit = profit + (worth - p) * q
  end
  return units, profit
end

-- Buy below this to make at least `margin` on each item you resell at `worth`
local function cutoffFor(worth, margin) return worth / (1 + margin) end

-- One item: its best deal at the loosest margin (DL.FLOOR), or nil
local function evaluate(id, it, now)
  local levels, qtyKnown = listings(it)
  local cheapest = levels[1]
  -- the item can change between queuing and evaluating (a new scan landed)
  if not cheapest or not it.seen or now - it.seen > DL.maxAge then return nil end
  local best
  -- worth: what you get per item (after the AH cut when you resell on the AH)
  -- ref: the headline value (fair value, vendor price, disenchant value)
  local function consider(kind, worth, ref)
    if not worth or worth <= 0 then return end
    local cutoff = cutoffFor(worth, DL.FLOOR)
    if cheapest >= cutoff then return end
    local units, profit = judge(levels, worth, cutoff)
    if profit >= MIN_PROFIT and (not best or profit > best.profit) then
      best = { kind = kind, worth = worth, ref = ref, units = units, profit = profit }
    end
  end
  local fair = fairValue(id, it, now)
  if fair then
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
  local vendor = vendorPrice(id)
  if vendor then consider("Vendor", vendor, vendor) end             -- NPC pays in full
  if FI.Disenchant:Results(id) then
    local de, complete = FI.Disenchant:Value(id)
    if de and complete then consider("Disenchant", de * (1 - CUT), de) end -- mats sold on the AH
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

-- Units and profit of a deal at a stricter margin (e.g. 0.20); nil if it no longer qualifies
function DL:At(d, minMargin)
  local cutoff = cutoffFor(d.worth, minMargin)
  if d.price >= cutoff then return nil end
  local units, profit = judge(d.levels, d.worth, cutoff)
  if profit < MIN_PROFIT then return nil end
  return units, profit
end

local function finish(d, now)
  local it = FI:Realm().items[d.id]
  d.soldPerDay = it and FI.History.Stats(it, now).soldPerDay
  d.name = FI:ItemName(d.id)
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
    local units, profit = self:At(d, minMargin)
    if units then
      local c = setmetatable({ units = units, profit = profit }, { __index = d })
      out[#out + 1] = c
    end
  end
  return out
end

-- All deals right now at self.minMargin, in one go (commands, tests)
function DL:Find(now)
  now = now or time()
  local realm = FI:Realm()
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
  self.job = { ids = candidates(realm, now, self.maxAge), i = 0, raw = {}, now = now, scan = realm.lastScan, onDone = onDone }
  runner:Show()
end
function DL:Running() return self.job ~= nil end

runner:SetScript("OnUpdate", function(self)
  local job = DL.job
  if not job then self:Hide(); return end
  local items = FI:Realm().items
  local last = math.min(#job.ids, job.i + PER_FRAME)
  for n = job.i + 1, last do
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
  local fresh, total, top = 0, 0, nil
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
  if fresh > 0 and total >= threshold then
    FI.Alerts:Toast(top.id,
      ("%d new deal%s worth %s"):format(fresh, fresh == 1 and "" or "s", FI.Money(total)),
      ("Best: %s, +%s each (%d%% margin). Click to view."):format(top.name, FI.Money(top.perItem), math.floor(top.margin)),
      function() FI.UI:Show("deals") end)
  end
end

-- After a scan (yours or a guildmate's), wait for things to settle, then search once.
-- Several guild scans arriving together cause one search, not several.
FI:On("FI_SCAN_DONE", function()
  FI:Debounce("deals", 2, function() DL:Run(alert) end)
end)
