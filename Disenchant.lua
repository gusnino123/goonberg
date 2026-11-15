-- Goonberg Terminal: estimated disenchant value
-- Expected value of disenchanting a piece of gear: each possible result's chance x
-- average quantity x what that material sells for. The game doesn't tell addons what
-- an item disenchants into, so this follows the WoW Forever disenchanting table:
-- bands by the item's REQUIRED level (the "Requires Level" line), not its item level.
-- Source: wow-professions.com/forever/disenchanting-guide (checked November 2026).
local _, FI = ...
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
-- Uncommon chances: armor 75% dust / 20% essence / 5% shard; weapons swap dust and
-- essence. The guide gives the shard as 3-5%, so 5% is the generous end.
local MAIN, SIDE, SHARD_CHANCE = 0.75, 0.20, 0.05
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

-- What an item can turn into: list of { itemID, chance, avgQty }, or nil.
-- These never change for an item, so they're worked out once and cached
-- (false = "can't be disenchanted"; items whose info isn't loaded yet aren't cached).
local resultsCache = {}
function D:ForgetCache() resultsCache = {} end
function D:Results(itemID)
  local c = resultsCache[itemID]
  if c ~= nil then return c or nil end
  local r, known = self:ComputeResults(itemID)
  if known then resultsCache[itemID] = r or false end
  return r
end

function D:ComputeResults(itemID)
  if not self:CanDisenchant(itemID) then return nil, true end
  local _, _, _, equipLoc, _, classID = FI.GetItemInfoInstant(itemID)
  if classID ~= 2 and classID ~= 4 then return nil, true end -- not gear: never
  if equipLoc and NOT_DISENCHANTABLE[equipLoc] then return nil, true end
  local _, _, quality, ilvl, reqLevel = FI.GetItemInfo(itemID)
  if not quality then return nil, false end -- not loaded yet: ask again later
  -- The table uses the required level. A few items have none; item level runs
  -- about 5 above required level, so use that as the stand-in.
  local level = (reqLevel and reqLevel > 0) and reqLevel or math.max(1, (ilvl or 1) - 5)

  if quality == 2 then
    local row = band(GREEN, level)
    local weapon = classID == 2
    local dust, ess = weapon and SIDE or MAIN, weapon and MAIN or SIDE
    if not row[6] then
      -- no shard at this level: dust and essence share all the chances
      local total = dust + ess
      return { { row[2], dust / total, row[3] }, { row[4], ess / total, row[5] } }, true
    end
    return { { row[2], dust, row[3] }, { row[4], ess, row[5] }, { row[6], SHARD_CHANCE, 1 } }, true
  elseif quality == 3 then
    local shard = band(SHARD_BY_LEVEL, level)[2]
    if level >= 51 then return { { shard, 1 - NEXUS_FROM_BLUE, 1 }, { NEXUS, NEXUS_FROM_BLUE, 1 } }, true end
    return { { shard, 1, 1 } }, true
  elseif quality == 4 then
    -- "Level 50 and below always gives a shard; high-level epics always give a crystal."
    -- The guide doesn't give quantities: 1 shard, and 1-2 crystals at 56+, are estimates.
    if level <= 50 then return { { band(SHARD_BY_LEVEL, level)[2], 1, 1 } }, true end
    return { { NEXUS, 1, level >= 56 and 1.5 or 1 } }, true
  end
  return nil, true
end

-- What one unit of a material sells for: the lower of its market price and the
-- cheapest listing now (what you'd have to match), only if seen in the last 7 days.
-- Essences take the better of selling as-is or converting (3 lesser = 1 greater).
function D:MaterialPrice(id)
  local own = FI.Crafting:SellPrice(id)
  local best = own
  if greaterOf[id] then
    local g = FI.Crafting:SellPrice(greaterOf[id])
    if g and (not best or g / 3 > best) then best = g / 3 end
  elseif lesserOf[id] then
    local l = FI.Crafting:SellPrice(lesserOf[id])
    if l and (not best or l * 3 > best) then best = l * 3 end
  end
  return best, best and own and best > own
end

-- Expected value in copper (before the AH's cut on the materials);
-- complete = every possible result has a price. parts lists each result.
function D:Value(itemID)
  local results = self:Results(itemID)
  if not results then return nil end
  local value, complete = 0, true
  local parts = {}
  for _, r in ipairs(results) do
    local price, converted = self:MaterialPrice(r[1])
    if price then
      value = value + r[2] * r[3] * price
    else
      complete = false
    end
    parts[#parts + 1] = { id = r[1], chance = r[2], qty = r[3], price = price, converted = converted }
  end
  if value == 0 and not complete then return nil, false, parts end
  return value, complete, parts
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
-- the disenchant went through or the game said it can't be disenchanted.
-- ---------------------------------------------------------------------------
local DISENCHANT = 13262
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

function D:Learn(itemID, can)
  if not itemID or not FI.db then return end
  FI.db.deLearned = FI.db.deLearned or {}
  if FI.db.deLearned[itemID] == can then return end
  FI.db.deLearned[itemID] = can
  self:ForgetCache()
  FI:Fire("FI_DISENCHANT_LEARNED", itemID, can)
end

FI:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
  if unit ~= "player" or spellID ~= DISENCHANT then return end
  if target and GetTime() - target.t < 30 then D:Learn(target.id, true) end
  target = nil
end)
FI:On("UI_ERROR_MESSAGE", function(_, _, msg)
  local cant = _G.SPELL_FAILED_CANT_BE_DISENCHANTED or "Item cannot be disenchanted"
  if msg == cant and target and GetTime() - target.t < 5 then
    D:Learn(target.id, false)
    target = nil
  end
end)
