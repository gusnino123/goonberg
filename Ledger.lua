-- Goonberg Terminal: profit and loss from Auction House mail invoices
-- Every AH sale and purchase arrives as mail with an invoice. When the mailbox is
-- open we read those invoices once each and keep a ledger per character.
local _, FI = ...
local L = {}
FI.Ledger = L
local DAY = 86400
local MAIL_DAYS = 30 -- AH mail lasts 30 days, so daysLeft tells us roughly when it was sent

function L:Data()
  local realm = FI:Realm()
  local who = UnitName("player") or "?"
  realm.ledger = realm.ledger or {}
  local d = realm.ledger[who]
  if not d then
    d = { entries = {}, inbox = {} }
    realm.ledger[who] = d
  end
  return d
end

-- entries: flat list of { t, kind ("sale"|"buy"), item, qty, gross, fee, deal }
-- deal = true: a purchase of something you'd just opened from the Deals tab
local DEAL_WINDOW = 3 * DAY
function L:TagDeal(d, e)
  local picked = e.k == "buy" and d.dealPicks and d.dealPicks[e.i]
  if picked and time() - picked <= DEAL_WINDOW and e.t >= picked - DAY then e.deal = true end
end

local function add(d, t, kind, item, qty, gross, fee)
  local e = { t = t, k = kind, i = item, q = qty or 1, g = gross or 0, f = fee or 0 }
  L:TagDeal(d, e)
  d.entries[#d.entries + 1] = e
end

-- The Deals tab calls this when you open a deal on the AH, so buying it afterwards
-- counts as a Deals-tab flip in the P&L.
function L:MarkDeal(itemName)
  if not itemName then return end
  local d = self:Data()
  d.dealPicks = d.dealPicks or {}
  local now = time()
  for name, t in pairs(d.dealPicks) do
    if now - t > DEAL_WINDOW then d.dealPicks[name] = nil end
  end
  d.dealPicks[itemName] = now
end

function L:ReadInbox()
  if not GetInboxNumItems or not GetInboxInvoiceInfo then return end
  local d = self:Data()
  local now = time()
  local counts, info = {}, {}
  for i = 1, GetInboxNumItems() do
    local invoiceType, itemName, playerName, bid, _, deposit, consignment, _, _, count = GetInboxInvoiceInfo(i)
    if invoiceType == "seller" or invoiceType == "buyer" then
      local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(i)
      local key = table.concat({ invoiceType, itemName or "?", playerName or "?", bid or 0, deposit or 0, consignment or 0 }, "|")
      counts[key] = (counts[key] or 0) + 1
      info[key] = { invoiceType, itemName, bid or 0, consignment or 0, count, daysLeft }
    end
  end
  -- Mail we've already counted stays in the inbox; only new copies are added.
  local added = 0
  for key, n in pairs(counts) do
    local seen = d.inbox[key] or 0
    if n > seen then
      local inv = info[key]
      local sent = now - math.max(0, MAIL_DAYS - (inv[6] or MAIL_DAYS)) * DAY
      for _ = 1, n - seen do
        if inv[1] == "seller" then
          add(d, sent, "sale", inv[2], inv[5], inv[3], inv[4])
        else
          add(d, sent, "buy", inv[2], inv[5], inv[3], 0)
        end
        added = added + 1
      end
    end
    d.inbox[key] = n
  end
  -- Mail that was taken: forget it so an identical sale later still counts
  for key in pairs(d.inbox) do
    if not counts[key] then d.inbox[key] = nil end
  end
  if added > 0 then FI:Fire("FI_LEDGER_CHANGED") end
end

FI:On("MAIL_INBOX_UPDATE", function()
  FI:Debounce("ledger", 0.5, function() L:ReadInbox() end)
end)
FI:On("MAIL_SHOW", function() L:ReadInbox() end)

-- Totals since `since` (a time), for this character.
--
-- mode "flips" (the default): only items you bought on the AH and sold again count.
-- Each sale is matched against your earlier AH purchases of the same item, oldest
-- first, and its profit is what you got (after the AH cut) minus what those units
-- cost. Units you never bought on the AH (farmed, crafted, looted) aren't counted,
-- and neither are purchases you haven't sold yet ("holding").
-- mode "all": every sale and every purchase, the way the AH mail adds up.
function L:Summary(since, mode)
  mode = mode or (FI.settings and FI.settings.pnlMode) or "flips"
  local d = self:Data()
  local s = { income = 0, fees = 0, spent = 0, sales = 0, buys = 0, items = {}, mode = mode,
    farmed = 0, farmedSales = 0, holding = 0, holdingUnits = 0, flipOf = {} }

  if mode == "all" then
    for _, e in ipairs(d.entries) do
      if e.t >= since then
        local per = s.items[e.i] or { net = 0 }
        s.items[e.i] = per
        if e.k == "sale" then
          s.income = s.income + e.g
          s.fees = s.fees + e.f
          s.sales = s.sales + 1
          per.net = per.net + e.g - e.f
        else
          s.spent = s.spent + e.g
          s.buys = s.buys + 1
          per.net = per.net - e.g
        end
      end
    end
    s.net = s.income - s.fees - s.spent
    -- ROI only means something when you mostly flip; for farmers it'd be a silly 500%+
    if s.spent > 0 and s.spent >= (s.income - s.fees) * 0.25 then s.roi = s.net / s.spent * 100 end
  else
    -- every trade in time order (purchases first on the same timestamp), whatever
    -- the period: a sale this week can use stock bought last month
    local list = {}
    for _, e in ipairs(d.entries) do list[#list + 1] = e end
    table.sort(list, function(x, y)
      if x.t ~= y.t then return x.t < y.t end
      return x.k == "buy" and y.k ~= "buy"
    end)
    local lots = {} -- item -> { { qty, unitCost, fromDeal }, ... } oldest first
    local farmItems = {}
    s.farmGross, s.farmFees, s.dealSales, s.dealNet, s.dealCost = 0, 0, 0, 0, 0
    for _, e in ipairs(list) do
      local q = math.max(1, e.q or 1)
      if e.k == "buy" then
        lots[e.i] = lots[e.i] or {}
        table.insert(lots[e.i], { q, e.g / q, e.deal })
      else
        local need, cost, got, dealGot, dealCost = q, 0, 0, 0, 0
        local queue = lots[e.i]
        while need > 0 and queue and queue[1] do
          local lot = queue[1]
          local take = math.min(need, lot[1])
          cost = cost + take * lot[2]
          got = got + take
          if lot[3] then dealGot = dealGot + take; dealCost = dealCost + take * lot[2] end
          need = need - take
          lot[1] = lot[1] - take
          if lot[1] <= 0 then table.remove(queue, 1) end
        end
        s.flipOf[e] = got
        if e.t >= since then
          local share = got / q
          if got > 0 then
            local income, fee = e.g * share, e.f * share
            s.income = s.income + income
            s.fees = s.fees + fee
            s.spent = s.spent + cost
            s.sales = s.sales + 1
            local per = s.items[e.i] or { net = 0 }
            s.items[e.i] = per
            per.net = per.net + income - fee - cost
          end
          if dealGot > 0 then
            local ds = dealGot / q
            s.dealSales = s.dealSales + 1
            s.dealCost = s.dealCost + dealCost
            s.dealNet = s.dealNet + (e.g - e.f) * ds - dealCost
          end
          if got < q then
            local fs = 1 - share
            s.farmed = s.farmed + (e.g - e.f) * fs
            s.farmGross = s.farmGross + e.g * fs
            s.farmFees = s.farmFees + e.f * fs
            s.farmedSales = s.farmedSales + 1
            farmItems[e.i] = (farmItems[e.i] or 0) + (e.g - e.f) * fs
          end
        end
      end
    end
    for name, v in pairs(farmItems) do
      if not s.farmTop or v > s.farmTop.net then s.farmTop = { name = name, net = v } end
    end
    -- bought and not sold yet (any time): their cost
    for _, queue in pairs(lots) do
      for _, lot in ipairs(queue) do
        s.holding = s.holding + lot[1] * lot[2]
        s.holdingUnits = s.holdingUnits + lot[1]
      end
    end
    for _, e in ipairs(d.entries) do
      if e.k == "buy" and e.t >= since then s.buys = s.buys + 1 end
    end
    s.net = s.income - s.fees - s.spent
    if s.spent > 0 then s.roi = s.net / s.spent * 100 end
    if s.dealCost > 0 then s.dealRoi = s.dealNet / s.dealCost * 100 end
    -- everything you made on the AH: flipping profit plus farming income
    s.total = s.net + s.farmed
  end
  for name, per in pairs(s.items) do
    if not s.best or per.net > s.best.net then s.best = { name = name, net = per.net } end
  end
  return s
end

-- What your bags would fetch at market price right now (not yet sold, so "unrealized")
function L:BagValue()
  if not C_Container or not C_Container.GetContainerNumSlots then return 0 end
  local realm = FI:Realm()
  local total = 0
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isBound then
        local it = realm.items[info.itemID]
        if it and it.mkt then total = total + it.mkt * (info.stackCount or 1) end
      end
    end
  end
  return total
end
