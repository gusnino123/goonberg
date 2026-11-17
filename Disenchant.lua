-- Goonberg Terminal: estimated disenchant value
-- Expected value of disenchanting a piece of gear: each possible result's chance x
-- average quantity x what that material sells for. The game doesn't tell addons what
-- an item disenchants into, so this starts from the WoW Forever disenchanting table:
-- bands by the item's REQUIRED level (the "Requires Level" line), not its item level.
-- Source: wow-professions.com/forever/disenchanting-guide (checked November 2026).
-- Every disenchant you do is recorded (which table row went in, what came out), and
-- that row's chances and amounts move toward what you actually get.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Disenchant
local D = {}
FI.Disenchant = D

-- Materials
local DUST = { strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204 }
local ESS = {
  lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134,
  gmystic = 11135, lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203,
}
local SHARD = {
  sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177,
  lrad = 11178, sbril = 14343, lbril = 14344,
}
local NEXUS = 20725
local IS_MATERIAL = { [NEXUS] = true }
for _, t in ipairs({ DUST, ESS, SHARD }) do for _, id in pairs(t) do IS_MATERIAL[id] = true end end

-- Uncommon (green) gear by REQUIRED level:
-- { maxRequiredLevel, dust, avgDust, essence, avgEssence, shard }
-- Quantities are the averages of the table's ranges (1-2 -> 1.5, 2-5 -> 3.5...).
local GREEN = {
  { 10, DUST.strange, 1.5, ESS.lmagic, 1.5, nil },
  { 15, DUST.strange, 2.5, ESS.gmagic, 1.5, SHARD.sglim },
  { 20, DUST.strange, 5, ESS.lastral, 1.5, SHARD.sglim },
  { 25, DUST.soul, 1.5, ESS.gastral, 1.5, SHARD.lglim },
  { 30, DUST.soul, 3.5, ESS.lmystic, 1.5, SHARD.sglow },
  { 35, DUST.vision, 1.5, ESS.gmystic, 1.5, SHARD.lglow },
  { 40, DUST.vision, 3.5, ESS.lnether, 1.5, SHARD.srad },
  { 45, DUST.dream, 1.5, ESS.gnether, 1.5, SHARD.lrad },
  { 50, DUST.dream, 3.5, ESS.leternal, 1.5, SHARD.sbril },
  { 55, DUST.illusion, 1.5, ESS.geternal, 1.5, SHARD.lbril },
  { 999, DUST.illusion, 3.5, ESS.geternal, 2, SHARD.lbril },
}
-- Rare (blue) and low-level epic gear: the band's shard
local SHARD_BY_LEVEL = {
  { 20, SHARD.sglim }, { 25, SHARD.lglim }, { 30, SHARD.sglow }, { 35, SHARD.lglow },
  { 40, SHARD.srad }, { 45, SHARD.lrad }, { 50, SHARD.sbril }, { 999, SHARD.lbril },
}
-- Uncommon chances: armor 75% dust / 20% essence; weapons swap dust and essence.
-- The guide gives the shard as 3-5%: 4% is the middle, so the estimate doesn't lean
-- on luck (the 1% left over is simply not counted).
local MAIN, SIDE, SHARD_CHANCE = 0.75, 0.20, 0.04
local NEXUS_FROM_BLUE = 0.005 -- "extremely rarely (about 0.5%)", level 51+

-- Each lesser essence can be combined 3 -> 1 greater (and split back), so an
-- essence is worth whichever way sells for more.
local ESSENCE_PAIRS = {
  { ESS.lmagic, ESS.gmagic }, { ESS.lastral, ESS.gastral }, { ESS.lmystic, ESS.gmystic },
  { ESS.lnether, ESS.gnether }, { ESS.leternal, ESS.geternal },
}
local lesserOf, greaterOf = {}, {}
for _, p in ipairs(ESSENCE_PAIRS) do greaterOf[p[1]] = p[2]; lesserOf[p[2]] = p[1] end

-- Slots that can't be disenchanted even though they're "armor"
local NOT_DISENCHANTABLE = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true }

-- Some gear can't be disenchanted at all (Greater Magic Wand, PvP rewards, ...):
-- FI.NoDisenchant (Disenchant/NoDE.lua) lists them from the classic item data.
-- WoW Forever can differ, so what you find out in game wins: a disenchant that works
-- clears an item, "Item cannot be disenchanted" blocks it (saved in FI.db.deLearned).
function D:Learned(itemID)
  local l = FI.db and FI.db.deLearned
  return l and l[itemID]
end

function D:CanDisenchant(itemID)
  local learned = self:Learned(itemID)
  if learned ~= nil then return learned end
  return not (FI.NoDisenchant and FI.NoDisenchant[itemID])
end

local function band(list, level)
  for _, row in ipairs(list) do if level <= row[1] then return row end end
end

---Where a piece of gear sits in the disenchanting table.
---@class GT.DEBand
---@field key string       the table row: quality, level band, and weapon or armor for greens
---@field quality integer
---@field level integer    required level
---@field weapon boolean

-- Items in the same row disenchant the same way, so what you learn from one counts
-- for all of them. nil when the item can't be disenchanted; known = false while its
-- info is still loading.
---@param itemID integer
---@return GT.DEBand? band
---@return boolean known
function D:Band(itemID)
  if not self:CanDisenchant(itemID) then return nil, true end
  local _, _, _, equipLoc, _, classID = FI.GetItemInfoInstant(itemID)
  if classID ~= 2 and classID ~= 4 then return nil, true end -- not gear: never
  if equipLoc and NOT_DISENCHANTABLE[equipLoc] then return nil, true end
  local _, _, quality, ilvl, reqLevel = FI.GetItemInfo(itemID)
  if not quality then return nil, false end -- not loaded yet: ask again later
  if quality < 2 or quality > 4 then return nil, true end
  -- The table uses the required level. A few items have none; item level runs
  -- about 5 above required level, so use that as the stand-in.
  local level = (reqLevel and reqLevel > 0) and reqLevel or math.max(1, (ilvl or 1) - 5)
  local weapon = classID == 2
  local key
  if quality == 2 then
    key = ("2-%d-%s"):format(band(GREEN, level)[1], weapon and "w" or "a")
  elseif quality == 4 and level > 50 then
    key = level >= 56 and "4-56" or "4-51"
  else
    key = ("%d-%d"):format(quality, band(SHARD_BY_LEVEL, level)[1])
  end
  return { key = key, quality = quality, level = level, weapon = weapon }, true
end

-- What an item can turn into: list of { itemID, chance, avgQty }, or nil.
-- These only change when you disenchant something, so they're worked out once and
-- cached (false = "can't be disenchanted"; items still loading aren't cached).
---@alias GT.DEResult { [1]: integer, [2]: number, [3]: number }  material itemID, chance (0-1), average quantity

---@class GT.DEPart
---@field id integer
---@field chance number
---@field qty number      average quantity
---@field price number?   what one sells for (nil = no recent price)
---@field converted boolean?  priced as the other essence size (3 lesser = 1 greater)
---@field sellAs integer?     the essence it's sold as when converted
---@field t integer?          when that price was seen (scan or import)

-- maxAge for D:Value that takes every material's last known price, however old
D.LAST_KNOWN = math.huge

local resultsCache = {}
function D:ForgetCache() resultsCache = {} end
FI:On("FI_MARKET_CHANGED", function() resultsCache = {} end) -- mats cost something else there
---@param itemID integer
---@return GT.DEResult[]?
function D:Results(itemID)
  local c = resultsCache[itemID]
  if c ~= nil then return c or nil end
  local r, known = self:ComputeResults(itemID)
  if known then resultsCache[itemID] = r or false end
  return r
end

-- Your own disenchants, blended into the table's numbers. The table counts as PRIOR
-- disenchants: after 20 of your own from that row it's half yours, after 100 mostly yours.
-- Amounts work the same way, with the table counting as QTY_PRIOR results.
local PRIOR, QTY_PRIOR = 20, 10
---@param results GT.DEResult[]
---@param seen {n: integer, out: table<integer, {h: integer, q: integer}>}?
---@return GT.DEResult[]
local function blend(results, seen)
  if not seen or (seen.n or 0) == 0 then return results end
  local out, done = {}, {}
  for _, r in ipairs(results) do
    local s = seen.out[r[1]]
    local hits, qty = s and s.h or 0, s and s.q or 0
    out[#out + 1] = { r[1], (r[2] * PRIOR + hits) / (PRIOR + seen.n), (r[3] * QTY_PRIOR + qty) / (QTY_PRIOR + hits) }
    done[r[1]] = true
  end
  -- something you got that the table doesn't list for this row
  for id, s in pairs(seen.out) do
    if not done[id] and s.h > 0 then out[#out + 1] = { id, s.h / (PRIOR + seen.n), s.q / s.h } end
  end
  return out
end

---@param itemID integer
---@return GT.DEResult[]? results
---@return boolean known  false while the item's info is still loading
function D:ComputeResults(itemID)
  local b, known = self:Band(itemID)
  if not b then return nil, known end
  local level = b.level
  local r ---@type GT.DEResult[]
  if b.quality == 2 then
    local row = band(GREEN, level)
    local dust, ess = b.weapon and SIDE or MAIN, b.weapon and MAIN or SIDE
    if not row[6] then
      -- no shard at this level: dust and essence share all the chances
      local total = dust + ess
      r = { { row[2], dust / total, row[3] }, { row[4], ess / total, row[5] } }
    else
      r = { { row[2], dust, row[3] }, { row[4], ess, row[5] }, { row[6], SHARD_CHANCE, 1 } }
    end
  elseif b.quality == 3 then
    local shard = band(SHARD_BY_LEVEL, level)[2]
    if level >= 51 then
      r = { { shard, 1 - NEXUS_FROM_BLUE, 1 }, { NEXUS, NEXUS_FROM_BLUE, 1 } }
    else
      r = { { shard, 1, 1 } }
    end
  elseif level <= 50 then
    -- "Level 50 and below always gives a shard; high-level epics always give a crystal."
    -- The guide doesn't give quantities: 1 shard, and 1-2 crystals at 56+, are estimates.
    r = { { band(SHARD_BY_LEVEL, level)[2], 1, 1 } }
  else
    r = { { NEXUS, 1, level >= 56 and 1.5 or 1 } }
  end
  return blend(r, FI.db and FI.db.deYields and FI.db.deYields[b.key]), true
end

-- How many of your own disenchants back an item's numbers (0 = the table alone)
---@param itemID integer
---@return integer
function D:Samples(itemID)
  local b = self:Band(itemID)
  local row = b and FI.db and FI.db.deYields and FI.db.deYields[b.key]
  return row and row.n or 0
end

-- What one unit of a material sells for: the lower of its market price and the
-- cheapest listing now (what you'd have to match), only if seen within maxAge
-- (7 days by default). Essences take the better of selling as-is or converting
-- (3 lesser = 1 greater); sellAs is then the essence you'd sell.
---@param id integer
---@param maxAge integer?  seconds
---@return number? price
---@return integer? sellAs
function D:MaterialPrice(id, maxAge)
  local C = FI.Crafting
  local best, as = C:SellPrice(id, maxAge), nil
  if greaterOf[id] then
    local g = C:SellPrice(greaterOf[id], maxAge)
    if g and (not best or g / 3 > best) then best, as = g / 3, greaterOf[id] end
  elseif lesserOf[id] then
    local l = C:SellPrice(lesserOf[id], maxAge)
    if l and (not best or l * 3 > best) then best, as = l * 3, lesserOf[id] end
  end
  return best, as
end

-- When a material's price was seen (your scan, a guild scan or an import)
local function priceTime(id)
  local it = FI:Realm().items[id]
  local t = it and math.max(it.seen or 0, it.imported or 0)
  return t and t > 0 and t or nil
end

-- A rare extra (like a Nexus Crystal from a blue) with no recent price counts as
-- nothing rather than blocking the whole estimate.
local MINOR = 0.02

-- The oldest price behind a value (ignoring rare extras), for "mat prices 3 days ago"
---@param parts GT.DEPart[]
---@return integer?
function D:OldestPrice(parts)
  local oldest
  for _, p in ipairs(parts) do
    if p.t and p.chance >= MINOR and (not oldest or p.t < oldest) then oldest = p.t end
  end
  return oldest
end

-- Expected value in copper (before the AH's cut on the materials);
-- complete = every result that matters has a price. parts lists each result.
---@param itemID integer
---@param maxAge integer?  only material prices seen this recently (seconds; default 7 days)
---@return number? value  copper, before the AH cut
---@return boolean? complete
---@return GT.DEPart[]? parts
function D:Value(itemID, maxAge)
  local results = self:Results(itemID)
  if not results then return nil end
  local value, complete = 0, true
  local parts = {}
  for _, r in ipairs(results) do
    local price, as = self:MaterialPrice(r[1], maxAge)
    if price then
      value = value + r[2] * r[3] * price
    elseif r[2] >= MINOR then
      complete = false
    end
    parts[#parts + 1] = {
      id = r[1], chance = r[2], qty = r[3], price = price, converted = as ~= nil, sellAs = as,
      t = price and priceTime(as or r[1]) or nil,
    }
  end
  if value == 0 and not complete then return nil, false, parts end
  return value, complete, parts
end

-- How far one disenchant's value swings from the average (standard deviation in
-- copper, before the AH cut). Each disenchant gives one kind of material, and an
-- amount like "2-5" varies about 30% around its average.
local QTY_SPREAD = 0.3
---@param parts GT.DEPart[]
---@return number
function D:Spread(parts)
  local mean, sq = 0, 0
  for _, p in ipairs(parts) do
    if p.price then
      local v = p.qty * p.price
      local s = p.qty > 1 and QTY_SPREAD or 0
      mean = mean + p.chance * v
      sq = sq + p.chance * v * v * (1 + s * s)
    end
  end
  return math.sqrt(math.max(0, sq - mean * mean))
end

-- Estimated sales a day of one material (the whole AH), cached for 10 minutes
local salesCache = {}
local function soldPerDay(id, now)
  local c = salesCache[id]
  if c and now - c.t < 600 then return c.v end
  local it = FI:Realm().items[id]
  local v = it and FI.History.Stats(it, now).soldPerDay or nil
  salesCache[id] = { t = now, v = v }
  return v
end

---One material of a disenchant and how fast it sells (for the Deals tooltip)
---@class GT.DEMatSales
---@field id integer        the material as sold (the other essence size when converted)
---@field converted boolean?
---@field chance number
---@field share number      part of the disenchant's value, 0-1
---@field sold number?      sold a day on the AH (nil = not known yet)
---@field counts boolean    carries enough value (10%+) to set the pace

-- How many items' worth of materials the AH takes a day. For each material that
-- carries real value (10%+ of it): its sales a day / how many one item gives.
-- The slowest one sets the pace. nil while a material's sales aren't known.
-- Third value: every priced material and its sales, most valuable first.
---@param parts GT.DEPart[]
---@param value number  what D:Value returned
---@param now integer?
---@return number? itemsPerDay
---@return integer? slowest  the material that sets the pace
---@return GT.DEMatSales[] mats
function D:ItemsPerDay(parts, value, now)
  now = now or time()
  local pace, slowest, unknown = nil, nil, false
  local mats = {}
  for _, p in ipairs(parts) do
    if p.price and value > 0 then
      local id, per = p.id, p.chance * p.qty
      if p.sellAs then
        -- sold as the other essence size: 3 lesser make 1 greater
        per = greaterOf[p.id] == p.sellAs and per / 3 or per * 3
        id = p.sellAs
      end
      local share = p.chance * p.qty * p.price / value
      local sold = soldPerDay(id, now)
      local counts = share >= 0.10
      mats[#mats + 1] = { id = id, converted = p.sellAs ~= nil, chance = p.chance, share = share, sold = sold, counts = counts }
      if counts then
        if not sold then
          unknown = true
        elseif not pace or sold / per < pace then
          pace, slowest = sold / per, id
        end
      end
    end
  end
  table.sort(mats, function(a, b) return a.share > b.share end)
  if unknown then return nil, nil, mats end
  return pace, slowest, mats
end

-- Materials to watch so disenchant values stay priced (used by "/goon de watch")
function D:Materials()
  local list = {}
  for _, t in ipairs({ DUST, ESS, SHARD }) do for _, id in pairs(t) do list[#list + 1] = id end end
  list[#list + 1] = NEXUS
  return list
end

-- ---------------------------------------------------------------------------
-- Learning from the game. Disenchant is cast, then you click the item: we note
-- which item you clicked while a spell was waiting for a target, then see whether
-- the disenchant went through or the game said it can't be disenchanted, and what
-- landed in your bags right after.
-- ---------------------------------------------------------------------------
local DISENCHANT = 13262
local LOOT_WINDOW = 10 -- seconds after the cast that its materials can arrive
local target
local function noteTarget(bag, slot)
  if not (SpellIsTargeting and SpellIsTargeting()) then return end
  local id = C_Container and C_Container.GetContainerItemID and C_Container.GetContainerItemID(bag, slot)
    or (GetContainerItemID and GetContainerItemID(bag, slot))
  if id then target = { id = id, t = GetTime() } end
end
if hooksecurefunc then
  if C_Container then
    if C_Container.PickupContainerItem then hooksecurefunc(C_Container, "PickupContainerItem", noteTarget) end
    if C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", noteTarget) end
  end
  if PickupContainerItem then hooksecurefunc("PickupContainerItem", noteTarget) end
  if UseContainerItem then hooksecurefunc("UseContainerItem", noteTarget) end
end

local function isDisenchant(spellID)
  if spellID == DISENCHANT then return true end
  local name = GetSpellInfo and spellID and GetSpellInfo(spellID)
  return name ~= nil and name == GetSpellInfo(DISENCHANT)
end

function D:Learn(itemID, can)
  if not itemID or not FI.db then return end
  FI.db.deLearned = FI.db.deLearned or {}
  if FI.db.deLearned[itemID] == can then return end
  FI.db.deLearned[itemID] = can
  self:ForgetCache()
  FI:Fire("FI_DISENCHANT_LEARNED", itemID, can)
end

-- One disenchant's materials, added to its table row in FI.db.deYields
-- (account-wide: disenchanting works the same on every realm)
---@param key string  GT.DEBand.key
---@param got table<integer, integer>  material itemID -> quantity
function D:Record(key, got)
  if not FI.db or not next(got) then return end
  FI.db.deYields = FI.db.deYields or {}
  local row = FI.db.deYields[key] or { n = 0, out = {} }
  FI.db.deYields[key] = row
  row.n = row.n + 1
  for id, q in pairs(got) do
    local s = row.out[id] or { h = 0, q = 0 }
    row.out[id] = s
    s.h = s.h + 1
    s.q = s.q + q
  end
  self:ForgetCache()
end

local current -- the disenchant whose materials are arriving: { key, got, t }
local function finishCurrent()
  if current then D:Record(current.key, current.got) end
  current = nil
end

FI:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit ~= "player" or not isDisenchant(spellID) then return end
  finishCurrent()
  if target and GetTime() - target.t < 30 then
    D:Learn(target.id, true)
    local b = D:Band(target.id)
    if b then
      local mine = { key = b.key, got = {}, t = GetTime() }
      current = mine
      C_Timer.After(LOOT_WINDOW, function() if current == mine then finishCurrent() end end)
    end
  end
  target = nil
end)
FI:On("CHAT_MSG_LOOT", function(_, msg)
  if not current or GetTime() - current.t > LOOT_WINDOW then return end
  local id, n = FI.Ledger.LootFromChat(msg)
  if id and IS_MATERIAL[id] then current.got[id] = (current.got[id] or 0) + n end
end)
FI:On("UI_ERROR_MESSAGE", function(_, _, msg)
  local cant = _G.SPELL_FAILED_CANT_BE_DISENCHANTED or "Item cannot be disenchanted"
  if msg == cant and target and GetTime() - target.t < 5 then
    D:Learn(target.id, false)
    target = nil
  end
end)
