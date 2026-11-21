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
  S.acc, S.fin = nil, nil
  setState("idle")
  FI:Print("Scan stopped: %s. Try /goon scan again.", tostring(why))
end

-- Reading and saving a scan both work in slices of at most BUDGET_MS per frame. A
-- big AH is tens of thousands of auctions and thousands of items: done in one go,
-- that froze the game for a moment at the end of every scan.
local BUDGET_MS = 8
local clock = debugprofilestop

-- After the last auction is read: one quick pass to learn what the last scan had
-- listed (and which of those are missing now), then the slices below.
local function startFinish()
  H = H or FI.History
  -- the market of the auction house this scan was read at (not whatever is on screen now)
  local market = S.market or FI.ahMarket or "home"
  local realm = FI:Market(market)
  local acc = S.acc
  S.acc = nil
  local job = { realm = realm, market = market, now = time(), lastScan = realm.lastScan, acc = acc,
    ids = {}, gone = {}, prev = {}, i = 0, auctions = 0, phase = "record" }
  local lastCount = 0
  for itemID, it in pairs(realm.items) do
    if it.seen == job.lastScan and (it.qty or 0) > 0 then
      lastCount = lastCount + 1
      if not acc[itemID] then job.gone[#job.gone + 1] = itemID end
    end
  end
  job.lastCount = lastCount
  for itemID in pairs(acc) do job.ids[#job.ids + 1] = itemID end
  S.fin = job
end

-- One item's listings: sorted by unit price, then into the history. Sorting their
-- positions avoids a table per auction (the listings are a flat unit, count array).
local sortList
local function byPrice(a, b) return sortList[a] < sortList[b] end
local function recordItem(job, itemID)
  local e = job.acc[itemID]
  local k = #e / 2
  local flat = e
  if k > 1 then
    local order = {}
    for i = 1, k do order[i] = i * 2 - 1 end
    sortList = e
    table.sort(order, byPrice)
    sortList = nil
    flat = {}
    for i = 1, k do
      local pos = order[i]
      flat[i * 2 - 1], flat[i * 2] = e[pos], e[pos + 1]
    end
  end
  local qty = 0
  for i = 2, #flat, 2 do qty = qty + flat[i] end
  -- its price in the previous scan, for the Goonberg Index
  local it = job.realm.items[itemID]
  if it and it.mkt and it.seen == job.lastScan then job.prev[itemID] = it.mkt end
  H.Record(job.realm, itemID, job.now, H.MarketPrice(flat, qty), flat[1], qty, k, H.Depth(flat, 10))
  job.auctions = job.auctions + k
end

local function finishStep()
  local job = S.fin
  local stopAt = FI:WorkUntil(BUDGET_MS)
  local realm = job.realm
  if job.phase == "record" then
    while job.i < #job.ids do
      job.i = job.i + 1
      recordItem(job, job.ids[job.i])
      if job.i % 25 == 0 and clock() > stopAt then return end
    end
    -- Items listed last scan and gone now: everything sold or expired. Skipped when
    -- this scan looks incomplete (far fewer items than last time), so a cut-off scan
    -- can't mark the whole AH as sold out.
    local items = #job.ids
    if not (job.lastCount < 200 or items >= job.lastCount * 0.5) then
      job.gone = {}
      FI:Print("This scan only had %s of the %s items seen last time; items missing from it aren't counted as sold.",
        FI.Number(items), FI.Number(job.lastCount))
    end
    job.phase, job.i = "gone", 0
  end
  if job.phase == "gone" then
    while job.i < #job.gone do
      job.i = job.i + 1
      local itemID = job.gone[job.i]
      local it = realm.items[itemID]
      if it and it.seen == job.lastScan and (it.qty or 0) > 0 then
        H.Record(realm, itemID, job.now, 0, nil, 0, 0, nil)
      end
      if job.i % 50 == 0 and clock() > stopAt then return end
    end
    job.phase = "done"
    return -- the index and what listens for the scan get a frame of their own
  end

  local now = job.now
  realm.lastScan = now
  realm.scans = (realm.scans or 0) + 1
  realm.scanDays = realm.scanDays or {}
  realm.scanDays[math.floor(now / 86400)] = true
  FI.db.lastFullScan = (S.mode == "replicate") and now or FI.db.lastFullScan
  H.UpdateIndex(realm, job.prev, now)
  H.cache = nil
  S.fin = nil
  worker:Hide()

  S.lastFinished = now
  setState("idle")
  FI:Print("Scan done: %s auctions, %s items in %.1fs.", FI.Number(job.auctions), FI.Number(#job.ids), GetTime() - (S.requested or GetTime()))
  FI:Fire("FI_SCAN_DONE", now, nil, job.market)
end

local function step()
  local read = S.mode == "replicate" and readReplicate or readLegacy
  local acc = S.acc
  local total = S.total
  local n = S.done
  local offset = S.mode == "replicate" and -1 or 0 -- replicate indexes are 0-based
  local stopAt = FI:WorkUntil(BUDGET_MS)
  while n < total do
    n = n + 1
    -- one auction the client can't read is skipped, not the whole scan
    local ok, count, buyout, itemID = pcall(read, n + offset)
    if ok and type(itemID) == "number" and count and count > 0 and buyout and buyout > 0 then
      local e = acc[itemID]
      if not e then e = {}; acc[itemID] = e end
      e[#e + 1] = math.floor(buyout / count + 0.5)
      e[#e + 1] = count
    end
    if n % 200 == 0 and clock() > stopAt then break end
  end
  S.done = n
  FI:Fire("FI_SCAN_PROGRESS", S.done, S.total)
  if S.done >= S.total then startFinish() end
end

worker:SetScript("OnUpdate", function()
  local fn = (S.fin and finishStep) or (S.acc and step)
  if not fn then worker:Hide(); return end
  local ok, err = pcall(fn)
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
    local ok, err = pcall(startFinish)
    if not ok then stop(err); return end
  end
  worker:Show()
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
  -- legacy API, which drops results on close (once read, it's saved regardless).
  if S.state == "processing" and S.mode == "legacy" and S.acc then
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
