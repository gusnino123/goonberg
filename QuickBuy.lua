-- Goonberg Terminal: one-key refresh, then buy (modern Auction House, commodities).
-- Set a price cap for an item (/goon buycap 1g50s with it open at the AH), then press
-- one macro (/click GoonBuy LeftButton 1) as often as you like. Each press does the
-- next useful step and never more than one:
--   the buy popup is open              -> confirms it, if the macro has the confirm
--     line and the price the game quotes is no higher than the list showed;
--     otherwise nothing (a refresh would knock the popup away)
--   results are on their way           -> nothing (resending restarts the wait)
--   fresh list, cheapest <= your cap   -> opens the game's buy popup; you confirm
--     (with /goon quant 20, "cheapest" is the cheapest listing of 20 or more)
--   stale list, or over your cap       -> refresh, if the AH will take a search now
-- Buying happens only in the game's own popup, after your own press or click to
-- confirm. After a purchase the list refreshes by itself, ready for the next press.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.QuickBuy
local Q = {}
FI.QuickBuy = Q

Q.FRESH = 3            -- seconds a result list counts as current
Q.PENDING_TIMEOUT = 5  -- a refresh with no answer by then is given up on

Q.pending = nil        -- { id, t }: a refresh we're waiting on
Q.buying = nil         -- { id, price }: the buy press that opened the popup
Q.quote = nil          -- { unit, total }: the price the game quotes in the open popup
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

-- the smallest listing the quick-buy key takes (/goon quant 20); 1 takes any
function Q:MinQty()
  local n = math.floor(tonumber(FI.settings.buyMinQty) or 1)
  return n > 1 and n or 1
end

-- the cheapest listing you can buy: unit price, how many, and its row number.
-- Rows that are only your own auctions are skipped, so posting under your cap
-- doesn't leave every press trying to buy your own stack. So are listings with
-- fewer than your minimum quantity from other sellers.
function Q:Cheapest(id)
  local need = self:MinQty()
  local CA = _G.C_AuctionHouse
  if CA and CA.GetCommoditySearchResultInfo then
    for i = 1, MAX_ROWS do
      local ok, info = pcall(CA.GetCommoditySearchResultInfo, id, i)
      if not ok or not info or not info.unitPrice then break end
      local n = others(info)
      if n >= need then return info.unitPrice, n, i end
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
    if d and d.unitPrice and others(d) >= need then return d.unitPrice, others(d), i end
  end
end

local function loading(f)
  local sp = f and f.ItemList and f.ItemList.LoadingSpinner
  return sp and sp:IsShown() or false
end

local hooked
local function popupOpen()
  local dlg = _G.AuctionHouseFrame and _G.AuctionHouseFrame.BuyDialog
  if dlg and not hooked then
    hooked = true
    -- a quote belongs to the popup it was made for: closing the popup drops it
    dlg:HookScript("OnHide", function()
      Q.quote = nil
      FI:Fire("FI_QUICKBUY", "closed")
    end)
  end
  return dlg and dlg:IsShown() or false
end
function Q:PopupOpen() return popupOpen() end

-- the popup's Buy Now button, once the game has priced the purchase and enabled it
function Q:ConfirmTarget()
  local dlg = _G.AuctionHouseFrame and _G.AuctionHouseFrame.BuyDialog
  if not (dlg and dlg:IsShown()) then return nil end
  local btn = dlg.BuyNowButton or dlg.BuyButton
  if btn and btn:IsShown() and (not btn.IsEnabled or btn:IsEnabled()) then return btn end
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
  if popupOpen() then
    -- Confirm only at the price the buy press saw (or your cap, for a popup you
    -- opened by hand). If the game quotes more, the choice stays with you.
    local q = self.quote
    if q and self:ConfirmTarget() then
      local b = self.buying
      local limit = b and b.id == id and b.price or cap
      if q.unit <= limit then return "confirm", id, q.unit, cap end
      return "moved", id, q.unit, cap
    end
    return "popup", id, nil, cap
  end
  local p = self.pending
  if p and now - p.t < self.PENDING_TIMEOUT then return "waiting", id, nil, cap end
  local qd = self.queued
  if qd and qd.id == id and now - qd.t < self.PENDING_TIMEOUT then return "queued", id, nil, cap end
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
  elseif step == "throttled" then
    -- the AH takes a refresh only every so often: hold this press's refresh and
    -- send it the moment the AH will take it (see the watcher below)
    self.queued = { id = id, t = now }
    step = "queued"
  elseif step == "buy" then
    self.buying, self.quote = { id = id, price = price }, nil
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
  -- the list is current: a refresh still waiting to be sent has nothing to add
  if Q.queued and Q.queued.id == id then Q.queued = nil end
  FI:Fire("FI_QUICKBUY", "results")
end)
FI:On("FI_AH_CLOSED", function() Q.pending, Q.queued, Q.buying, Q.quote = nil, nil, nil, nil end)

-- the game prices a purchase before its popup lets you confirm
FI:On("COMMODITY_PRICE_UPDATED", function(_, unit, total)
  Q.quote = type(unit) == "number" and { unit = unit, total = total } or nil
  FI:Fire("FI_QUICKBUY", "quote")
end)
FI:On("COMMODITY_PRICE_UNAVAILABLE", function()
  Q.quote = nil
  FI:Fire("FI_QUICKBUY", "quote")
end)

-- A purchase went through (or fell over): the list on screen is out of date, so
-- refresh it now instead of spending your next press on that.
local function afterPurchase(event)
  Q.quote, Q.buying = nil, nil
  local id = Q:CurrentItem()
  if id and Q:Caps()[id] then
    Q.freshAt[id] = nil
    Q.queued = { id = id, t = GetTime() }
  end
  if Q.last then Q.last.step = event == "COMMODITY_PURCHASE_SUCCEEDED" and "bought" or "failed" end
  FI:Fire("FI_QUICKBUY", "purchase")
end
FI:On("COMMODITY_PURCHASE_SUCCEEDED", afterPurchase)
FI:On("COMMODITY_PURCHASE_FAILED", afterPurchase)

-- Send a queued refresh as soon as the AH will take it: on the game's "ready" event,
-- and by checking every tenth of a second in case the client doesn't send one.
-- Dropped if you've switched item, the buy popup opened, or it's waited too long.
function Q:SendQueued()
  local qd = self.queued
  if not qd then return end
  local now = GetTime()
  if not FI.ahOpen or now - qd.t >= self.PENDING_TIMEOUT or self:CurrentItem() ~= qd.id or popupOpen() then
    self.queued = nil
    FI:Fire("FI_QUICKBUY", "dropped")
    return
  end
  if not searchReady() then return end
  self.queued = nil
  if sendRefresh(qd.id) then
    self.pending = { id = qd.id, t = now }
    if self.last then self.last.step = "refresh" end
  end
  FI:Fire("FI_QUICKBUY", "sent")
end
FI:On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function() Q:SendQueued() end)
local qtick = 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
  if not Q.queued then return end
  qtick = qtick + dt
  if qtick < 0.1 then return end
  qtick = 0
  Q:SendQueued()
end)

-- the item in the AH's sell view, if one is in the slot
local function sellItem()
  local ah = _G.AuctionHouseFrame
  if not (ah and C_Item and C_Item.GetItemID) then return nil end
  for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
    local f = ah[key]
    if f and f:IsVisible() and f.GetItem then
      local ok, loc = pcall(f.GetItem, f)
      if ok and loc then
        local ok2, id = pcall(C_Item.GetItemID, loc)
        if ok2 and id then return id end
      end
    end
  end
end

-- "/goon quant 20": the quick-buy key only takes a listing of 20 or more. One
-- number for every item; "/goon quant 1" (or off) takes any listing again.
function Q:SetMinQty(text)
  local arg = (text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if arg == "" then
    local n = self:MinQty()
    FI:Print(n > 1 and "Quick buy takes listings of %s or more. /goon quant 1 takes any."
      or "Quick buy takes a listing of any size. /goon quant 20 skips ones under 20.", FI.Number(n))
    return
  end
  local n = (arg == "off" or arg == "clear" or arg == "any") and 1 or tonumber(arg:match("^x?(%d+)$"))
  if not n or n < 1 then
    FI:Print("Couldn't read that quantity. Try /goon quant 20, or /goon quant 1 for any size.")
    return
  end
  FI.settings.buyMinQty = n
  FI:Print(n > 1 and "Quick buy now skips listings under %s and takes the cheapest one of %s or more (still at or under your cap)."
    or "Quick buy takes a listing of any size again.", FI.Number(n), FI.Number(n))
  FI:Fire("FI_QUICKBUY", "cap")
end

-- "/goon buycap 1g50s": the cap for the item open at the AH (buy or sell view).
-- "/goon buycap Mageweave Cloth 2s50c" names the item, so it works from anywhere.
function Q:SetCap(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local id
  local itemText, last = text:match("^(.-)%s+(%S+)$")
  if itemText and itemText ~= "" then
    local named = FI:FindItem(itemText)
    if named then id, text = named, last end
  end
  id = id or self:CurrentItem() or sellItem()
  if not id then
    FI:Print("Open the item at the Auction House (Buy or Sell), or name it: /goon buycap Mageweave Cloth 2s50c")
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
