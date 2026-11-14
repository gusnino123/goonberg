-- Goonberg Terminal: imports price history from Auctionator, and picks up
-- Auctionator's full scans as they happen.
-- Auctionator keeps, per item and per day, the lowest price it saw and how many were
-- listed. Goonberg adds those days to its own history (never twice, never over a
-- day it scanned itself), so charts start with everything Auctionator remembers.
local _, FI = ...
local I = {}
FI.Import = I
local PER_FRAME = 250

function I:Available()
  local A = _G.Auctionator
  return A and A.Database and A.Database.db and A.Database.GetPriceHistory and A.Constants and A.Constants.SCAN_DAY_0
end

local worker = CreateFrame("Frame")
worker:Hide()

function I:Run(manual)
  if self.running then return end
  if not self:Available() then
    if manual then FI:Print("Auctionator isn't loaded, so there's nothing to import.") end
    return
  end
  local A = _G.Auctionator
  local keys = {}
  for key in pairs(A.Database.db) do
    -- plain item IDs only (gear with suffixes and battle pets use other keys)
    if type(key) == "string" and key:match("^%d+$") then keys[#keys + 1] = key end
  end
  self.keys, self.i, self.items, self.points = keys, 0, 0, 0
  self.day0 = A.Constants.SCAN_DAY_0
  self.running = true
  if manual then FI:Print("Importing Auctionator's price history for %s items...", FI.Number(#keys)) end
  self.manual = manual
  worker:Show()
end

worker:SetScript("OnUpdate", function(self)
  local A = _G.Auctionator
  local realm = FI:Realm()
  local last = math.min(#I.keys, I.i + PER_FRAME)
  for n = I.i + 1, last do
    local key = I.keys[n]
    local ok, hist = pcall(A.Database.GetPriceHistory, A.Database, key)
    if ok and type(hist) == "table" and #hist > 0 then
      local points = {}
      for _, d in ipairs(hist) do
        local day = tonumber(d.rawDay)
        local price = d.minSeen or d.maxSeen
        if day and price and price > 0 then
          -- midday, so the point lands inside the right calendar day
          points[#points + 1] = { I.day0 + day * 86400 + 43200, price, d.available }
        end
      end
      table.sort(points, function(a, b) return a[1] < b[1] end)
      local added = FI.History.Merge(realm, tonumber(key), points)
      -- Auctionator scanned on these days too (used to judge how rare items are)
      realm.scanDays = realm.scanDays or {}
      for _, pt in ipairs(points) do realm.scanDays[math.floor(pt[1] / 86400)] = true end
      if added > 0 then
        I.items = I.items + 1
        I.points = I.points + added
      end
    end
  end
  I.i = last
  if I.i >= #I.keys then
    self:Hide()
    I.running = false
    FI.db.lastImport = time()
    FI.History.cache = nil
    if I.points > 0 or I.manual then
      FI:Print("Imported %s days of price history for %s items from Auctionator.", FI.Number(I.points), FI.Number(I.items))
    end
    FI:Fire("FI_DATA_MERGED", "Auctionator")
  end
end)

-- Every login: catch up on whatever Auctionator recorded since last time
FI:On("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
  if not (isLogin or isReload) then return end
  if FI.settings.importAuctionator == false then return end
  C_Timer.After(8, function() I:Run(false) end)
end)
