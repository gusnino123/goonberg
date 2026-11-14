-- Goonberg Terminal: shared price history that ships with the addon.
-- Seed\Data.lua (built by tools/build_seed.py from players' saved data) holds daily
-- prices for the last 60 days. On login it's added to your own history (never over a
-- day you already have), so a brand-new install starts with charts and fair values.
local _, FI = ...
local SD = {}
FI.Seed = SD

local DAY = 86400
local BUDGET_MS = 6

local function n36(s) return s and tonumber(s, 36) end

local worker = CreateFrame("Frame")
worker:Hide()

local function done(job)
  worker:Hide()
  SD.job = nil
  local realm = FI:Realm()
  realm.seedBuilt = job.built
  FI.History.cache = nil
  _G.GoonbergSeed = nil -- free the memory, it's in your history now
  if job.points > 0 then
    FI:Print("Loaded %s days of shared price history for %s items (bundled with this version).",
      FI.Number(job.points), FI.Number(job.count))
    FI:Fire("FI_DATA_MERGED", "Goonberg")
  end
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
    for entry in job.items[id]:gmatch("[^;]+") do
      local d, p, q = entry:match("^(%w+),(%w+),(%w*)$")
      d, p, q = n36(d), n36(p), n36(q) or 0
      if d and p and p > 0 then points[#points + 1] = { (job.base + d) * DAY + 43200, p, q } end
    end
    local added = FI.History.Merge(realm, id, points)
    if added > 0 then job.points = job.points + added; job.count = job.count + 1 end
    if debugprofilestop() - start > BUDGET_MS then return end
  end
end)

function SD:Run(force)
  local seed = _G.GoonbergSeed
  if type(seed) ~= "table" or type(seed.realms) ~= "table" then return false end
  local realm = FI:Realm()
  local data = seed.realms[FI.realmKey]
  if not data then _G.GoonbergSeed = nil; return false end
  if realm.seedBuilt == seed.built and not force then _G.GoonbergSeed = nil; return false end
  local ids = {}
  for id in pairs(data.items) do ids[#ids + 1] = id end
  -- days with data count as scanned days (used to judge how rare an item is)
  realm.scanDays = realm.scanDays or {}
  for d in (data.days or ""):gmatch("%w+") do realm.scanDays[data.base + n36(d)] = true end
  self.job = { ids = ids, i = 0, items = data.items, base = data.base, built = seed.built, points = 0, count = 0 }
  worker:Show()
  return true
end

-- after the Auctionator import (8 s) so the two don't run at the same time
FI:On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  if not (isLogin or isReload) then return end
  C_Timer.After(12, function() SD:Run(false) end)
end)
