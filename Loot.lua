-- Goonberg Terminal: dungeon loot worth selling.
--
-- Loot tables ship with the addon (Loot\Data.lua: Dungeon Codex's WoW Forever data,
-- with drop chances), so the tab is full from the start. On top of that Goonberg keeps
-- learning: every boss corpse you loot in a dungeon is one kill and what it dropped is
-- counted; guildmates' kills arrive through guild sync, each kill counted once however
-- many people looted it. A listed drop chance counts like 20 kills, so real kills move
-- it more and more. The game's Adventure Guide adds anything the tables miss.
--
-- Only what can be sold on the AH is shown: Bind on Equip and unbound items
-- (recipes, materials). Bind on Pickup and quest items are never listed.
local _, FI = ...
local LT = {}
FI.Loot = LT

local KEEP_SEEN = 3 * 86400 -- corpse GUIDs remembered for de-duplication
local BOSS_WINDOW = 300     -- a boss corpse is looted within 5 minutes of the kill
local MIN_QUALITY = 2       -- green and up

-- ---------------------------------------------------------------------------
-- Bundled loot tables
-- ---------------------------------------------------------------------------
local PRIOR = 20 -- a listed drop chance weighs as much as 20 kills
LT.bosses = {}   -- creature ID -> source
LT.sources = {}  -- every boss, rare spawn and chest: { key, name, instance, items, listed = { [item] = 0..1 }, rare, object }
LT.trash = {}    -- dungeon trash tables: { instance, items, listed }
LT.dungeonInfo = {} -- dungeon name -> { min, max, order } (level range, place in the list)
LT.PRIOR = PRIOR

function LT:IndexBundled()
  local data = FI.LootData
  if not data then return end
  wipe(self.bosses)
  wipe(self.sources)
  wipe(self.trash)
  wipe(self.dungeonInfo)
  -- wings (Scarlet Monastery, Dire Maul) share one instance: keep their own names
  local perInstance = {}
  for _, dg in ipairs(data.dungeons) do perInstance[dg.instance] = (perInstance[dg.instance] or 0) + 1 end
  for idx, dg in ipairs(data.dungeons) do
    local name = dg.name
    if perInstance[dg.instance] == 1 and GetRealZoneText then
      local real = GetRealZoneText(dg.instance) -- the client's own (localized) name
      if type(real) == "string" and real ~= "" then name = real end
    end
    dg.display = name
    self.dungeonInfo[name] = { min = dg.levels and dg.levels[1], max = dg.levels and dg.levels[2], order = idx }
    for _, b in ipairs(dg.bosses) do
      local npc, bossName, items, drops, rare, object = b[1], b[2], b[3], b[4], b[5], b[6]
      local listed = {}
      for id, pct in pairs(drops or {}) do listed[id] = pct / 100 end
      local src = { key = npc > 0 and ("n" .. npc) or ("x" .. dg.key .. ":" .. bossName), npc = npc > 0 and npc or nil,
        name = bossName, instance = name, levels = dg.levels, items = items, listed = listed,
        rare = rare and true or false, object = object and true or false }
      self.sources[#self.sources + 1] = src
      if src.npc then self.bosses[npc] = src end
    end
    if dg.trash then
      local listed = {}
      for id, pct in pairs(dg.trash[2] or {}) do listed[id] = pct / 100 end
      self.trash[#self.trash + 1] = { instance = name, items = dg.trash[1], listed = listed }
    end
  end
  self.cache = nil
end

local function db()
  local d = FI.db.loot
  if not d then
    d = { enc = {}, trash = {}, seen = {}, bossNpc = {} }
    FI.db.loot = d
  end
  d.enc, d.trash, d.seen, d.bossNpc = d.enc or {}, d.trash or {}, d.seen or {}, d.bossNpc or {}
  return d
end
LT.DB = db

local function npcFromGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, npc = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(npc)
end
LT.NpcFromGUID = npcFromGUID

local function instanceName()
  local name, kind = GetInstanceInfo()
  if kind ~= "party" and kind ~= "raid" then return nil end
  return name
end

local function itemFromLink(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- ---------------------------------------------------------------------------
-- Recording
-- ---------------------------------------------------------------------------
-- Adds one looted corpse. `items` is a list of item IDs (green and up).
-- Returns true when it was new (not already counted, by us or a guildmate).
function LT:Record(guid, instance, bossKey, bossName, items, t)
  local d = db()
  if not guid or d.seen[guid] then return false end
  t = t or time()
  d.seen[guid] = t
  if bossKey then
    local e = d.enc[bossKey]
    if not e then
      e = { n = bossName, i = instance, k = 0, d = {} }
      d.enc[bossKey] = e
    end
    e.n, e.i = bossName or e.n, instance or e.i
    e.k = e.k + 1
    e.last = t
    for _, id in ipairs(items) do e.d[id] = (e.d[id] or 0) + 1 end
  elseif instance then
    local tr = d.trash[instance]
    if not tr then tr = { k = 0, d = {} }; d.trash[instance] = tr end
    tr.k = tr.k + 1
    for _, id in ipairs(items) do tr.d[id] = (tr.d[id] or 0) + 1 end
  end
  self.cache = nil
  FI:Debounce("lootChanged", 1, function() FI:Fire("FI_LOOT_CHANGED") end)
  return true
end

-- the boss we just killed (ENCOUNTER_END) waits for its corpse to be looted
LT.pending = nil

FI:On("ENCOUNTER_END", function(_, encounterID, name, _, _, success)
  if success ~= 1 and success ~= true then return end
  local inst = instanceName()
  if not inst then return end
  LT.pending = { key = "e" .. tostring(encounterID), name = name, instance = inst, t = time() }
end)

-- boss frames during a fight name the boss's creature too (when there's no encounter event)
FI:On("INSTANCE_ENCOUNTER_ENGAGE_UNIT", function()
  local inst = instanceName()
  if not inst then return end
  local d = db()
  for i = 1, 5 do
    local unit = "boss" .. i
    if UnitExists and UnitExists(unit) then
      local npc = npcFromGUID(UnitGUID(unit))
      if npc and not d.bossNpc[npc] then
        d.bossNpc[npc] = { key = "n" .. npc, name = UnitName(unit), instance = inst }
      end
    end
  end
end)

local function readLoot()
  local inst = instanceName()
  if not inst or not GetNumLootItems then return end
  local d = db()
  local byCorpse = {}
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink and GetLootSlotLink(slot)
    local id = itemFromLink(link)
    local quality = id and select(3, FI.GetItemInfo(id))
    if not quality and GetLootSlotInfo then quality = select(5, GetLootSlotInfo(slot)) end
    local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
    if guid and npcFromGUID(guid) then
      byCorpse[guid] = byCorpse[guid] or {}
      if id and (quality or 0) >= MIN_QUALITY then table.insert(byCorpse[guid], { id, quality or 0 }) end
    end
  end
  local now = time()
  for guid, list in pairs(byCorpse) do
    if not d.seen[guid] then
      local npc = npcFromGUID(guid)
      local bundled = LT.bosses[npc]
      local boss = bundled and { key = bundled.key, name = bundled.name, instance = inst } or d.bossNpc[npc]
      local p = nil
      if not bundled then p = LT.pending end
      if bundled and LT.pending and LT.pending.instance == inst then LT.pending = nil end
      -- first loot after a kill in the same dungeon with a blue or better: the boss
      -- (in Forever every boss drops a guaranteed blue)
      local best = 0
      for _, it in ipairs(list) do best = math.max(best, it[2]) end
      if p and p.instance == inst and now - p.t <= BOSS_WINDOW and best >= 3
        and (not boss or boss.key:sub(1, 1) == "n") then
        -- the encounter's ID beats the boss-frame guess
        boss = { key = p.key, name = p.name, instance = inst }
        d.bossNpc[npc] = boss
        LT.pending = nil
      elseif boss and p and p.key == boss.key then
        LT.pending = nil
      end
      local items = {}
      for _, it in ipairs(list) do items[#items + 1] = it[1] end
      if LT:Record(guid, inst, boss and boss.key, boss and boss.name, items, now) and boss and FI.Sync and FI.Sync.ShareKill then
        FI.Sync:ShareKill(guid, inst, boss.key, boss.name, items)
      end
    end
  end
end

FI:On("LOOT_OPENED", function() readLoot() end)
FI:On("LOOT_READY", function() readLoot() end)

-- forget old corpse IDs at login
FI:On("PLAYER_LOGIN", function()
  LT:IndexBundled()
  local d = db()
  local now = time()
  for guid, t in pairs(d.seen) do
    if now - t > KEEP_SEEN then d.seen[guid] = nil end
  end
  C_Timer.After(25, function() LT:ImportJournal() end)
end)

-- ---------------------------------------------------------------------------
-- Adventure Guide: dungeons, bosses and (if the game lists it) their loot
-- ---------------------------------------------------------------------------
function LT:ImportJournal()
  if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then return false end
  local d = db()
  local journal = { built = time(), dungeons = {} }
  local ok = pcall(function()
    for tier = 1, EJ_GetNumTiers() do
      EJ_SelectTier(tier)
      for _, raid in ipairs({ false, true }) do
        local i = 1
        while true do
          local instID, instName = EJ_GetInstanceByIndex(i, raid)
          if not instID then break end
          local inst = { name = instName, raid = raid, bosses = {} }
          if EJ_SelectInstance then EJ_SelectInstance(instID) end
          local j = 1
          while true do
            local bossName, _, encID, _, _, _, dungeonEncID = EJ_GetEncounterInfoByIndex(j, instID)
            if not bossName then break end
            local boss = { name = bossName, key = "e" .. tostring(dungeonEncID or encID), items = {} }
            if EJ_SelectEncounter and EJ_GetNumLoot then
              EJ_SelectEncounter(encID)
              for k = 1, EJ_GetNumLoot() do
                local info = C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex and C_EncounterJournal.GetLootInfoByIndex(k)
                local itemID = type(info) == "table" and info.itemID or (EJ_GetLootInfoByIndex and select(1, EJ_GetLootInfoByIndex(k)))
                if itemID then boss.items[#boss.items + 1] = itemID end
              end
            end
            inst.bosses[#inst.bosses + 1] = boss
            j = j + 1
          end
          if #inst.bosses > 0 then journal.dungeons[#journal.dungeons + 1] = inst end
          i = i + 1
        end
      end
    end
  end)
  if ok and #journal.dungeons > 0 then
    d.journal = journal
    self.cache = nil
    FI:Fire("FI_LOOT_CHANGED")
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- What it's all worth
-- ---------------------------------------------------------------------------
-- bindType: 0 none, 1 on pickup, 2 on equip, 3 on use, 4 quest
local function itemInfo(id)
  local name, _, quality, _, reqLevel, _, _, _, equipLoc, _, vendor, classID, _, bindType = FI.GetItemInfo(id)
  if not name then
    FI:ItemName(id) -- asks the game to load it; FI_ITEM_LOADED refreshes the tab
    return nil
  end
  return {
    name = name, quality = quality or 1, req = reqLevel or 0, equipLoc = equipLoc or "",
    vendor = vendor or 0, classID = classID, bind = bindType or 0,
  }
end
LT.ItemInfo = itemInfo

local function sellable(info)
  return info and info.bind ~= 1 and info.bind ~= 4
end
LT.Sellable = sellable

local function isGear(info)
  return info.equipLoc ~= "" and info.equipLoc ~= "INVTYPE_NON_EQUIP" and info.equipLoc ~= "INVTYPE_BAG"
    and info.equipLoc ~= "INVTYPE_AMMO" and info.equipLoc ~= "INVTYPE_QUIVER"
end

-- twink brackets: 10-19, 20-29, 30-39, 40-49 (the classic battleground brackets)
local function bracket(req)
  if req < 10 or req > 49 then return nil end
  return math.floor(req / 10) * 10 + 9
end
LT.Bracket = bracket

local function priceOf(id)
  local it = FI:Realm().items[id]
  return it and it.mkt, it
end

-- Rows: one per item and where it drops. Cached until loot or prices change.
function LT:Rows()
  local realm = FI:Realm()
  if self.cache and self.cacheScan == realm.lastScan then return self.cache end
  local d = db()
  local rows, pending = {}, 0
  local function add(id, src)
    local info = itemInfo(id)
    if not info then pending = pending + 1; return end
    if not sellable(info) then return end
    local price, it = priceOf(id)
    local r = {
      id = id, name = info.name, quality = info.quality, req = info.req, bind = info.bind,
      gear = isGear(info), bracket = isGear(info) and info.bind == 2 and bracket(info.req) or nil,
      boss = src.boss, instance = src.instance, trash = src.trash,
      kills = src.kills or 0, drops = src.drops or 0, price = price,
      onAH = it and it.qty or 0, listedChance = src.listed, rareSpawn = src.rareSpawn, object = src.object,
    }
    if r.trash and r.listedChance then
      r.chance = r.listedChance -- per trash mob
      if price then r.perKill = r.chance * price end
    end
    if not r.trash then
      if r.listedChance then
        r.chance = (r.listedChance * PRIOR + r.drops) / (PRIOR + r.kills)
      elseif r.kills > 0 then
        r.chance = r.drops / r.kills
      end
      if r.chance and price then r.perKill = r.chance * price end
    end
    rows[#rows + 1] = r
  end
  local known = {}
  -- Adventure Guide items join the bundled boss of the same name
  local guideItems = {}
  if d.journal then
    for _, inst in ipairs(d.journal.dungeons) do
      for _, b in ipairs(inst.bosses) do guideItems[(b.name or ""):lower()] = b.items end
    end
  end
  -- kills recorded under another key for the same boss (0.18.0 keyed by encounter)
  local byName = {}
  for key, e in pairs(d.enc) do
    if e.n then
      local n = e.n:lower()
      byName[n] = byName[n] or {}
      table.insert(byName[n], key)
    end
  end
  for _, b in ipairs(self.sources) do
    local e = d.enc[b.key]
    local others = byName[b.name:lower()]
    if others and (#others > 1 or others[1] ~= b.key) then
      local merged = { k = 0, d = {} }
      for _, key in ipairs(others) do
        local x = d.enc[key]
        merged.k = merged.k + x.k
        for id, n in pairs(x.d) do merged.d[id] = (merged.d[id] or 0) + n end
      end
      e = merged
    end
    local items, seen = {}, {}
    local function push(id) if not seen[id] then seen[id] = true; items[#items + 1] = id end end
    for _, id in ipairs(b.items) do push(id) end
    if e then for id in pairs(e.d) do push(id) end end
    for _, id in ipairs(guideItems[b.name:lower()] or {}) do push(id) end
    for _, id in ipairs(items) do
      add(id, { boss = b.name, instance = b.instance, kills = e and e.k or 0, drops = e and e.d[id] or 0,
        listed = b.listed[id], rareSpawn = b.rare, object = b.object })
    end
    known[b.key] = true
    known["name:" .. b.name:lower()] = true
  end
  for key, e in pairs(d.enc) do
    if not known[key] and not known["name:" .. (e.n or ""):lower()] then
      for id, n in pairs(e.d) do
        add(id, { boss = e.n, instance = e.i, kills = e.k, drops = n })
        known[key .. ":" .. id] = true
      end
    end
  end
  local bundledTrash = {}
  for _, t in ipairs(self.trash) do
    local rec = d.trash[t.instance]
    bundledTrash[t.instance] = {}
    for _, id in ipairs(t.items) do
      bundledTrash[t.instance][id] = true
      add(id, { boss = "Trash", instance = t.instance, trash = true, kills = rec and rec.k or 0,
        drops = rec and rec.d[id] or 0, listed = t.listed[id] })
    end
  end
  for inst, tr in pairs(d.trash) do
    for id, n in pairs(tr.d) do
      if not (bundledTrash[inst] and bundledTrash[inst][id]) then
        add(id, { boss = "Trash", instance = inst, trash = true, kills = tr.k, drops = n })
      end
    end
  end
  -- Adventure Guide loot not seen drop yet
  if d.journal then
    for _, inst in ipairs(d.journal.dungeons) do
      for _, b in ipairs(inst.bosses) do
        local e = d.enc[b.key]
        for _, id in ipairs(known["name:" .. (b.name or ""):lower()] and {} or b.items) do
          if not known[b.key .. ":" .. id] then
            add(id, { boss = b.name, instance = inst.name, kills = e and e.k or 0, drops = 0 })
          end
        end
      end
    end
  end

  -- What counts as worth something. Twink gear: Bind on Equip gear for a level
  -- bracket that sells for real money there, either over the bracket's floor below
  -- or in the top quarter of what drops for that bracket (and 1g+). Rare drops: 5% or
  -- less over 20+ kills and 5g+, or any epic with an AH price.
  local byBracket = {}
  for _, r in ipairs(rows) do
    if r.bracket and r.price then
      byBracket[r.bracket] = byBracket[r.bracket] or {}
      table.insert(byBracket[r.bracket], r.price)
    end
  end
  local cut = {}
  for b, list in pairs(byBracket) do
    table.sort(list)
    cut[b] = list[math.max(1, math.ceil(#list * 0.75))]
  end
  local FLOOR = { [19] = 50000, [29] = 100000, [39] = 150000, [49] = 250000 }
  for _, r in ipairs(rows) do
    r.twink = r.bracket and r.price and (r.price >= FLOOR[r.bracket]
      or (#(byBracket[r.bracket] or {}) >= 4 and r.price >= math.max(10000, cut[r.bracket] or 0))) or false
    r.rare = (r.chance and (r.kills >= 20 or r.listedChance) and r.chance <= 0.05 and (r.price or 0) >= 50000)
      or (r.quality >= 4 and (r.price or 0) > 0) or false
  end
  self.cache, self.cacheScan, self.pendingItems = rows, realm.lastScan, pending
  return rows
end

-- Dungeons: gold a full clear is worth on average (sellable boss drops only)
function LT:Dungeons()
  local rows = self:Rows()
  local by = {}
  for _, r in ipairs(rows) do
    if r.instance then
      local dg = by[r.instance]
      if not dg then
        local info = self.dungeonInfo[r.instance] or {}
        dg = { name = r.instance, bosses = {}, perClear = 0, items = 0, kills = 0,
          minLevel = info.min, maxLevel = info.max, order = info.order }
        by[r.instance] = dg
      end
      dg.items = dg.items + 1
      if not r.trash then dg.bosses[r.boss] = math.max(dg.bosses[r.boss] or 0, r.kills) end
      -- per clear: bosses and chests (once a run); trash chances are per mob, so not here
      if r.perKill and not r.trash then dg.perClear = dg.perClear + r.perKill end
      if r.price and (not dg.best or r.price > dg.best.price) then dg.best = r end
    end
  end
  local list = {}
  for _, dg in pairs(by) do
    dg.bossCount = 0
    -- runs: the most kills of any of its bosses (the last bosses get skipped sometimes)
    for _, k in pairs(dg.bosses) do dg.bossCount = dg.bossCount + 1; dg.kills = math.max(dg.kills, k) end
    list[#list + 1] = dg
  end
  return list
end

FI:On("FI_SCAN_DONE", function() LT.cache = nil end)
FI:On("FI_DATA_MERGED", function() LT.cache = nil end)
FI:On("FI_ITEM_LOADED", function()
  if LT.pendingItems and LT.pendingItems > 0 then
    LT.cache = nil
    FI:Debounce("lootItems", 0.5, function() FI:Fire("FI_LOOT_CHANGED") end)
  end
end)
