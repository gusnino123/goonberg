-- Goonberg Terminal: profit and loss from Auction House mail invoices
-- Every AH sale and purchase arrives as mail with an invoice. When the mailbox is
-- open we read those invoices once each and keep a ledger per character.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Ledger
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
    d = { entries = {}, seen = {} }
    realm.ledger[who] = d
  end
  return d
end

-- entries: flat list of { t, kind ("sale"|"buy"|"craft"|"use"|"de"), item, qty, gross, fee, deal }
-- deal = true: a purchase of something you'd just opened from the Deals tab
local DEAL_WINDOW = 3 * DAY
function L:TagDeal(d, e)
  local picked = e.k == "buy" and d.dealPicks and d.dealPicks[e.i]
  if picked and e.t >= picked - 300 and e.t - picked <= DEAL_WINDOW then e.deal = true end
end

local function add(d, t, kind, item, qty, gross, fee)
  local e = { t = t, k = kind, i = item, q = qty or 1, g = gross or 0, f = fee or 0, v = 2 }
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

-- How many items an AH invoice was for. The invoice says (its 11th value); if a
-- client leaves it out, the item attached to a purchase or "(20)" in a sale's subject does.
local function invoiceCount(i, invoiceType, count)
  if type(count) == "number" and count > 0 then return count, true end
  if invoiceType == "buyer" and GetInboxItem then
    local _, _, _, n = GetInboxItem(i, 1)
    if type(n) == "number" and n > 0 then return n, true end
  end
  local _, _, _, subject = GetInboxHeaderInfo(i)
  local n = type(subject) == "string" and tonumber(subject:match("%((%d+)%)%s*$"))
  if n and n > 0 then return n, true end
  return 1, false
end

-- Reading the mailbox. Each AH mail is recognised by what it's for (buyer/seller,
-- item, price, AH cut) plus when it was sent, so reading the same mail again - every
-- time the mailbox opens, or before WoW has finished loading it - never counts it twice.
-- Identical mails sent together (someone buying three of your identical stacks) are
-- counted by how many there are.
local SAME_MAIL = 180 -- seconds: the same mail's send time, worked out on two reads, can drift a little
function L:ReadInbox()
  if not GetInboxNumItems or not GetInboxInvoiceInfo then return end
  local d = self:Data()
  local now = time()
  local n = GetInboxNumItems() or 0
  local found = {}
  for i = 1, n do
    local invoiceType, itemName, _, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(i)
    if (invoiceType == "seller" or invoiceType == "buyer") and itemName then
      local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(i)
      local qty, known = invoiceCount(i, invoiceType, count)
      local key = table.concat({ invoiceType, itemName, bid or 0, consignment or 0, qty }, "|")
      local sent = now - math.max(0, MAIL_DAYS - (daysLeft or MAIL_DAYS)) * DAY
      local list = found[key]
      if not list then list = {}; found[key] = list end
      -- mails of the same kind sent together form one group
      local grp
      for _, g in ipairs(list) do if math.abs(g.t - sent) <= SAME_MAIL then grp = g end end
      if not grp then
        grp = { t = sent, n = 0, inv = { invoiceType, itemName, bid or 0, consignment or 0, qty, known, deposit or 0 } }
        list[#list + 1] = grp
      end
      grp.n = grp.n + 1
    end
  end
  if n == 0 then return end -- nothing loaded (yet): never a reason to change anything

  d.seen = d.seen or {}
  -- moving from the old way of remembering mail: what it had counted is counted
  local old = d.inbox
  local added = 0
  for key, groups in pairs(found) do
    local seen = d.seen[key] or {}
    d.seen[key] = seen
    for _, g in ipairs(groups) do
      local rec
      for _, r in ipairs(seen) do if math.abs(r.t - g.t) <= SAME_MAIL then rec = r end end
      if not rec then
        rec = { t = g.t, n = 0 }
        seen[#seen + 1] = rec
        if old then
          -- counted before this version (under its old key): don't add it again, but
          -- fix the quantity those entries were saved with
          local inv = g.inv
          local oldKey
          for k in pairs(old) do
            local t, item, _, bid, _, cut = k:match("^([^|]*)|(.-)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
            if t == inv[1] and item == inv[2] and tonumber(bid) == inv[3] and tonumber(cut) == inv[4] then oldKey = k end
          end
          if oldKey and (old[oldKey] or 0) > 0 then
            local take = math.min(g.n, old[oldKey])
            old[oldKey] = old[oldKey] - take
            rec.n = take
            self:RepairQuantity(inv, take)
          end
        end
      end
      if g.n > rec.n then
        local inv = g.inv
        for _ = 1, g.n - rec.n do
          if inv[1] == "seller" then
            add(d, g.t, "sale", inv[2], inv[5], inv[3], inv[4])
          else
            add(d, g.t, "buy", inv[2], inv[5], inv[3], 0)
          end
          if not inv[6] then d.entries[#d.entries].qGuess = true end
          added = added + 1
        end
        rec.n = g.n
      end
    end
  end
  if old then d.inbox = nil end
  -- forget mail long gone (AH mail lasts 30 days)
  for key, seen in pairs(d.seen) do
    for i = #seen, 1, -1 do if now - seen[i].t > (MAIL_DAYS + 2) * DAY then table.remove(seen, i) end end
    if #seen == 0 then d.seen[key] = nil end
  end
  d.lastInbox = now
  if added > 0 then FI:Fire("FI_LEDGER_CHANGED") end
end

-- Entries saved before 0.25 have the wrong quantity (they read the wrong invoice field).
-- When their mail is still in the mailbox we learn the right one.
function L:RepairQuantity(inv, howMany)
  local d = self:Data()
  local k = inv[1] == "seller" and "sale" or "buy"
  for _, e in ipairs(d.entries) do
    if howMany <= 0 then break end
    if not e.v and e.k == k and e.i == inv[2] and e.g == inv[3] and (k == "buy" or e.f == inv[4]) then
      e.q, e.v = inv[5], 2
      howMany = howMany - 1
    end
  end
end

-- trades saved before 0.25 that couldn't be repaired: their quantity is unknown
function L:LegacyCount()
  local n = 0
  for _, e in ipairs(self:Data().entries) do
    if not e.v and (e.k == "buy" or e.k == "sale") then n = n + 1 end
  end
  return n
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

-- One "You create" message is one craft, however many it made (1-3 for some recipes).
function L:RecordCraft(itemID, qty, t, linkName)
  local rec = self:RecipeFor(itemID)
  if not rec or not rec.r then return false end
  local name = FI:ItemName(itemID) or linkName
  if not name then return false end
  qty = math.max(1, qty or 1)
  local used = {}
  for i = 1, #rec.r, 2 do
    local id, n = rec.r[i], rec.r[i + 1]
    local price, source = FI.Crafting:ReagentPrice(id, n)
    local mat = FI:ItemName(id)
    if not mat then return false end -- can't tell what went in yet: better not guess
    -- { name, count, unit price at the time, bought from a vendor }
    used[#used + 1] = { mat, n, price or 0, source == "vendor" or nil }
  end
  local d = self:Data()
  d.entries[#d.entries + 1] = { t = t or time(), k = "craft", i = name, q = qty, r = used, v = 2 }
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
  if id then L:RecordCraft(id, tonumber(n) or 1, nil, link:match("%[(.-)%]")) end
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
  local c = { bag = {}, worn = {}, ids = {} }
  if C_Container and C_Container.GetContainerNumSlots then
    for bag = 0, 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local name = info and nameOf(info.itemID, info.hyperlink)
        if name then
          c.bag[name] = (c.bag[name] or 0) + (info.stackCount or 1)
          c.ids[name] = info.itemID
        end
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

-- names that can have units from the AH in them: bought, crafted, or disenchanted into
function L:Bought()
  local d = self:Data()
  if not self.boughtSet or self.boughtN ~= #d.entries then
    local set = {}
    for _, e in ipairs(d.entries) do
      if e.k == "buy" or e.k == "craft" then set[e.i] = true end
      if e.k == "de" then for _, o in ipairs(e.out or {}) do set[o[1]] = true end end
    end
    self.boughtSet, self.boughtN = set, #d.entries
  end
  return self.boughtSet
end

-- Disenchanting: the spell goes off, the item leaves your bags, the dust lands in
-- them. We note the cast and what you loot right after, and when the bag watcher sees
-- the item gone it's logged as a disenchant (its cost moves onto the dust) instead of "used".
local DISENCHANT = 13262
local LOOT_ONE = toPattern(_G.LOOT_ITEM_SELF or "You receive loot: %s.")
local LOOT_MANY = toPattern(_G.LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.")
local PUSH_ONE = toPattern(_G.LOOT_ITEM_PUSHED_SELF or "You receive item: %s.")
local PUSH_MANY = toPattern(_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE or "You receive item: %sx%d.")
FI:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit ~= "player" then return end
  local isDE = spellID == DISENCHANT
  if not isDE and GetSpellInfo and spellID then
    local n = GetSpellInfo(spellID)
    isDE = n ~= nil and n == GetSpellInfo(DISENCHANT)
  end
  if isDE then L.de = { t = time(), out = {} } end
end)
-- The item and amount in one of your own loot messages ("You receive loot: [X]x3."),
-- or nil. Disenchant.lua uses it too.
---@param msg any
---@return integer? itemID
---@return integer qty
---@return string? link
function L.LootFromChat(msg)
  if type(msg) ~= "string" then return nil, 0 end
  local link, n = msg:match(LOOT_MANY)
  if not link then link, n = msg:match(PUSH_MANY) end
  if not link then link = msg:match(LOOT_ONE) or msg:match(PUSH_ONE) end
  local id = link and tonumber(link:match("item:(%d+)"))
  return id, tonumber(n) or 1, link
end
FI:On("CHAT_MSG_LOOT", function(_, msg)
  local de = L.de
  if not de or type(msg) ~= "string" or time() - de.t > 6 then return end
  local id, n, link = L.LootFromChat(msg)
  if not id then return end
  local name = nameOf(id, link)
  local mkt = L:PriceByName(name)
  de.out[#de.out + 1] = { name, n, mkt or 0 }
end)

-- What a vendor pays for an item (GetItemInfo's 11th value)
local function vendorPrice(id)
  if not id then return 0 end
  local p = select(11, FI.GetItemInfo(id))
  return tonumber(p) or 0
end

-- At a vendor: things you sold to it. Buying something back undoes the sale.
function L:CheckVendor()
  local now, before = self:Carried(), self.carried
  self.carried = now
  if not before then return end
  local bought, d, changed = self:Bought(), self:Data(), false
  local visit = self.vendorVisit or {}
  self.vendorVisit = visit
  local open
  for name in pairs(bought) do
    local diff = (now.bag[name] or 0) - (before.bag[name] or 0)
    if diff < 0 then
      open = open or self:Summary(0, "flips").open
      local q = math.min(-diff, open[name] or 0)
      if q > 0 then
        local unit = vendorPrice(before.ids[name])
        local e = visit[name]
        if e then
          e.q, e.g = e.q + q, e.g + unit * q
        else
          e = { t = time(), k = "vendor", i = name, q = q, g = unit * q, f = 0, v = 2 }
          d.entries[#d.entries + 1] = e
          visit[name] = e
        end
        open[name] = open[name] - q
        changed = true
      end
    elseif diff > 0 and visit[name] then
      -- bought back
      local e = visit[name]
      local back = math.min(diff, e.q)
      e.g = e.g - e.g / e.q * back
      e.q = e.q - back
      if e.q <= 0 then
        for i = #d.entries, 1, -1 do if d.entries[i] == e then table.remove(d.entries, i) break end end
        visit[name] = nil
      end
      changed = true
    end
  end
  if changed then FI:Fire("FI_LEDGER_CHANGED") end
end

function L:CheckUsed()
  if busy.vendor and not next(busy, next(busy)) and next(busy) == "vendor" then
    if CursorHasItem and CursorHasItem() then
      FI:Debounce("ledgerUse", USE_DELAY, function() L:CheckUsed() end)
      return
    end
    return self:CheckVendor()
  end
  if next(busy) then self.carried = nil; return end -- moving things around: start fresh after
  -- a disenchant whose dust hasn't landed yet: give it a moment
  if self.de and #self.de.out == 0 and time() - self.de.t < 4 then
    FI:Debounce("ledgerUse", USE_DELAY, function() L:CheckUsed() end)
    return
  end
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
  -- the item you just disenchanted
  local de = self.de
  if de and time() - de.t <= 10 and #de.out > 0 then
    local target
    for name, use in pairs(gone) do
      if (open[name] or 0) > 0 and use > 0 and not target then target = name end
    end
    if target then
      d.entries[#d.entries + 1] = { t = time(), k = "de", i = target, q = 1, out = de.out }
      gone[target] = gone[target] - 1
      open[target] = open[target] - 1
      added = added + 1
    end
    self.de = nil
  end
  for name, use in pairs(gone) do
    local q = math.min(use, open[name] or 0)
    if q > 0 then
      d.entries[#d.entries + 1] = { t = time(), k = "use", i = name, q = q }
      added = added + 1
    end
  end
  if added > 0 then FI:Fire("FI_LEDGER_CHANGED") end
end

for ev, key in pairs(OPENS) do
  FI:On(ev, function()
    busy[key] = true
    if key == "vendor" then L.vendorVisit = {} else L.carried = nil end
  end)
end
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
  local hideOld = FI.settings and FI.settings.pnlHideOld
  local s = { income = 0, fees = 0, spent = 0, sales = 0, buys = 0, items = {}, mode = mode,
    farmed = 0, farmedSales = 0, holding = 0, holdingUnits = 0, flipOf = {} }

  if mode == "all" then
    for _, e in ipairs(d.entries) do
      local old = hideOld and not e.v and (e.k == "buy" or e.k == "sale")
      if e.i and not old and e.t >= since and (e.k == "sale" or e.k == "buy" or e.k == "vendor") then -- crafts, uses and disenchants move no money
        local per = s.items[e.i] or { net = 0 }
        s.items[e.i] = per
        if e.k == "sale" or e.k == "vendor" then
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
    for _, e in ipairs(d.entries) do
      if e.i and not (hideOld and not e.v and (e.k == "buy" or e.k == "sale")) then list[#list + 1] = e end
    end
    local ORDER = { buy = 1, craft = 2, de = 2, use = 3, sale = 4, vendor = 4 }
    table.sort(list, function(x, y)
      if x.t ~= y.t then return x.t < y.t end
      return (ORDER[x.k] or 4) < (ORDER[y.k] or 4)
    end)
    -- your own materials (not bought on the AH): at market price, or free
    local ownAtMarket = (FI.settings and FI.settings.ownMats or "market") ~= "free"
    -- lots: item -> { { qty, unitCost, fromDeal, crafted, root, ownPerUnit }, ... } oldest first.
    -- ownPerUnit: how much of the cost is your own materials at market price (gold you
    -- never spent: it's added back to Farming, so the total is the gold you really made)
    -- root: the entry that started the position these units belong to. A craft, a
    -- disenchant or a sale that uses units from several positions joins them into one
    -- (like a stock position: it stays one position until you're flat).
    local lots = {}
    local parent = {}
    local function find(x)
      while parent[x] and parent[x] ~= x do x = parent[x] end
      return x
    end
    local function join(roots, fallback)
      local r
      for _, x in ipairs(roots) do
        x = find(x)
        if not r then r = x elseif x ~= r then parent[x] = r end
      end
      r = r or fallback
      parent[r] = parent[r] or r
      return r
    end
    s.steps, s.find, s.lots = {}, find, lots
    local function step(t) s.steps[#s.steps + 1] = t; return t end
    local farmItems = {}
    s.farmGross, s.farmFees, s.dealSales, s.dealNet, s.dealCost = 0, 0, 0, 0, 0
    s.craftSales, s.craftNet, s.craftCost, s.crafts, s.craftCostOf, s.craftOf = 0, 0, 0, 0, {}, {}
    s.used, s.uses, s.usedUnits, s.usedOf, s.usedCostOf = 0, 0, 0, {}, {}
    s.deCostOf = {}
    -- take `need` units of an item from the oldest lots
    local function take(name, need)
      local r = { cost = 0, got = 0, own = 0, dealGot = 0, dealCost = 0, craftGot = 0, craftCost = 0, roots = {} }
      local queue = lots[name]
      while need > 0 and queue and queue[1] do
        local lot = queue[1]
        local n = math.min(need, lot[1])
        local c = n * lot[2]
        r.cost, r.got, need = r.cost + c, r.got + n, need - n
        r.own = r.own + n * (lot[6] or 0)
        if lot[3] then r.dealGot, r.dealCost = r.dealGot + n, r.dealCost + c end
        if lot[4] then r.craftGot, r.craftCost = r.craftGot + n, r.craftCost + c end
        r.roots[#r.roots + 1] = lot[5]
        lot[1] = lot[1] - n
        if lot[1] <= 0 then table.remove(queue, 1) end
      end
      return r
    end
    local function put(name, q, unit, deal, crafted, root, ownUnit)
      lots[name] = lots[name] or {}
      table.insert(lots[name], { q, unit, deal, crafted, root, ownUnit or 0 })
    end
    s.ownSold = 0
    for _, e in ipairs(list) do
      local q = math.max(1, e.q or 1)
      if e.k == "buy" then
        parent[e] = e
        put(e.i, q, e.g / q, e.deal, nil, e)
        step({ e = e, root = e, kind = "buy", q = q, cost = e.g })
      elseif e.k == "craft" then
        -- bought materials at what they cost you; your own at market (or free);
        -- vendor materials always at the vendor price
        local cost, own, ownMkt, roots, mats = 0, 0, 0, {}, {}
        for _, m in ipairs(e.r or {}) do
          local r = take(m[1], m[2])
          local mine = m[2] - r.got
          local c = (mine > 0) and mine * ((m[4] or ownAtMarket) and (m[3] or 0) or 0) or 0
          own = own + c
          if not m[4] then ownMkt = ownMkt + c end -- vendor mats are gold you really spent
          ownMkt = ownMkt + r.own
          cost = cost + c + r.cost
          for _, x in ipairs(r.roots) do roots[#roots + 1] = x end
          mats[#mats + 1] = { name = m[1], n = m[2], bought = r.got, vendor = m[4], cost = c + r.cost }
        end
        local root = join(roots, e)
        put(e.i, q, cost / q, nil, true, root, ownMkt / q)
        s.craftCostOf[e] = cost
        step({ e = e, root = root, kind = "craft", q = q, cost = cost, own = own, mats = mats })
        if e.t >= since then s.crafts = s.crafts + 1 end
      elseif e.k == "de" then
        -- disenchanted something you bought: its cost moves onto the dust and shards,
        -- shared out by what each was worth at the time
        local r = take(e.i, q)
        if r.got > 0 then
          local root = join(r.roots, e)
          local total, outs = 0, e.out or {}
          for _, o in ipairs(outs) do total = total + math.max(1, o[3] or 0) * o[2] end
          for _, o in ipairs(outs) do
            local share = (total > 0) and (math.max(1, o[3] or 0) * o[2] / total) or (1 / #outs)
            put(o[1], o[2], r.cost * share / o[2], nil, true, root, r.own * share / o[2])
          end
          s.deCostOf[e] = r.cost
          step({ e = e, root = root, kind = "de", q = r.got, cost = r.cost, outs = outs })
        end
      elseif e.k == "use" then
        -- used it yourself: what it cost leaves "holding", but it isn't a loss on a flip
        local r = take(e.i, q)
        s.usedOf[e], s.usedCostOf[e] = r.got, r.cost
        if r.got > 0 then
          step({ e = e, root = join(r.roots, e), kind = "use", q = r.got, cost = r.cost })
          if e.t >= since then
            s.used, s.uses, s.usedUnits = s.used + r.cost, s.uses + 1, s.usedUnits + r.got
          end
        end
      elseif e.k == "sale" or e.k == "vendor" then
        local r = take(e.i, q)
        local got, cost = r.got, r.cost
        local vendor = e.k == "vendor"
        s.flipOf[e] = got
        s.saleCostOf = s.saleCostOf or {}
        s.saleCostOf[e] = cost
        s.craftOf[e] = r.craftGot
        local share = got / q
        if got > 0 then
          step({ e = e, root = join(r.roots, e), kind = "sale", vendor = vendor, q = got, of = q, cost = cost,
            gross = e.g * share, fee = e.f * share, net = (e.g - e.f) * share })
        end
        if e.t >= since then
          if r.craftGot > 0 then
            s.craftSales = s.craftSales + 1
            s.craftCost = s.craftCost + r.craftCost
            s.craftNet = s.craftNet + (e.g - e.f) * r.craftGot / q - r.craftCost
          end
          if got > 0 then
            s.ownSold = s.ownSold + r.own
            local income, fee = e.g * share, e.f * share
            s.income = s.income + income
            s.fees = s.fees + fee
            s.spent = s.spent + cost
            s.sales = s.sales + 1
            local per = s.items[e.i] or { net = 0 }
            s.items[e.i] = per
            per.net = per.net + income - fee - cost
          end
          if r.dealGot > 0 then
            s.dealSales = s.dealSales + 1
            s.dealCost = s.dealCost + r.dealCost
            s.dealNet = s.dealNet + (e.g - e.f) * r.dealGot / q - r.dealCost
          end
          if got < q and not vendor then -- (only AH sales count as farming)
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
    -- Your own materials at market price were counted as a cost of the crafts that
    -- sold, but you never spent that gold: it's what your farmed mats earned, so it
    -- goes to Farming. Flipping + Farming = the gold you really made.
    s.farmed = s.farmed + s.ownSold
    s.ownMatsSold = s.ownSold
    s.total = s.net + s.farmed
  end
  for name, per in pairs(s.items) do
    if not s.best or per.net > s.best.net then s.best = { name = name, net = per.net } end
  end
  return s
end

-- Market price by item name (the ledger knows names, the price data knows IDs)
function L:PriceByName(name)
  local realm = FI:Realm()
  if not self.nameIndex or self.nameIndexAt ~= realm then
    self.nameIndex, self.nameIndexAt = {}, realm
    for id, it in pairs(realm.items) do
      local n = it.n or FI.GetItemInfo(id)
      if n then self.nameIndex[n] = id end
    end
  end
  local id = self.nameIndex[name]
  if id == nil then
    -- not indexed: look once, and remember a miss until the next scan
    for i, it in pairs(realm.items) do if it.n == name then id = i; break end end
    self.nameIndex[name] = id or false
  end
  local it = id and realm.items[id]
  return it and it.mkt, id
end

FI:On("FI_SCAN_DONE", function() L.nameIndex = nil end)
FI:On("FI_DATA_MERGED", function() L.nameIndex = nil end)

-- Positions: each chain from buying to selling, like a broker's trade history.
-- Bought 20 Light Leather -> crafted 4 gloves -> sold 2, sold 2 = one position.
-- Units from different purchases that end up in the same craft or sale join into
-- one position; a position is closed once none of its units are left.
-- Returns a list of { steps, cost, proceeds, soldCost, usedCost, realized, roi,
-- openUnits, openCost, openValue, opened, closed, last, status, name, deal }
local AH_CUT = 0.05
function L:Positions(since)
  since = since or 0
  local s = self:Summary(0, "flips")
  local find, groups, order = s.find, {}, {}
  for _, st in ipairs(s.steps) do
    local r = find(st.root)
    local g = groups[r]
    if not g then
      g = { steps = {}, cost = 0, own = 0, realizedIn = 0, salesIn = 0, proceeds = 0, gross = 0, fees = 0, soldCost = 0, usedCost = 0,
        openUnits = 0, openCost = 0, openValue = 0, unpriced = 0, opened = st.e.t, last = st.e.t, ins = {}, outs = {} }
      groups[r] = g
      order[#order + 1] = g
    end
    g.steps[#g.steps + 1] = st
    if not st.e.v and (st.kind == "buy" or st.kind == "sale") then g.legacy = true end
    g.last = math.max(g.last, st.e.t)
    g.opened = math.min(g.opened, st.e.t)
    if st.kind == "buy" then
      g.cost = g.cost + st.cost
      g.ins[st.e.i] = true
      if st.e.deal then g.deal = true end
    elseif st.kind == "craft" then
      g.own = g.own + st.own
      g.cost = g.cost + st.own -- your own and vendor materials join the cost
      g.ownMats = g.ownMats or {}
      for _, m in ipairs(st.mats or {}) do if m.bought < m.n then g.ownMats[m.name] = true end end
      g.crafted = true
    elseif st.kind == "de" then
      g.disenchanted = true
    elseif st.kind == "use" then
      g.usedCost = g.usedCost + st.cost
    elseif st.kind == "sale" then
      g.proceeds = g.proceeds + st.net
      g.gross = g.gross + st.gross
      g.fees = g.fees + st.fee
      g.soldCost = g.soldCost + st.cost
      if st.e.t >= since then g.realizedIn, g.salesIn = g.realizedIn + st.net - st.cost, g.salesIn + 1 end
      g.outs[st.e.i] = true
      g.closed = st.e.t
    end
  end
  -- what's still held, and what it's worth now (after the AH cut)
  for name, queue in pairs(s.lots) do
    for _, lot in ipairs(queue) do
      local g = lot[5] and groups[find(lot[5])]
      if g and lot[1] > 0 then
        g.openUnits = g.openUnits + lot[1]
        g.openCost = g.openCost + lot[1] * lot[2]
        local mkt = self:PriceByName(name)
        if mkt then g.openValue = g.openValue + lot[1] * mkt * (1 - AH_CUT) else g.unpriced = g.unpriced + lot[1] end
        g.held = g.held or {}
        g.held[name] = (g.held[name] or 0) + lot[1]
      end
    end
  end
  local out = {}
  for _, g in ipairs(order) do
    table.sort(g.steps, function(a, b)
      if a.e.t ~= b.e.t then return a.e.t < b.e.t end
      local O = { buy = 1, craft = 2, de = 2, use = 3, sale = 4 }
      return O[a.kind] < O[b.kind]
    end)
    g.realized = g.proceeds - g.soldCost
    if g.soldCost > 0 then g.roi = g.realized / g.soldCost * 100 end
    g.status = g.openUnits > 0 and "open" or "closed"
    if g.status == "open" then
      g.closed = nil
      g.unrealized = g.openValue - g.openCost
    end
    -- a name: what went in -> what came out
    local function names(set, skip)
      local list = {}
      for n in pairs(set) do if not (skip and skip[n]) then list[#list + 1] = n end end
      table.sort(list)
      if #list > 2 then return list[1] .. " +" .. (#list - 1) end
      return table.concat(list, " + ")
    end
    -- (made only from your own materials: those are what went in)
    local ins = names(next(g.ins) and g.ins or (g.ownMats or {}))
    local outs = names(g.outs, g.ins)
    if outs == "" and g.held then outs = names(g.held, g.ins) end
    g.name = (ins ~= "" and outs ~= "") and (ins .. " > " .. outs) or (ins ~= "" and ins or outs)
    -- only positions that did something in the period (a sale only counts when it
    -- closed a position, an open one counts while it's open)
    if g.last >= since or g.status == "open" then
      -- positions with nothing bought or sold (a craft from your own mats, not sold) aren't trades
      if g.cost > 0 or g.proceeds > 0 then out[#out + 1] = g end
    end
  end
  return out, s
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
