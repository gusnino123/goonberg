-- Goonberg Terminal: one-key refresh, then buy (modern Auction House, commodities).
-- Set a price cap for an item (/goon buycap 1g50s with it open at the AH), then press
-- one macro (/click GoonBuy LeftButton 1) as often as you like. Each press does the
-- next useful step and never more than one:
--   the buy popup is already open      -> nothing (a refresh would knock it away)
--   results are on their way           -> nothing (resending restarts the wait)
--   fresh list, cheapest <= your cap   -> opens the game's buy popup; you confirm
--   stale list, or over your cap       -> refresh, if the AH will take a search now
-- Buying happens only in the game's own popup, after your own click to confirm.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.QuickBuy
local Q = {}
FI.QuickBuy = Q

Q.FRESH = 3            -- seconds a result list counts as current
Q.PENDING_TIMEOUT = 5  -- a refresh with no answer by then is given up on

Q.pending = nil        -- { id, t }: a refresh we're waiting on
Q.freshAt = {}         -- itemID -> GetTime() its results last arrived

-- Caps per item, per realm (prices differ between realms)
function Q:Caps()
  local realm = FI:Market("home")
  realm.buyCaps = realm.buyCaps or {}
  return realm.buyCaps
end

local function buyFrame()
  local ah = _G.AuctionHouseFrame
  local f = ah and ah.CommoditiesBuyFrame
  if f and f:IsVisible() then return f end
end

local function firstRow(f)
  local list = f.ItemList
  local box = list and list.ScrollBox
  if not box or not box.GetFrames then return nil end
  local ok, frames = pcall(box.GetFrames, box)
  return ok and frames and frames[1] or nil
end

-- the commodity open in the AH's buy view
function Q:CurrentItem()
  local f = buyFrame()
  if not f then return nil end
  if f.GetItemID then
    local ok, id = pcall(f.GetItemID, f)
    if ok and id then return id end
  end
  local row = firstRow(f)
  return row and row.rowData and row.rowData.itemID or nil
end

-- how many in a listing someone else posted (you can't buy your own)
local function others(d)
  local q = d.quantity or 0
  return q - math.min(d.numOwnerItems or 0, q)
end

local MAX_ROWS = 10

-- the cheapest listing you can buy: unit price, how many, and its row number.
-- Rows that are only your own auctions are skipped, so posting under your cap
-- doesn't leave every press trying to buy your own stack.
function Q:Cheapest(id)
  local CA = _G.C_AuctionHouse
  if CA and CA.GetCommoditySearchResultInfo then
    for i = 1, MAX_ROWS do
      local ok, info = pcall(CA.GetCommoditySearchResultInfo, id, i)
      if not ok or not info or not info.unitPrice then break end
      local n = others(info)
      if n > 0 then return info.unitPrice, n, i end
    end
    return nil
  end
  local f = buyFrame()
  local box = f and f.ItemList and f.ItemList.ScrollBox
  local ok, frames = false, nil
  if box and box.GetFrames then ok, frames = pcall(box.GetFrames, box) end
  if not ok or not frames then return nil end
  for i = 1, math.min(#frames, MAX_ROWS) do
    local d = frames[i].rowData
    if d and d.unitPrice and others(d) > 0 then return d.unitPrice, others(d), i end
  end
end

local function loading(f)
  local sp = f and f.ItemList and f.ItemList.LoadingSpinner
  return sp and sp:IsShown() or false
end

local function popupOpen()
  local dlg = _G.AuctionHouseFrame and _G.AuctionHouseFrame.BuyDialog
  return dlg and dlg:IsShown() or false
end

local function searchReady()
  local CA = _G.C_AuctionHouse
  if CA and CA.IsThrottledMessageSystemReady then
    local ok, ready = pcall(CA.IsThrottledMessageSystemReady)
    return not ok or ready
  end
  return true
end

local function sendRefresh(id)
  local CA = _G.C_AuctionHouse
  if not CA then return false end
  if CA.RefreshCommoditySearchResults then
    return (pcall(CA.RefreshCommoditySearchResults, id))
  elseif CA.SendSearchQuery and CA.MakeItemKey then
    return (pcall(CA.SendSearchQuery, CA.MakeItemKey(id), {}, false))
  end
  return false
end

-- What one press should do. Returns the step and, for the status line, the
-- item, its cheapest price and the cap.
function Q:Decide(now)
  local id = self:CurrentItem()
  if not id then return "noitem" end
  local cap = self:Caps()[id]
  if not cap then return "nocap", id end
  if popupOpen() then return "popup", id, nil, cap end
  local p = self.pending
  if p and now - p.t < self.PENDING_TIMEOUT then return "waiting", id, nil, cap end
  if p then self.pending = nil end
  local f = buyFrame()
  if loading(f) then return "waiting", id, nil, cap end
  local price = self:Cheapest(id)
  local fresh = self.freshAt[id] and now - self.freshAt[id] <= self.FRESH
  if fresh and price and price <= cap then return "buy", id, price, cap end
  if not searchReady() then return "throttled", id, fresh and price or nil, cap end
  return "refresh", id, fresh and price or nil, cap
end

-- The proxy buttons the macro's press goes through (see UI/QuickBuy.lua) click the
-- game's own first row and Buy button only when this says "buy".
function Q:Press()
  local now = GetTime()
  local step, id, price, cap = self:Decide(now)
  if step == "refresh" then
    if sendRefresh(id) then
      self.pending = { id = id, t = now }
    else
      step = "norefresh"
    end
  elseif step == "buy" then
    local _, qty = self:Cheapest(id)
    FI:Print("Buy ready: %s x%s at %s each (your cap %s). Confirm in the popup.",
      FI:ItemLink(id) or tostring(id), qty and FI.Number(qty) or "?", FI.Money(price), FI.Money(cap))
  end
  self.last = { step = step, id = id, price = price, cap = cap, t = now }
  FI:Fire("FI_QUICKBUY", step)
  return step, id, price, cap
end

-- the targets a "buy" press clicks: the cheapest row you can buy (sets the quantity
-- to that listing's) and the Buy button that opens the game's confirmation
function Q:Targets()
  local f = buyFrame()
  if not f then return nil end
  local id = self:CurrentItem()
  local _, _, index = self:Cheapest(id)
  local row = firstRow(f)
  if index and index > 1 then
    local box = f.ItemList.ScrollBox
    local ok, frames = pcall(box.GetFrames, box)
    row = ok and frames and frames[index] or nil
  end
  local btn = f.BuyDisplay and f.BuyDisplay.BuyButton
  return row, btn
end

FI:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(_, id)
  if not id then return end
  Q.freshAt[id] = GetTime()
  if Q.pending and Q.pending.id == id then Q.pending = nil end
  FI:Fire("FI_QUICKBUY", "results")
end)
FI:On("FI_AH_CLOSED", function() Q.pending = nil end)

-- "/goon buycap 1g50s": the cap for the item open at the AH
function Q:SetCap(text)
  local id = self:CurrentItem()
  if not id then
    FI:Print("Open an item in the Auction House's buy view first, then set its cap.")
    return
  end
  local caps = self:Caps()
  local arg = (text or ""):lower()
  if arg == "off" or arg == "clear" then
    caps[id] = nil
    FI:Print("No buy cap for %s now: the quick-buy key won't buy it.", FI:ItemLink(id) or id)
  elseif arg == "" then
    FI:Print("%s: buy cap %s. /goon buycap 1g50s sets it, /goon buycap off clears it.",
      FI:ItemLink(id) or id, caps[id] and FI.Money(caps[id]) or "not set")
  else
    local copper = FI.ParseMoney(text)
    if not copper or copper <= 0 then
      FI:Print("Couldn't read that price. Try 1g50s, 75s or 1.5 (gold).")
      return
    end
    caps[id] = copper
    FI:Print("%s: the quick-buy key buys at %s each or less.", FI:ItemLink(id) or id, FI.Money(copper))
  end
  FI:Fire("FI_QUICKBUY", "cap")
end
