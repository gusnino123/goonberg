-- Goonberg Terminal: deal finder
-- Looks at the latest scan for listings priced well under what the item is worth:
--   Flip       - at least N% under its 7-day fair value; relist near fair value
--   Vendor     - under what an NPC vendor pays for it; buy and vendor, no waiting
--   Disenchant - gear under its estimated disenchant value
-- Profit counts every unit under the deal price (from market depth) and takes off
-- the AH's 5% cut where you'd resell on the AH.
local _, FI = ...
local DL = { minDiscount = 0.30, maxAge = 3600 }
FI.Deals = DL
local CUT = 0.05
local MIN_PROFIT = 100 -- 1s: ignore crumbs

local function vendorPrice(id)
  local sell = select(11, FI.GetItemInfo(id))
  return sell and sell > 0 and sell or nil
end

-- Listings to judge: the scan's depth when it's current, else just the lowest price
-- (guild scans carry the lowest price but not depth). qtyKnown says which.
local function listings(it)
  if it.d and it.d[1] and it.dt and it.dt == it.seen then return it.d, true end
  return { it.min, 1 }, false
end

-- One candidate deal type: worth (per unit, net), cutoff (buy below this)
local function judge(levels, worth, cutoff)
  local units, profit = 0, 0
  for i = 1, #levels, 2 do
    local p, q = levels[i], levels[i + 1]
    if p < cutoff then
      units = units + q
      profit = profit + (worth - p) * q
    end
  end
  return units, profit
end

function DL:Find(now)
  now = now or time()
  local realm = FI:Realm()
  local H = FI.History
  local out = {}
  for id, it in pairs(realm.items) do
    if it.min and it.seen and now - it.seen <= self.maxAge then
      local levels, qtyKnown = listings(it)
      local best
      local function consider(kind, worth, cutoff, ref)
        if not worth or worth <= 0 or levels[1] >= cutoff then return end
        local units, profit = judge(levels, worth, cutoff)
        if profit >= MIN_PROFIT and (not best or profit > best.profit) then
          best = { kind = kind, worth = worth, ref = ref, units = units, profit = profit }
        end
      end
      -- Flip: resell on the AH near fair value
      local fair = H.FairValue(it, now)
      if fair then
        consider("Flip", fair * (1 - CUT), fair * (1 - self.minDiscount), fair)
      end
      -- Vendor: an NPC pays this, no cut, no waiting
      local vendor = vendorPrice(id)
      if vendor then consider("Vendor", vendor, vendor, vendor) end
      -- Disenchant: materials resold on the AH
      local de, complete = FI.Disenchant:Value(id)
      if de and complete then
        consider("Disenchant", de * (1 - CUT), de * (1 - CUT) * (1 - self.minDiscount), de)
      end
      if best then
        local s = H.Stats(it, now)
        best.id = id
        best.price = levels[1]
        best.discount = (best.ref - levels[1]) / best.ref * 100
        best.qtyKnown = qtyKnown
        best.soldPerDay = s.soldPerDay
        best.seen = it.seen
        best.name = FI:ItemName(id)
        out[#out + 1] = best
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Deal alerts: after a live scan, a pop-up when new deals add up to enough gold
-- ---------------------------------------------------------------------------
FI:On("FI_SCAN_DONE", function()
  if FI.settings.dealAlerts == false then return end
  local threshold = FI.settings.dealAlertGold or 50000 -- 5g
  local deals = DL:Find(time())
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
      ("Best: %s, %d%% under %s value. Click to view."):format(top.name, math.floor(top.discount), top.kind:lower()),
      function() FI.UI:Show("deals") end)
  end
end)
