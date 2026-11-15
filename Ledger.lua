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

-- entries: flat list of { t, kind ("sale"|"buy"|"craft"|"use"), item, qty, gross, fee, deal }
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

-- ---------------------------------------------------------------------------
-- Crafting: "You create: [item]" in chat. The recipe (from the Crafting tab's scan)
-- says what went in; the P&L then moves the cost of those materials onto what you
-- made, so selling it counts as a crafted flip, not a farmed sale.
-- ---------------------------------------------------------------------------
local function toPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  fmt = fmt:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. fmt .. "$"
end

-- recipe that makes this item (any profession this character knows)
function L:RecipeFor(itemID)
  local known = FI.Crafting and FI.Crafting:CharData() or {}
  for _, list in pairs(known) do
    for _, rec in pairs(list) do
      if rec.o == itemID then return rec end
    end
  end
end

function L:RecordCraft(itemID, qty, t)
  local rec = self:RecipeFor(itemID)
  if not rec or not rec.r then return false end
  qty = math.max(1, qty or 1)
  local crafts = math.max(1, math.floor(qty / math.max(1, rec.n or 1) + 0.5))
  local used = {}
  for i = 1, #rec.r, 2 do
    local id, n = rec.r[i], rec.r[i + 1]
    local price, source = FI.Crafting:ReagentPrice(id)
    -- { name, count, unit price at the time, bought from a vendor }
    used[#used + 1] = { FI:ItemName(id), n * crafts, price or 0, source == "vendor" or nil }
  end
  local d = self:Data()
  d.entries[#d.entries + 1] = { t = t or time(), k = "craft", i = FI:ItemName(itemID), q = qty, r = used }
  -- the materials leaving your bags were this craft, not "used"
  self.craftCredit, self.craftCreditAt = self.craftCredit or {}, time()
  for _, m in ipairs(used) do self.craftCredit[m[1]] = (self.craftCredit[m[1]] or 0) + m[2] end
  FI:Fire("FI_LEDGER_CHANGED")
  return true
end

local CREATED_ONE = toPattern(_G.LOOT_ITEM_CREATED_SELF or "You create: %s.")
local CREATED_MANY = toPattern(_G.LOOT_ITEM_CREATED_SELF_MULTIPLE or "You create: %sx%d.")
FI:On("CHAT_MSG_LOOT", function(_, msg)
  if type(msg) ~= "string" then return end
  local link, n = msg:match(CREATED_MANY)
  if not link then link = msg:match(CREATED_ONE) end
  local id = link and tonumber(link:match("item:(%d+)"))
  if id then L:RecordCraft(id, tonumber(n) or 1) end
end)

-- ---------------------------------------------------------------------------
-- Used: things you bought on the AH and then used yourself (drank, ate, equipped,
-- used up in an enchant, disenchanted, destroyed). We watch your bags and worn gear:
-- when a bought item goes away while no vendor, bank, mailbox, trade or AH window is
-- open (and it wasn't a craft's materials), it was used. It stops counting as unsold
-- "holding" and shows as Used in the P&L instead. Equipping counts as using; taking
-- gear off and on again doesn't count twice.
-- ---------------------------------------------------------------------------
local busy = {}
local OPENS = { MERCHANT_SHOW = "vendor", BANKFRAME_OPENED = "bank", MAIL_SHOW = "mail", TRADE_SHOW = "trade",
  AUCTION_HOUSE_SHOW = "ah", GUILDBANKFRAME_OPENED = "gbank" }
local CLOSES = { MERCHANT_CLOSED = "vendor", BANKFRAME_CLOSED = "bank", MAIL_CLOSED = "mail", TRADE_CLOSED = "trade",
  AUCTION_HOUSE_CLOSED = "ah", GUILDBANKFRAME_CLOSED = "gbank" }
local USE_DELAY = 2 -- seconds: lets a craft's "You create" message arrive first

local function nameOf(id, link)
  return (id and FI:ItemName(id)) or (link and link:match("%[(.-)%]"))
end

-- what you're carrying and wearing, by item name
function L:Carried()
  local c = { bag = {}, worn = {} }
  if C_Container and C_Container.GetContainerNumSlots then
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local name = info and nameOf(info.itemID, info.hyperlink)
        if name then c.bag[name] = (c.bag[name] or 0) + (info.stackCount or 1) end
      end
    end
  end
  if GetInventoryItemID then
    for slot = 1, 19 do
      local id = GetInventoryItemID("player", slot)
      local name = id and nameOf(id, GetInventoryItemLink and GetInventoryItemLink("player", slot))
      if name then c.worn[name] = (c.worn[name] or 0) + 1 end
    end
  end
  return c
end

-- names you've ever bought on the AH (only those can be "used")
function L:Bought()
  local d = self:Data()
  if not self.boughtSet or self.boughtN ~= #d.entries then
    local set = {}
    for _, e in ipairs(d.entries) do if e.k == "buy" then set[e.i] = true end end
    self.boughtSet, self.boughtN = set, #d.entries
  end
  return self.boughtSet
end

function L:CheckUsed()
  if next(busy) then self.carried = nil; return end -- moving things around: start fresh after
  if (CursorHasItem and CursorHasItem()) or (InCombatLockdown and InCombatLockdown()) then
    FI:Debounce("ledgerUse", USE_DELAY, function() L:CheckUsed() end) -- try again shortly
    return
  end
  local now, before = self:Carried(), self.carried
  self.carried = now
  if not before then return end
  local credit = self.craftCredit or {}
  if self.craftCreditAt and time() - self.craftCreditAt > 15 then credit = {}; self.craftCredit = nil end
  local bought, gone = self:Bought(), {}
  for name in pairs(bought) do
    local b, n = before.bag[name] or 0, now.bag[name] or 0
    local bw, nw = before.worn[name] or 0, now.worn[name] or 0
    local drop = (b + bw) - (n + nw)                 -- left you entirely
    if drop > 0 and credit[name] then
      local c = math.min(drop, credit[name])
      drop, credit[name] = drop - c, credit[name] - c
    end
    local use = math.max(0, drop) + math.max(0, nw - bw) -- plus newly put on
    if use > 0 then gone[name] = use end
  end
  if not next(gone) then return end
  -- only units you still had from the AH (not farmed copies)
  local open = self:Summary(0, "flips").open
  local d, added = self:Data(), 0
  for name, use in pairs(gone) do
    local q = math.min(use, open[name] or 0)
    if q > 0 then
      d.entries[#d.entries + 1] = { t = time(), k = "use", i = name, q = q }
      added = added + 1
    end
  end
  if added > 0 then FI:Fire("FI_LEDGER_CHANGED") end
end

for ev, key in pairs(OPENS) do FI:On(ev, function() busy[key] = true; L.carried = nil end) end
for ev, key in pairs(CLOSES) do
  FI:On(ev, function()
    busy[key] = nil
    -- what came out of the mail or bank is yours now: take stock once it has landed
    C_Timer.After(1, function() if not next(busy) then L.carried = L:Carried() end end)
  end)
end
FI:On("BAG_UPDATE_DELAYED", function() FI:Debounce("ledgerUse", USE_DELAY, function() L:CheckUsed() end) end)
FI:On("PLAYER_EQUIPMENT_CHANGED", function() FI:Debounce("ledgerUse", USE_DELAY, function() L:CheckUsed() end) end)
FI:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, function() L.carried = L:Carried() end) end)

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
      if e.t >= since and e.k ~= "craft" and e.k ~= "use" then -- crafts and uses move no money
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
    local ORDER = { buy = 1, craft = 2, use = 3, sale = 4 }
    table.sort(list, function(x, y)
      if x.t ~= y.t then return x.t < y.t end
      return (ORDER[x.k] or 4) < (ORDER[y.k] or 4)
    end)
    -- your own materials (not bought on the AH): at market price, or free
    local ownAtMarket = (FI.settings and FI.settings.ownMats or "market") ~= "free"
    local lots = {} -- item -> { { qty, unitCost, fromDeal, crafted }, ... } oldest first
    local farmItems = {}
    s.farmGross, s.farmFees, s.dealSales, s.dealNet, s.dealCost = 0, 0, 0, 0, 0
    s.craftSales, s.craftNet, s.craftCost, s.crafts, s.craftCostOf, s.craftOf = 0, 0, 0, 0, {}, {}
    s.used, s.uses, s.usedUnits, s.usedOf, s.usedCostOf = 0, 0, 0, {}, {}
    local function take(name, need)
      local cost, got = 0, 0
      local queue = lots[name]
      while need > 0 and queue and queue[1] do
        local lot = queue[1]
        local n = math.min(need, lot[1])
        cost = cost + n * lot[2]
        got = got + n
        need = need - n
        lot[1] = lot[1] - n
        if lot[1] <= 0 then table.remove(queue, 1) end
      end
      return cost, got
    end
    for _, e in ipairs(list) do
      local q = math.max(1, e.q or 1)
      if e.k == "buy" then
        lots[e.i] = lots[e.i] or {}
        table.insert(lots[e.i], { q, e.g / q, e.deal })
      elseif e.k == "craft" then
        -- bought materials at what they cost you; your own at market (or free);
        -- vendor materials always at the vendor price
        local cost = 0
        for _, m in ipairs(e.r or {}) do
          local c, got = take(m[1], m[2])
          local own = m[2] - got
          if own > 0 then cost = cost + own * ((m[4] or ownAtMarket) and (m[3] or 0) or 0) end
          cost = cost + c
        end
        lots[e.i] = lots[e.i] or {}
        table.insert(lots[e.i], { q, cost / q, nil, true })
        s.craftCostOf[e] = cost
        if e.t >= since then s.crafts = s.crafts + 1 end
      elseif e.k == "use" then
        -- used it yourself: what it cost leaves "holding", but it isn't a loss on a flip
        local cost, got = take(e.i, q)
        s.usedOf[e], s.usedCostOf[e] = got, cost
        if e.t >= since and got > 0 then
          s.used, s.uses, s.usedUnits = s.used + cost, s.uses + 1, s.usedUnits + got
        end
      elseif e.k == "sale" then
        local need, cost, got, dealGot, dealCost, craftGot, craftCost = q, 0, 0, 0, 0, 0, 0
        local queue = lots[e.i]
        while need > 0 and queue and queue[1] do
          local lot = queue[1]
          local take = math.min(need, lot[1])
          cost = cost + take * lot[2]
          got = got + take
          if lot[3] then dealGot = dealGot + take; dealCost = dealCost + take * lot[2] end
          if lot[4] then craftGot = craftGot + take; craftCost = craftCost + take * lot[2] end
          need = need - take
          lot[1] = lot[1] - take
          if lot[1] <= 0 then table.remove(queue, 1) end
        end
        s.flipOf[e] = got
        s.craftOf[e] = craftGot
        if e.t >= since then
          if craftGot > 0 then
            s.craftSales = s.craftSales + 1
            s.craftCost = s.craftCost + craftCost
            s.craftNet = s.craftNet + (e.g - e.f) * craftGot / q - craftCost
          end
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
    s.open = {}
    for name, queue in pairs(lots) do
      for _, lot in ipairs(queue) do
        s.holding = s.holding + lot[1] * lot[2]
        s.holdingUnits = s.holdingUnits + lot[1]
        s.open[name] = (s.open[name] or 0) + lot[1]
      end
    end
    for _, e in ipairs(d.entries) do
      if e.k == "buy" and e.t >= since then s.buys = s.buys + 1 end
    end
    s.net = s.income - s.fees - s.spent
    if s.spent > 0 then s.roi = s.net / s.spent * 100 end
    if s.dealCost > 0 then s.dealRoi = s.dealNet / s.dealCost * 100 end
    if s.craftCost > 0 then s.craftRoi = s.craftNet / s.craftCost * 100 end
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
