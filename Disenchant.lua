-- Goonberg Terminal: estimated disenchant value
-- Expected value of disenchanting a piece of gear: each possible result's chance x
-- average quantity x its AH market price. The game doesn't tell addons what an item
-- disenchants into, so this uses the Classic disenchant tables (item level, quality,
-- armor vs. weapon). Forever's custom gear may differ, so it's shown as an estimate.
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

-- Uncommon (green) ARMOR by item level: { maxLevel, dust, dustQty, essence, essQty, shard }
-- Dust 75%, essence 20%, shard 5% (weapons swap the dust and essence chances).
local GREEN = {
  { 15, DUST.strange, 1.5, ESS.lmagic, 1.5, nil },
  { 20, DUST.strange, 2.5, ESS.gmagic, 1.5, SHARD.sglim },
  { 25, DUST.strange, 5, ESS.lastral, 1.5, SHARD.sglim },
  { 30, DUST.soul, 1.5, ESS.gastral, 1.5, SHARD.lglim },
  { 35, DUST.soul, 3.5, ESS.lmystic, 1.5, SHARD.sglow },
  { 40, DUST.vision, 1.5, ESS.gmystic, 1.5, SHARD.lglow },
  { 45, DUST.vision, 3.5, ESS.lnether, 1.5, SHARD.srad },
  { 50, DUST.dream, 1.5, ESS.gnether, 1.5, SHARD.lrad },
  { 55, DUST.dream, 3.5, ESS.leternal, 1.5, SHARD.sbril },
  { 60, DUST.illusion, 1.5, ESS.geternal, 1.5, SHARD.lbril },
  { 65, DUST.illusion, 3.5, ESS.geternal, 2.5, SHARD.lbril },
}
-- Rare (blue): a shard, almost always one
local BLUE = {
  { 25, SHARD.sglim }, { 30, SHARD.lglim }, { 35, SHARD.sglow }, { 40, SHARD.lglow },
  { 45, SHARD.srad }, { 50, SHARD.lrad }, { 55, SHARD.sbril }, { 70, SHARD.lbril },
}

-- What an item can turn into: list of { itemID, chance, avgQty }, or nil.
-- These never change for an item, so they're worked out once and cached
-- (false = "can't be disenchanted"; items whose info isn't loaded yet aren't cached).
local resultsCache = {}
function D:Results(itemID)
  local c = resultsCache[itemID]
  if c ~= nil then return c or nil end
  local r, known = self:ComputeResults(itemID)
  if known then resultsCache[itemID] = r or false end
  return r
end

function D:ComputeResults(itemID)
  local _, _, _, _, _, classID = FI.GetItemInfoInstant(itemID)
  if classID ~= 2 and classID ~= 4 then return nil, true end -- not gear: never
  local _, _, quality, ilvl = FI.GetItemInfo(itemID)
  if not quality or not ilvl then return nil, false end -- not loaded yet: ask again later
  if quality == 2 then
    for _, row in ipairs(GREEN) do
      if ilvl <= row[1] then
        local weapon = classID == 2
        local dustChance, essChance = weapon and 0.20 or 0.75, weapon and 0.75 or 0.20
        local out = { { row[2], dustChance, row[3] }, { row[4], essChance, row[5] } }
        if row[6] then out[#out + 1] = { row[6], 0.05, 1 } end
        return out, true
      end
    end
  elseif quality == 3 then
    for _, row in ipairs(BLUE) do
      if ilvl <= row[1] then
        if ilvl >= 56 then return { { row[2], 0.995, 1 }, { NEXUS, 0.005, 1 } }, true end
        return { { row[2], 1, 1 } }, true
      end
    end
  elseif quality == 4 and ilvl >= 51 then
    return { { NEXUS, 1, 1.5 } }, true
  end
  return nil, true
end

-- Expected value in copper; complete = every possible result has a price
function D:Value(itemID)
  local results = self:Results(itemID)
  if not results then return nil end
  local realm = FI:Realm()
  local value, complete = 0, true
  local parts = {}
  for _, r in ipairs(results) do
    local it = realm.items[r[1]]
    local price = it and it.mkt
    if price then
      value = value + r[2] * r[3] * price
    else
      complete = false
    end
    parts[#parts + 1] = { id = r[1], chance = r[2], qty = r[3], price = price }
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
