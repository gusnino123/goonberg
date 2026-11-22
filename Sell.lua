-- Goonberg Terminal: one-press posting. A macro line like
--   /goon sell Linen Cloth 25s
-- posts that item from your bags at that price each while the Auction House is open.
-- Optional after the price: x40 (how many; default all of it for a commodity, one
-- stack otherwise) and a duration: short, medium or long, or its hours as your AH
-- shows them (2h, 8h, 24h on some clients). Default medium.
-- Each press posts once. A price far under Goonberg's market price needs a second
-- press within a few seconds, so a typo (25c for 25g) can't dump your stack.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Sell
local S = {}
FI.Sell = S

S.CONFIRM_WINDOW = 5   -- seconds to press again on a suspicious price
S.LOW_RATIO = 0.3      -- under 30% of the market price counts as suspicious
S.BUSY = 2             -- seconds after a post before the next one (the item is locked)

-- durations: choice 1 to 3. What each lasts depends on the client (2/8/24 hours on
-- some, 12/24/48 on others), so the names come from the game's own labels. "short",
-- "medium" and "long" (or 1, 2, 3) work everywhere.
local DUR_TEXT = { "short", "medium", "long" }
local DUR = { short = 1, medium = 2, long = 3, ["1"] = 1, ["2"] = 2, ["3"] = 3 }
for i, g in ipairs({ "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }) do
  local label = type(_G[g]) == "string" and _G[g]
  local hours = label and tonumber(label:match("(%d+)"))
  if hours then
    DUR_TEXT[i] = hours .. "h"
    DUR[hours .. "h"] = i
  end
end

-- "Linen Cloth 25s x40 48h" -> item text, price, qty, duration
function S.Parse(text)
  local rest = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local qty, dur
  while true do
    local last = rest:match("(%S+)$")
    if not last then break end
    local l = last:lower()
    if not qty and l:match("^x%d+$") then
      qty = tonumber(l:sub(2))
    elseif not dur and DUR[l] then
      dur = DUR[l]
    else
      break
    end
    rest = rest:sub(1, #rest - #last):gsub("%s+$", "")
  end
  local last = rest:match("(%S+)$")
  local price = last and FI.ParseMoney(last)
  if not price or price <= 0 then return nil end
  local item = rest:sub(1, #rest - #last):gsub("%s+$", "")
  if item == "" then return nil end
  return item, price, qty, dur or 2
end

local function bagSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function slotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount or 1, info.isLocked end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
    return link and FI:ItemIDFromLink(link), count or 1, locked
  end
end

-- every bag slot with the item: { bag, slot, count, locked }, and how many in all
function S.Find(id)
  local out, total = {}, 0
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, bagSlots(bag) do
      local itemID, count, locked = slotInfo(bag, slot)
      if itemID == id then
        out[#out + 1] = { bag = bag, slot = slot, count = count, locked = locked }
        if not locked then total = total + count end
      end
    end
  end
  return out, total
end

-- an item in your bags by link, ID or name (whole name first, then the start of one)
function S.Resolve(text)
  local id = FI:ItemIDFromLink(text) or tonumber(text)
  if id then return id end
  local needle = text:lower()
  local prefix
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, bagSlots(bag) do
      local itemID = slotInfo(bag, slot)
      local name = itemID and FI:ItemName(itemID)
      if name then
        local l = name:lower()
        if l == needle then return itemID end
        if not prefix and l:sub(1, #needle) == needle then prefix = itemID end
      end
    end
  end
  return prefix or FI:FindItem(text)
end

local function modernAH()
  local f = _G.AuctionHouseFrame
  return f and f:IsShown() and C_AuctionHouse and C_AuctionHouse.PostCommodity and true or false
end

local function isCommodity(loc)
  local CA = C_AuctionHouse
  if not (CA and CA.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus) then return nil end
  local ok, status = pcall(CA.GetItemCommodityStatus, loc)
  if not ok or not status then return nil end
  if status == Enum.ItemCommodityStatus.Commodity then return true end
  if status == Enum.ItemCommodityStatus.Item then return false end
  return nil -- not loaded yet
end

-- post one auction. Returns what was posted (qty, price each) or nil and a reason.
function S:Post(id, price, qty, dur)
  local slots, total = S.Find(id)
  if #slots == 0 then return nil, "none" end
  if total == 0 then return nil, "locked" end
  local first
  for _, s in ipairs(slots) do if not s.locked then first = s; break end end

  if modernAH() then
    local loc = ItemLocation:CreateFromBagAndSlot(first.bag, first.slot)
    local CA = C_AuctionHouse
    if CA.IsSellItemValid then
      local ok, valid = pcall(CA.IsSellItemValid, loc, false)
      if ok and valid == false then return nil, "invalid" end
    end
    local commodity = isCommodity(loc)
    if commodity == nil then return nil, "loading" end
    if commodity then
      local n = math.min(qty or total, total)
      CA.PostCommodity(loc, dur, n, price)
      return n, price
    end
    -- a non-commodity posts one bag stack at a time
    local n = math.min(qty or first.count, first.count)
    CA.PostItem(loc, dur, n, nil, price * n)
    return n, price
  end

  -- classic Auction House: put the stack in the sell slot, then post it
  if not (PostAuction and ClickAuctionSellItemButton) then return nil, "noah" end
  local n = math.min(qty or first.count, first.count)
  local pickup = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  ClearCursor()
  pickup(first.bag, first.slot)
  ClickAuctionSellItemButton()
  ClearCursor()
  local stack = price * n
  PostAuction(stack, stack, dur, n, 1)
  return n, price
end

local lastPress, confirm = -1, nil

-- /goon sell <item> <price> [x<qty>] [12h|24h|48h]
function S:Command(text)
  local itemText, price, qty, dur = S.Parse(text)
  if not itemText then
    return FI:Print("Usage: /goon sell <item> <price each> [x<how many>] [%s|%s|%s], e.g. /goon sell Linen Cloth 25s",
      DUR_TEXT[1], DUR_TEXT[2], DUR_TEXT[3])
  end
  if not FI.ahOpen then return FI:Print("Open the Auction House first.") end
  local now = GetTime()
  -- a key press can arrive as a down and an up click; and the item stays locked a moment
  if now == lastPress then return end
  if self.busyUntil and now < self.busyUntil then return end
  lastPress = now
  local id = S.Resolve(itemText)
  if not id then return FI:Print("No \"%s\" in your bags.", itemText) end

  local it = FI:Realm().items[id]
  local mkt = it and it.mkt
  if mkt and mkt > 0 and price < mkt * S.LOW_RATIO then
    local key = id .. ":" .. price
    if not (confirm and confirm.key == key and now - confirm.t <= S.CONFIRM_WINDOW) then
      confirm = { key = key, t = now }
      return FI:Print("%s at %s each is far under its market price (%s). Press again within %d s to post anyway.",
        FI:ItemLink(id) or FI:ItemName(id), FI.Money(price), FI.Money(mkt), S.CONFIRM_WINDOW)
    end
  end
  confirm = nil

  local ok, n, why = pcall(S.Post, S, id, price, qty, dur)
  if not ok then return FI:Print("Couldn't post: %s", tostring(n)) end
  if not n then
    local msg = {
      none = "No %s in your bags.",
      locked = "Your %s is still busy from the last post: press again in a moment.",
      invalid = "%s can't be sold on the Auction House.",
      loading = "The game is still loading %s: press again.",
      noah = "Couldn't find the Auction House's sell controls for %s.",
    }
    return FI:Print(msg[why] or "Couldn't post %s.", FI:ItemLink(id) or FI:ItemName(id))
  end
  self.busyUntil = now + S.BUSY
  FI:Print("Posted %s x%d at %s each (%s total, %s).", FI:ItemLink(id) or FI:ItemName(id), n,
    FI.Money(price), FI.Money(price * n), DUR_TEXT[dur] or "?")
end

FI:On("AUCTION_HOUSE_AUCTION_CREATED", function() S.busyUntil = nil end)
