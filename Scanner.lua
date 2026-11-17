-- Goonberg Terminal: full Auction House scans
-- Uses C_AuctionHouse.ReplicateItems (modern AH: one full dump, Blizzard allows one
-- every 15 minutes per account). Falls back to the classic "getAll" query if the
-- client only has the old AH API.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Scanner
local S = { state = "idle" }
FI.Scanner = S

S.COOLDOWN = 15 * 60
local PER_FRAME = 1500
local H -- History, set on first use

function S:Mode()
  if C_AuctionHouse and C_AuctionHouse.ReplicateItems then return "replicate" end
  if QueryAuctionItems then return "legacy" end
end

function S:CooldownLeft()
  if self:Mode() == "legacy" and CanSendAuctionQuery then
    local _, canAll = CanSendAuctionQuery()
    if canAll then return 0 end
  end
  -- Blizzard's 15 minutes start when the scan is asked for, not when it arrives
  local last = math.max(FI.db and FI.db.lastFullScan or 0, FI.db and FI.db.lastScanRequest or 0)
  return math.max(0, last + self.COOLDOWN - time())
end

function S:Progress()
  if self.state ~= "processing" or not self.total or self.total == 0 then return nil end
  return (self.done or 0) / self.total
end

local function setState(state)
  S.state = state
  FI:Fire("FI_SCAN_STATE", state)
end

function S:Start(manual)
  if self.state ~= "idle" then
    if manual then FI:Print("A scan is already running.") end
    return
  end
  if not FI.ahOpen then
    if manual then FI:Print("Open the Auction House to scan.") end
    return
  end
  local mode = self:Mode()
  if not mode then
    return FI:Print("This client has no Auction House scan API Goonberg Terminal knows about.")
  end
  local left = self:CooldownLeft()
  if left > 0 then
    if manual then
      FI:Print("Next full scan in %s. Blizzard allows one every 15 minutes.", FI.Duration(left))
    end
    return
  end

  self.mode = mode
  self.requested = GetTime()
  setState("waiting")
  local ok, err
  if mode == "replicate" then
    FI.db.lastScanRequest = time()
    ok, err = pcall(C_AuctionHouse.ReplicateItems)
  else
    ok, err = pcall(QueryAuctionItems, "", nil, nil, 0, nil, nil, true, false, nil)
  end
  if not ok then
    setState("idle")
    return FI:Print("The Auction House refused the scan request (%s).", tostring(err))
  end
  local token = self.requested
  -- busy realms can take a few minutes to send everything
  C_Timer.After(180, function()
    if S.state == "waiting" and S.requested == token then
      setState("idle")
      FI:Print("The Auction House hasn't sent the scan yet. If it arrives while the AH is open it will still be read.")
    end
  end)
end

-- Reads one auction: count, buyout (total), itemID
local function readReplicate(i)
  local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
  return count, buyout, itemID
end
local function readLegacy(i)
  local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
  return count, buyout, itemID
end

local worker = CreateFrame("Frame")
worker:Hide()

local function stop(why)
  worker:Hide()
  S.acc = nil
  setState("idle")
  FI:Print("Scan stopped: %s. Try /goon scan again.", tostring(why))
end

local function finish()
  worker:Hide()
  H = H or FI.History
  -- the market of the auction house this scan was read at (not whatever is on screen now)
  local market = S.market or FI.ahMarket or "home"
  local realm = FI:Market(market)
  local now = time()
  local acc = S.acc
  S.acc = nil

  local prevPrices = {}
  for itemID, it in pairs(realm.items) do
    if it.mkt and it.seen == realm.lastScan then prevPrices[itemID] = it.mkt end
  end

  local items, auctions = 0, 0
  for itemID, e in pairs(acc) do
    -- e is a flat array: unit, count, unit, count...; sort it by unit price
    local pairsList = {}
    for i = 1, #e, 2 do pairsList[#pairsList + 1] = { e[i], e[i + 1] } end
    table.sort(pairsList, function(a, b) return a[1] < b[1] end)
    local flat, qty = {}, 0
    for i, p in ipairs(pairsList) do
      flat[i * 2 - 1] = p[1]
      flat[i * 2] = p[2]
      qty = qty + p[2]
    end
    H.Record(realm, itemID, now, H.MarketPrice(flat, qty), flat[1], qty, #pairsList, H.Depth(flat, 10))
    items = items + 1
    auctions = auctions + #pairsList
  end

  -- Items listed last scan and gone now: everything sold or expired.
  -- Skipped when this scan looks incomplete (far fewer items than last time),
  -- so a cut-off scan can't mark the whole AH as sold out.
  local lastCount = 0
  for _, it in pairs(realm.items) do
    if it.seen == realm.lastScan and (it.qty or 0) > 0 then lastCount = lastCount + 1 end
  end
  if lastCount < 200 or items >= lastCount * 0.5 then
    for itemID, it in pairs(realm.items) do
      if not acc[itemID] and it.seen == realm.lastScan and (it.qty or 0) > 0 then
        H.Record(realm, itemID, now, 0, nil, 0, 0, nil)
      end
    end
  else
    FI:Print("This scan only had %s of the %s items seen last time; items missing from it aren't counted as sold.",
      FI.Number(items), FI.Number(lastCount))
  end

  realm.lastScan = now
  realm.scans = (realm.scans or 0) + 1
  realm.scanDays = realm.scanDays or {}
  realm.scanDays[math.floor(now / 86400)] = true
  FI.db.lastFullScan = (S.mode == "replicate") and now or FI.db.lastFullScan
  H.UpdateIndex(realm, prevPrices, now)
  H.cache = nil

  S.lastFinished = now
  setState("idle")
  FI:Print("Scan done: %s auctions, %s items in %.1fs.", FI.Number(auctions), FI.Number(items), GetTime() - (S.requested or GetTime()))
  FI:Fire("FI_SCAN_DONE", now, nil, market)
end

local function step()
  local read = S.mode == "replicate" and readReplicate or readLegacy
  local acc = S.acc
  local last = math.min(S.total, S.done + PER_FRAME)
  local offset = S.mode == "replicate" and -1 or 0 -- replicate indexes are 0-based
  for n = S.done + 1, last do
    -- one auction the client can't read is skipped, not the whole scan
    local ok, count, buyout, itemID = pcall(read, n + offset)
    if ok and type(itemID) == "number" and count and count > 0 and buyout and buyout > 0 then
      local e = acc[itemID]
      if not e then e = {}; acc[itemID] = e end
      e[#e + 1] = math.floor(buyout / count + 0.5)
      e[#e + 1] = count
    end
  end
  S.done = last
  FI:Fire("FI_SCAN_PROGRESS", S.done, S.total)
  if S.done >= S.total then finish() end
end

worker:SetScript("OnUpdate", function()
  if not S.acc then worker:Hide(); return end
  local ok, err = pcall(step)
  if not ok then
    stop(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
  end
end)

local function begin(total)
  S.total = total or 0
  S.done = 0
  S.acc = {}
  S.market = FI.ahMarket or FI.market -- which auction house this scan belongs to
  setState("processing")
  if S.total == 0 then
    local ok, err = pcall(finish)
    if not ok then stop(err) end
  else
    worker:Show()
  end
end

FI:On("REPLICATE_ITEM_LIST_UPDATE", function()
  local total = C_AuctionHouse.GetNumReplicateItems() or 0
  -- an empty list is the AH still getting ready (a real AH always has auctions):
  -- keep waiting for the next update instead of recording "everything sold out"
  if total == 0 then return end
  if S.state == "waiting" and S.mode == "replicate" then
    begin(total)
  elseif S.state == "idle" and FI.ahOpen and time() - (FI.db.lastScanRequest or 0) < S.COOLDOWN
    and (FI.db.lastFullScan or 0) < (FI.db.lastScanRequest or 0) then
    -- our own scan, arriving after we stopped waiting for it
    S.mode = "replicate"
    S.requested = GetTime()
    FI:Print("The scan arrived, reading it now.")
    begin(total)
  elseif S.state == "idle" and FI.ahOpen and time() - (FI.db.lastFullScan or 0) > 600 then
    -- Another addon (e.g. Auctionator's Full Scan) asked for the full AH. Blizzard's
    -- 15-minute limit is shared, so read the same results instead of missing out.
    -- (Within 10 minutes of a scan we processed, these events are just the tail of it.)
    S.mode = "replicate"
    S.requested = GetTime()
    FI:Print("Reading the full scan another addon just requested.")
    begin(total)
  end
end)

FI:On("AUCTION_ITEM_LIST_UPDATE", function()
  if S.state == "waiting" and S.mode == "legacy" then
    -- With getAll, the "batch" is every auction on the AH
    local batch = GetNumAuctionItems("list")
    begin(batch)
  end
end)

FI:On("FI_AH_OPEN", function()
  if FI.settings.autoScan then
    -- Give the AH a moment to finish opening
    C_Timer.After(1, function() S:Start(false) end)
  end
end)

FI:On("FI_AH_CLOSED", function()
  if S.state == "waiting" then setState("idle") end
  -- Data already received is processed even if the AH closes, except the
  -- legacy API, which drops results on close.
  if S.state == "processing" and S.mode == "legacy" then
    worker:Hide()
    S.acc = nil
    setState("idle")
    FI:Print("Scan stopped because the Auction House closed.")
  end
end)

-- While the AH stays open, scan again as soon as Blizzard's 15-minute limit allows
local auto = CreateFrame("Frame")
auto.acc = 0
auto:SetScript("OnUpdate", function(self, e)
  self.acc = self.acc + e
  if self.acc < 5 then return end
  self.acc = 0
  if FI.ahOpen and FI.settings and FI.settings.autoScan and S.state == "idle" and S:CooldownLeft() == 0 then
    S:Start(false)
  end
end)
