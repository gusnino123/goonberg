-- Goonberg Terminal: one-press posting. A macro line like
--   /goon sell Linen Cloth 25s
-- posts that item from your bags at that price each while the Auction House is open.
-- Optional after the price: x40 (how many; default all of it for a commodity, one
-- stack otherwise) and a duration: short, medium or long, or its hours as your AH
-- shows them (2h, 8h, 24h on some clients). Default medium.
-- Each press posts once. A price far under Goonberg's market price needs a second
-- press within a few seconds, so a typo (25c for 25g) can't dump your stack.
-- Presets: /goon sell save Linen Cloth 25s x5 keeps that price and stack size for the
-- item; then /goon sell Linen Cloth (or a click on the AH's Quick sell panel, see
-- UI/SellPresets.lua) posts it without typing them again.
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
  for bag = 0, FI.LastBag() do
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
  for bag = 0, FI.LastBag() do
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

-- The bag slot to post from: with a stack size, the smallest stack that has enough
-- (the game splits it), else the biggest one; without one, the first free stack.
local function pickSlot(slots, want)
  local fit, biggest
  for _, s in ipairs(slots) do
    if not s.locked then
      if not want then return s end
      if s.count >= want and (not fit or s.count < fit.count) then fit = s end
      if not biggest or s.count > biggest.count then biggest = s end
    end
  end
  return fit or biggest
end

-- Post one auction (on the classic AH: every full stack of that size at once).
-- Returns how many were posted in all, the price each and how many auctions, or
-- nil and a reason.
function S:Post(id, price, qty, dur)
  local slots, total = S.Find(id)
  if #slots == 0 then return nil, "none" end
  if total == 0 then return nil, "locked" end
  local first = pickSlot(slots, qty)

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
      return n, price, 1
    end
    -- a non-commodity posts one bag stack at a time (part of one when it's bigger:
    -- the game splits it)
    local n = math.min(qty or first.count, first.count)
    CA.PostItem(loc, dur, n, nil, price * n)
    return n, price, 1
  end

  -- classic Auction House: put the stack in the sell slot, then post it. With a
  -- stack size the game splits your bags into as many stacks of it as you have.
  if not (PostAuction and ClickAuctionSellItemButton) then return nil, "noah" end
  local n, stacks = math.min(qty or first.count, first.count), 1
  if qty and total >= qty then n, stacks = qty, math.floor(total / qty) end
  local pickup = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
  ClearCursor()
  pickup(first.bag, first.slot)
  ClickAuctionSellItemButton()
  ClearCursor()
  local stack = price * n
  PostAuction(stack, stack, dur, n, stacks)
  return n * stacks, price, stacks
end

-- ---------------------------------------------------------------------------
-- Presets: a price (and stack size and duration) kept per item, on your faction's
-- market like buy caps: [itemID] = { price = copper each, qty = stack size or nil, dur = 1..3 }
-- ---------------------------------------------------------------------------
function S:Presets()
  local realm = FI:Market("home")
  realm.sellPresets = realm.sellPresets or {}
  return realm.sellPresets
end

function S.DurText(dur) return DUR_TEXT[dur] or "?" end

-- The item in the AH's Sell view, with the price each, quantity and duration typed
-- there, and whether it's a commodity
function S.SellView()
  local ah = _G.AuctionHouseFrame
  if not (ah and C_Item and C_Item.GetItemID) then return nil end
  for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
    local f = ah[key]
    if f and f:IsVisible() and f.GetItem then
      local ok, loc = pcall(f.GetItem, f)
      local ok2, id = false, nil
      if ok and loc then ok2, id = pcall(C_Item.GetItemID, loc) end
      if ok2 and id then
        local function call(obj, name)
          if not (obj and type(obj[name]) == "function") then return nil end
          local okc, v = pcall(obj[name], obj)
          return okc and type(v) == "number" and v or nil
        end
        local price = call(f, "GetUnitPrice") or call(f.PriceInput, "GetAmount")
        local qty = call(f, "GetQuantity") or call(f.QuantityInput, "GetQuantity")
        return id, price, qty, call(f, "GetDuration"), key == "CommoditiesSellFrame"
      end
    end
  end
end

-- keep a preset, and say so in chat (with a warning for a price far under market)
function S:Save(id, price, qty, dur)
  if qty and qty < 1 then qty = nil end
  dur = DUR_TEXT[dur or 0] and dur or 2
  self:Presets()[id] = { price = price, qty = qty, dur = dur }
  FI:Print("Saved: %s at %s each%s, %s. Click it on the Quick sell panel at the AH, or /goon sell %s.",
    FI:ItemLink(id) or FI:ItemName(id), FI.Money(price), qty and (" in stacks of " .. qty) or "",
    DUR_TEXT[dur], FI:ItemName(id))
  local it = FI:Realm().items[id]
  local mkt = it and it.mkt
  if mkt and mkt > 0 and price < mkt * S.LOW_RATIO then
    FI:Print("Careful: that's far under its market price (%s).", FI.Money(mkt))
  end
  FI:Fire("FI_SELL_PRESETS")
end

function S:Remove(id)
  if not self:Presets()[id] then return false end
  self:Presets()[id] = nil
  FI:Print("Removed the sell preset for %s.", FI:ItemLink(id) or FI:ItemName(id))
  FI:Fire("FI_SELL_PRESETS")
  return true
end

-- "/goon sell save": the item in the Sell view as you set it up there.
-- "/goon sell save Linen Cloth 25s x5 long": as typed.
function S:SaveCommand(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    local id, price, qty, dur, commodity = S.SellView()
    if not id then
      return FI:Print("Put an item in the AH's Sell slot and type its price first, or name it: /goon sell save Linen Cloth 25s x5")
    end
    if not price or price <= 0 then return FI:Print("Type a price in the Sell view first.") end
    -- a commodity's quantity box starts at all you have: that means "all", not a size
    if commodity and qty then
      local _, total = S.Find(id)
      if qty >= total then qty = nil end
    end
    return self:Save(id, price, qty, dur)
  end
  local itemText, price, qty, dur = S.Parse(text)
  if not itemText then
    return FI:Print("Usage: /goon sell save <item> <price each> [x<stack size>] [%s|%s|%s], or /goon sell save with the item in the AH's Sell view.",
      DUR_TEXT[1], DUR_TEXT[2], DUR_TEXT[3])
  end
  local id = S.Resolve(itemText)
  if not id then return FI:Print("Couldn't find an item called \"%s\".", itemText) end
  self:Save(id, price, qty, dur)
end

-- presets sorted by name: { id, p, name }
function S:Sorted()
  local rows = {}
  for id, p in pairs(self:Presets()) do rows[#rows + 1] = { id = id, p = p, name = FI:ItemName(id) } end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

function S:List()
  local rows = self:Sorted()
  if #rows == 0 then
    return FI:Print("No sell presets yet: /goon sell save Linen Cloth 25s x5, or Save on the Quick sell panel at the AH.")
  end
  FI:Print("Sell presets:")
  for _, r in ipairs(rows) do
    FI:Print("  %s: %s each%s, %s", FI:ItemLink(r.id) or r.name, FI.Money(r.p.price),
      r.p.qty and (" in stacks of " .. r.p.qty) or "", S.DurText(r.p.dur))
  end
end

local lastPress, confirm = -1, nil

-- Post now, with the checks every press needs. checkLow: a price far under market
-- needs a second press (a preset's price was chosen on purpose, so it skips this).
function S:PostNow(id, price, qty, dur, checkLow)
  if not FI.ahOpen then return FI:Print("Open the Auction House first.") end
  local now = GetTime()
  -- a key press can arrive as a down and an up click; and the item stays locked a moment
  if now == lastPress then return end
  if self.busyUntil and now < self.busyUntil then return end
  lastPress = now

  if checkLow then
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
  end
  confirm = nil

  local ok, n, why, stacks = pcall(S.Post, S, id, price, qty, dur)
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
  local what = (stacks or 1) > 1 and (stacks .. " stacks of " .. math.floor(n / stacks)) or ("x" .. n)
  FI:Print("Posted %s %s at %s each (%s total, %s).", FI:ItemLink(id) or FI:ItemName(id), what,
    FI.Money(price), FI.Money(price * n), DUR_TEXT[dur] or "?")
  return n
end

-- post an item's saved preset
function S:PostPreset(id)
  local p = self:Presets()[id]
  if not p then return FI:Print("No sell preset for %s.", FI:ItemLink(id) or FI:ItemName(id)) end
  return self:PostNow(id, p.price, p.qty, p.dur or 2, false)
end

-- /goon sell <item> <price> [x<qty>] [12h|24h|48h]  |  /goon sell <item> (its preset)
-- /goon sell save [...]  |  remove <item>  |  list  |  panel on|off
function S:Command(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local sub, rest = text:match("^(%S+)%s*(.-)$")
  sub = sub and sub:lower()
  if sub == "save" then return self:SaveCommand(rest) end
  if sub == "list" and rest == "" then return self:List() end
  if (sub == "remove" or sub == "delete") and rest ~= "" then
    local id = S.Resolve(rest)
    if not (id and self:Remove(id)) then FI:Print("No sell preset for \"%s\".", rest) end
    return
  end
  if sub == "panel" and rest == "reset" then
    FI.settings.sellPanelPos = nil
    FI:Print("The Quick sell panel goes back beside the AH.")
    if FI.SellPanel and FI.SellPanel.frame then FI.SellPanel.frame:Hide() end
    return FI:Fire("FI_SELL_PRESETS")
  end
  if sub == "panel" and (rest == "on" or rest == "off") then
    FI.settings.sellPanel = rest == "on"
    FI:Print("The Quick sell panel at the AH is now %s.", rest)
    return FI:Fire("FI_SELL_PRESETS")
  end

  local itemText, price, qty, dur = S.Parse(text)
  if not itemText then
    -- just a name: post its preset
    local id = text ~= "" and S.Resolve(text)
    if id and self:Presets()[id] then return self:PostPreset(id) end
    return FI:Print("Usage: /goon sell <item> <price each> [x<how many>] [%s|%s|%s], e.g. /goon sell Linen Cloth 25s. /goon sell save keeps a price for one-click selling.",
      DUR_TEXT[1], DUR_TEXT[2], DUR_TEXT[3])
  end
  if not FI.ahOpen then return FI:Print("Open the Auction House first.") end
  local id = S.Resolve(itemText)
  if not id then return FI:Print("No \"%s\" in your bags.", itemText) end
  self:PostNow(id, price, qty, dur, true)
end

FI:On("AUCTION_HOUSE_AUCTION_CREATED", function() S.busyUntil = nil end)
