-- Goonberg Terminal: learns your recipes and works out crafting profit from AH prices
-- Recipes are read when you open a profession window (C_TradeSkillUI, the API the
-- Forever client uses). Vendor prices are read when you open any merchant, so
-- reagents like vials and thread are priced at what an NPC charges.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Crafting
local K = {}
FI.Crafting = K
local TS = C_TradeSkillUI
---@type fun(v: any): boolean
local secret = issecretvalue or function() return false end
K.AH_CUT = 0.05

function K:CharData()
  local realm = FI:Realm()
  realm.recipes = realm.recipes or {}
  local who = UnitName("player") or "?"
  realm.recipes[who] = realm.recipes[who] or {}
  return realm.recipes[who]
end

local function profName(info)
  return info and (info.professionName or info.parentProfessionName)
end

local function outputItem(recipeID, s)
  local id = s and s.outputItemID
  if (not id or secret(id)) and TS.GetRecipeItemLink then
    local link = TS.GetRecipeItemLink(recipeID)
    id = type(link) == "string" and not secret(link) and tonumber(link:match("|Hitem:(%d+)"))
  end
  if id and not secret(id) and id > 0 then return id end
end

-- flat list: itemID, qty, itemID, qty...
local function reagents(s)
  local out = {}
  local slots = s and s.reagentSlotSchematics
  if type(slots) ~= "table" then return out end
  for _, slot in ipairs(slots) do
    -- only the materials a craft always uses (not optional or finishing slots)
    local basic = slot.required ~= false and (slot.reagentType == nil or slot.reagentType == 1
      or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic))
    local r = basic and slot.reagents and slot.reagents[1]
    local id, qty = r and r.itemID, slot.quantityRequired
    if id and qty and not secret(id) and not secret(qty) then
      out[#out + 1] = id
      out[#out + 1] = qty
    end
  end
  return out
end

-- Reads every learned recipe of the open profession. Returns true when it worked.
function K:Scan()
  if not TS or not TS.GetAllRecipeIDs then return false end
  if TS.IsTradeSkillReady and not TS.IsTradeSkillReady() then return false end
  if (TS.IsTradeSkillLinked and TS.IsTradeSkillLinked()) or (TS.IsTradeSkillGuild and TS.IsTradeSkillGuild()) then return true end
  local prof = profName(TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo())
  if not prof then return false end

  local list = {}
  local count = 0
  for _, id in ipairs(TS.GetAllRecipeIDs() or {}) do
    local r = TS.GetRecipeInfo(id)
    if r and r.learned and r.name then
      -- the list can hold other professions' recipes; keep only this one's
      local p = TS.GetProfessionInfoByRecipeID and profName(TS.GetProfessionInfoByRecipeID(id))
      if not p or p == prof then
        local s = TS.GetRecipeSchematic and TS.GetRecipeSchematic(id, false)
        local out = outputItem(id, s)
        -- enchants make no item, so they can't be sold on the AH
        if out then
          local made = 1
          if s and s.quantityMin and not secret(s.quantityMin) then
            made = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2
          end
          list[id] = { o = out, n = made, r = reagents(s), name = r.name }
          count = count + 1
        end
      end
    end
  end
  if count == 0 then return false end
  self:CharData()[prof] = list
  FI:Fire("FI_RECIPES_CHANGED", prof)
  return true
end

local pending = false
local function tryScan()
  if pending and K:Scan() then pending = false end
end
FI:On("TRADE_SKILL_SHOW", function() pending = true; tryScan() end)
FI:On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() pending = true; tryScan() end)
FI:On("TRADE_SKILL_LIST_UPDATE", tryScan)
FI:On("TRADE_SKILL_CLOSE", function() pending = false end)
FI:On("NEW_RECIPE_LEARNED", function() pending = true end)

-- ---------------------------------------------------------------------------
-- Vendor prices: anything an NPC sells without limit
-- ---------------------------------------------------------------------------
FI:On("MERCHANT_SHOW", function()
  if not GetMerchantNumItems then return end
  FI.db.vendor = FI.db.vendor or {}
  for i = 1, GetMerchantNumItems() do
    local _, _, price, qty, available, _, _, extended = GetMerchantItemInfo(i)
    local id = FI:ItemIDFromLink(GetMerchantItemLink(i))
    if id and price and price > 0 and not extended and available == -1 then
      FI.db.vendor[id] = math.floor(price / math.max(1, qty or 1) + 0.5)
    end
  end
end)

-- Best price to get a reagent: the cheaper of an NPC vendor and the AH market price.
-- Returns price, source ("vendor" | "ah") or nil when unknown.
-- An AH price is only used if it's from the last 7 days; older ones are too stale
-- to plan crafting around (the recipe shows "?" until the item is seen again).
K.MAX_PRICE_AGE = 7 * 86400
-- where an item's current price came from: "scan" (yours), "guild", or an import
-- ("Auctionator": the lowest listing it saw that day)
local function priceSource(it)
  if it.imported and it.imported > (it.seen or 0) then return it.src or "import" end
  if it.shared then return "guild" end
  return "scan"
end
K.PriceSource = priceSource
local function freshMarket(it, maxAge)
  if not it or not it.mkt or it.mkt <= 0 then return nil end
  local t = math.max(it.seen or 0, it.imported or 0)
  if time() - t > (maxAge or K.MAX_PRICE_AGE) then return nil end
  return it.mkt, t, priceSource(it)
end

-- What buying `qty` of an item on the AH costs right now, per unit: walk the price
-- levels from the latest scan (cheapest first). When those are older than 6 hours
-- (or there aren't any), the market price (average of the cheapest 15%) stands in.
-- Returns unitPrice, dataTime, how ("listings" | "market") or nil.
local LISTINGS_FRESH = 6 * 3600
local function ahBuyPrice(it, qty)
  local mkt, t = freshMarket(it)
  if not mkt then return nil end
  qty = math.max(1, qty or 1)
  local d = it.d
  if d and #d >= 2 and it.dt and time() - it.dt < LISTINGS_FRESH and (it.qty or 0) > 0 then
    local got, cost, last = 0, 0, nil
    for i = 1, #d, 2 do
      local take = math.min(d[i + 1], qty - got)
      cost, got, last = cost + take * d[i], got + take, d[i]
      if got >= qty then break end
    end
    if got < qty then cost = cost + (qty - got) * math.max(last or mkt, mkt) end -- past the levels we kept
    return cost / qty, it.dt, "listings"
  end
  local _, _, from = freshMarket(it)
  return mkt, t, from == "scan" and "market" or from
end

-- Best price to get a reagent: the cheaper of an NPC vendor and buying it on the AH.
-- qty: how many you need (the AH price depends on it). Returns unit price,
-- source ("vendor" | "ah"), dataTime, how — or nil when unknown.
function K:ReagentPrice(itemID, qty)
  local vendor = FI.db.vendor and FI.db.vendor[itemID]
  local ah, t, how = ahBuyPrice(FI:Realm().items[itemID], qty)
  if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
  if ah then return ah, "ah", t, how end
end

-- What a crafted item really sells for: you'd have to match the cheapest listing,
-- so it's the lower of the market price and the lowest price right now.
-- maxAge: only a price seen this recently (seconds; default MAX_PRICE_AGE).
---@param itemID integer
---@param maxAge integer?
---@return number?
function K:SellPrice(itemID, maxAge)
  local it = FI:Realm().items[itemID]
  local mkt = freshMarket(it, maxAge)
  if not mkt then return nil end
  if it.min and it.seen and time() - it.seen < 6 * 3600 then return math.min(mkt, it.min) end
  return mkt
end

-- Profit for one recipe. Fields: cost, sell, profit, margin, missing (reagents with
-- no price), noSell (crafted item never seen on the AH), soldPerDay
-- (also: ahValue = what the AH shows for what one craft makes, before the cut;
-- oldest = time of the oldest AH price used; unlisted = the item wasn't on the AH in
-- your latest scan, so its price is the last one seen)
local function unlisted(it, realm)
  return it and realm.lastScan and it.seen and it.seen < realm.lastScan and (it.qty or 0) == 0
end
function K:Evaluate(rec)
  local realm = FI:Realm()
  local res = { cost = 0, missing = 0, reagents = {} }
  for i = 1, #rec.r, 2 do
    local id, qty = rec.r[i], rec.r[i + 1]
    local p, src, t, how = self:ReagentPrice(id, qty)
    local g = { id = id, qty = qty, price = p, src = src, t = t, how = how }
    if src == "ah" then
      g.unlisted = unlisted(realm.items[id], realm)
      if t and (not res.oldest or t < res.oldest) then res.oldest = t end
      if g.unlisted then res.unlistedMats = (res.unlistedMats or 0) + 1 end
    end
    res.reagents[#res.reagents + 1] = g
    if p then res.cost = res.cost + p * qty else res.missing = res.missing + 1 end
  end
  local it = realm.items[rec.o]
  local unit = self:SellPrice(rec.o)
  if unit then
    local t = math.max(it.seen or 0, it.imported or 0)
    if not res.oldest or t < res.oldest then res.oldest = t end
    res.sellT, res.unit = t, unit
    res.unlisted = unlisted(it, realm)
    res.ahValue = unit * rec.n
    res.cut = res.ahValue * self.AH_CUT
    res.sell = unit * rec.n * (1 - self.AH_CUT)
    res.profit = res.sell - res.cost
    if res.cost > 0 then res.margin = res.profit / res.cost * 100 end
    res.soldPerDay = FI.History.Stats(it, time()).soldPerDay
  else
    res.noSell = true
  end
  res.complete = res.missing == 0 and not res.noSell
  return res
end

-- All professions this character has scanned, sorted
function K:Professions()
  local out = {}
  for prof in pairs(self:CharData()) do out[#out + 1] = prof end
  table.sort(out)
  return out
end

-- Rows for the crafting screen
function K:Rows(prof)
  local rows = {}
  local data = self:CharData()
  for p, list in pairs(data) do
    if prof == "All" or p == prof then
      for recipeID, rec in pairs(list) do
        local e = self:Evaluate(rec)
        e.recipeID, e.rec, e.prof = recipeID, rec, p
        e.name = FI:ItemName(rec.o)
        rows[#rows + 1] = e
      end
    end
  end
  return rows
end

-- ---------------------------------------------------------------------------
-- Performance over time: the same maths with prices as they were at time t
-- ---------------------------------------------------------------------------
function K:ProfitAt(rec, t)
  local items = FI:Realm().items
  local cost = 0
  for i = 1, #rec.r, 2 do
    local id, qty = rec.r[i], rec.r[i + 1]
    local vendor = FI.db.vendor and FI.db.vendor[id]
    local ah = FI.History.PriceAt(items[id], t, 2 * 86400)
    local p = vendor and ah and math.min(vendor, ah) or vendor or ah
    if not p then return nil end
    cost = cost + p * qty
  end
  local out = FI.History.PriceAt(items[rec.o], t, 2 * 86400)
  if not out then return nil end
  local profit = out * rec.n * (1 - self.AH_CUT) - cost
  return profit, cost > 0 and (profit / cost * 100) or nil
end

local function median(list)
  if #list == 0 then return nil end
  table.sort(list)
  local m = math.floor((#list + 1) / 2)
  if #list % 2 == 1 then return list[m] end
  return (list[m] + list[m + 1]) / 2
end

-- Everything the crafting overview shows, in one pass
-- The overview is cached until something it depends on changes (or 5 minutes pass:
-- its "7 days ago" moves on), so switching tabs and sorting don't redo the work.
local OVERVIEW_TTL = 300
for _, e in ipairs({ "FI_SCAN_DONE", "FI_DATA_MERGED", "FI_RECIPES_CHANGED", "FI_LEDGER_CHANGED", "MERCHANT_SHOW" }) do
  FI:On(e, function() K.ovCache = nil end)
end

function K:Overview()
  local c = self.ovCache
  if c and c.realm == FI:Realm() and time() - c.at < OVERVIEW_TTL then return c.data end
  local data = self:BuildOverview()
  self.ovCache = { realm = FI:Realm(), at = time(), data = data }
  return data
end

function K:BuildOverview()
  local now = time()
  local rows = self:Rows("All")
  local o = { known = #rows, priced = 0, profitable = 0, pool = 0, profs = {}, movers = {}, days = {} }
  local margins = {}
  local profList = {}
  for _, r in ipairs(rows) do
    local p = o.profs[r.prof]
    if not p then
      p = { name = r.prof, known = 0, profitable = 0, margins = {}, pool = 0 }
      o.profs[r.prof] = p
      profList[#profList + 1] = p
    end
    p.known = p.known + 1
    if r.complete then
      o.priced = o.priced + 1
      if r.margin then margins[#margins + 1] = r.margin; p.margins[#p.margins + 1] = r.margin end
      if r.profit > 0 then
        o.profitable = o.profitable + 1
        p.profitable = p.profitable + 1
        -- profit available per day if you supplied the units that sell
        local crafts = (r.soldPerDay or 0) / math.max(1, r.rec.n)
        o.pool = o.pool + r.profit * crafts
        p.pool = p.pool + r.profit * crafts
        if not p.best or r.profit > p.best.profit then p.best = r end
        if not o.best or (r.margin or 0) > (o.best.margin or 0) then o.best = r end
      end
      -- compare like with like: both sides use market prices from the history
      local then7 = self:ProfitAt(r.rec, now - 7 * 86400)
      local nowP = self:ProfitAt(r.rec, now)
      if then7 and nowP then
        o.movers[#o.movers + 1] = { row = r, delta = nowP - then7, before = then7 }
      end
    end
  end
  o.medianMargin = median(margins)
  for _, p in ipairs(profList) do p.medianMargin = median(p.margins) end
  table.sort(profList, function(a, b) return a.pool > b.pool end)
  o.profList = profList
  table.sort(o.movers, function(a, b) return a.delta > b.delta end)

  -- median margin of your recipes at the end of each of the last 14 days
  for d = 13, 0, -1 do
    local t = now - d * 86400
    local ms = {}
    for _, r in ipairs(rows) do
      local _, m = self:ProfitAt(r.rec, t)
      if m then ms[#ms + 1] = m end
    end
    o.days[#o.days + 1] = { t = t, margin = median(ms), n = #ms }
  end

  -- what crafted items actually earned you (AH sales of things you can craft)
  local craftable = {}
  for _, r in ipairs(rows) do craftable[r.name] = true end
  o.sold7 = 0
  for _, e in ipairs(FI.Ledger:Data().entries) do
    if e.k == "sale" and e.t >= now - 7 * 86400 and craftable[e.i] then
      o.sold7 = o.sold7 + e.g - e.f
    end
  end
  return o
end
