-- Goonberg Terminal: price history that ships with the addon.
--  * Market data: one load-on-demand addon per market (GoonbergData_US_PvP_Horde ...),
--    built daily from Blizzard's auction house API (tools/fetch_blizzard.py). Only
--    your own market's addon is loaded, and only when it's newer than last time.
--  * Seed\Data.lua: history built from players' saved data (tools/build_seed.py).
-- Either way the days are added to your own history (never over a day you already
-- have), a little each frame, and the data is then dropped from memory.
local _, FI = ...
local SD = {}
FI.Seed = SD

local DAY = 86400
local BUDGET_MS = 6
local REGIONS = { [1] = "US", [2] = "KR", [3] = "EU", [4] = "TW", [5] = "CN" }
-- longest names first, so "roleplaypvp" isn't read as "pvp"
local RULESETS = {
  { "roleplaypvp", "Roleplay PvP" }, { "rppvp", "Roleplay PvP" },
  { "roleplay", "Roleplay" }, { "rp", "Roleplay" },
  { "normal", "Normal" }, { "pve", "Normal" },
  { "pvp", "PvP" },
}

local function n36(s) return s and tonumber(s, 36) end
local function norm(s) return ((s or ""):lower():gsub("[^a-z]", "")) end
-- the addon API moved into C_AddOns in newer clients; look it up when used
local function api(name)
  local ns = _G.C_AddOns
  return (ns and ns[name]) or _G[name]
end

local function addonExists(name)
  local doesExist = _G.C_AddOns and _G.C_AddOns.DoesAddOnExist
  if doesExist then
    local ok, yes = pcall(doesExist, name)
    if ok then return yes end
  end
  local info = api("GetAddOnInfo")
  if not info then return false end
  local ok, n, _, _, _, reason = pcall(info, name)
  return ok and n ~= nil and reason ~= "MISSING"
end

local function rulesetFrom(text)
  local n = norm(text)
  if n == "" then return nil end
  for _, r in ipairs(RULESETS) do
    if n == r[1] then return r[2] end
  end
  for _, r in ipairs(RULESETS) do
    if #r[1] > 3 and n:find(r[1], 1, true) then return r[2] end
  end
end
SD.RulesetFrom = rulesetFrom

-- "US PvP - Horde", worked out from the client (or /goon market <ruleset>)
function SD:Market()
  local region = REGIONS[GetCurrentRegion and GetCurrentRegion() or 0] or "US"
  local ruleset = (FI.settings and FI.settings.market) or rulesetFrom(GetRealmName and GetRealmName())
  local faction = UnitFactionGroup("player")
  if not ruleset or (faction ~= "Alliance" and faction ~= "Horde") then return nil end
  return ("%s %s - %s"):format(region, ruleset, faction)
end

function SD.AddonName(market)
  local left, faction = market:match("^(.-) %- (%a+)$")
  local region, ruleset = left:match("^(%S+) (.+)$")
  return ("GoonbergData_%s_%s_%s"):format(region, (ruleset:gsub("[^%w]", "")), faction)
end

-- ---------------------------------------------------------------------------
-- Merging, a little each frame
-- ---------------------------------------------------------------------------
local worker = CreateFrame("Frame")
worker:Hide()
SD.queue = {}

local function start(job)
  job.ids, job.i, job.points, job.count = {}, 0, 0, 0
  for id in pairs(job.data.items) do job.ids[#job.ids + 1] = id end
  local realm = FI:Realm()
  realm.scanDays = realm.scanDays or {}
  for d in (job.data.days or ""):gmatch("%w+") do realm.scanDays[job.data.base + n36(d)] = true end
  SD.job = job
  worker:Show()
end

local function done(job)
  SD.job = nil
  local realm = FI:Realm()
  realm[job.field] = job.built
  FI.History.cache = nil
  if job.points > 0 then
    FI:Print("Added %s days of %s price history for %s items.", FI.Number(job.points), job.label, FI.Number(job.count))
    FI:Fire("FI_DATA_MERGED", "Goonberg")
  end
  local nextJob = table.remove(SD.queue, 1)
  if nextJob then start(nextJob) else worker:Hide() end
end

worker:SetScript("OnUpdate", function()
  local job = SD.job
  if not job then worker:Hide(); return end
  local realm = FI:Realm()
  local start = debugprofilestop()
  while true do
    job.i = job.i + 1
    local id = job.ids[job.i]
    if not id then return done(job) end
    local points = {}
    for entry in job.data.items[id]:gmatch("[^;]+") do
      local d, p, q = entry:match("^(%w+),(%w+),(%w*)$")
      d, p, q = n36(d), n36(p), n36(q) or 0
      if d and p and p > 0 then points[#points + 1] = { (job.data.base + d) * DAY + 43200, p, q } end
    end
    local added = FI.History.Merge(realm, id, points)
    if added > 0 then job.points = job.points + added; job.count = job.count + 1 end
    if debugprofilestop() - start > BUDGET_MS then return end
  end
end)

local function enqueue(job)
  if SD.job or SD.hold then SD.queue[#SD.queue + 1] = job else start(job) end
end

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------
local bundled -- Seed\Data.lua, captured at login (the market addon reuses the global name)

local function pick(seed, keys)
  if type(seed) ~= "table" or type(seed.realms) ~= "table" then return nil end
  for _, k in ipairs(keys) do
    if k and seed.realms[k] then return seed.realms[k] end
  end
end

-- Is the market addon there, and is it newer than what we already merged?
function SD:MarketStatus()
  local market = self:Market()
  if not market then return nil, "unknown" end
  local name = SD.AddonName(market)
  if not addonExists(name) then return market, "missing", name end
  local meta = api("GetAddOnMetadata")
  local built = tonumber(meta and meta(name, "X-Goonberg-Built") or "")
  local realm = FI:Realm()
  if built and realm.marketBuilt == built then return market, "current", name, built end
  return market, "new", name, built
end

function SD:Run(force)
  local realm = FI:Realm()
  local queued = false
  -- 1) bundled history from players' saved data
  local data = pick(bundled, { FI.realmKey, self:Market() })
  if data and (force or realm.seedBuilt ~= bundled.built) then
    enqueue({ data = data, built = bundled.built, field = "seedBuilt", label = "shared" })
    queued = true
  end
  bundled = nil
  -- 2) this market's Blizzard data
  local market, status, name, built = self:MarketStatus()
  if not market and not FI.settings.marketHint and UnitFactionGroup("player") ~= "Neutral" then
    FI.settings.marketHint = true
    FI:Print("To get daily Blizzard prices, tell Goonberg your ruleset once: /goon market normal, pvp, rp or rppvp.")
  end
  if status == "new" or (force and status == "current") then
    _G.GoonbergSeed = nil
    local load = api("LoadAddOn")
    local ok = load and pcall(load, name)
    local seed = _G.GoonbergSeed
    _G.GoonbergSeed = nil -- the data lives on in the job until it's merged
    local mdata = ok and pick(seed, { market })
    if mdata then
      enqueue({ data = mdata, built = seed.built or built, field = "marketBuilt", label = market })
      queued = true
    end
  end
  return queued
end

-- At login the data file is read while the loading screen is still up (reading a
-- few MB takes a moment); the merge waits until after the Auctionator import (8 s)
-- so the two don't run at the same time.
FI:On("PLAYER_LOGIN", function()
  bundled = _G.GoonbergSeed
  _G.GoonbergSeed = nil
  SD.hold = true
  SD:Run(false)
  C_Timer.After(12, function()
    SD.hold = false
    local job = table.remove(SD.queue, 1)
    if job and not SD.job then start(job) end
  end)
end)
