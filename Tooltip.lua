-- Goonberg Terminal: Auction House value on every item tooltip (bags, bank, mail, links...)
---@type string, GoonbergTerminal
local _, FI = ...

local function vendorPrice(itemID)
  local sell = select(11, FI.GetItemInfo(itemID))
  return sell and sell > 0 and sell or nil
end

-- How many are in the hovered stack, when the tooltip is for a bag slot
local function stackCount(tooltip)
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if not owner then return 1 end
  local count
  if owner.count then count = owner.count end
  if not count and owner.GetBagID and owner.GetID and C_Container and C_Container.GetContainerItemInfo then
    local ok, info = pcall(C_Container.GetContainerItemInfo, owner:GetBagID(), owner:GetID())
    if ok and info then count = info.stackCount end
  end
  if not count and owner.Count and owner.Count.GetText then
    count = tonumber(owner.Count:GetText() or "")
  end
  return (count and count > 1) and count or 1
end

-- The lines you can turn on and off (Options in the Goonberg window), in the order
-- they show. Saved in settings.tooltipLines; a line is on unless it's set to false.
FI.TOOLTIP_LINES = {
  { key = "vendor", label = "Vendor", hint = "What a vendor pays for the whole stack" },
  { key = "vendorEach", label = "Vendor (ea)", hint = "What a vendor pays for one (shown on stacks)" },
  { key = "market", label = "Market", hint = "The AH market price of the whole stack" },
  { key = "marketEach", label = "Market (ea)", hint = "The AH market price of one (shown on stacks)" },
  { key = "de", label = "Disenchant", hint = "What its disenchant materials are worth" },
  { key = "cap", label = "Buy cap", hint = "Your quick-buy cap for the item, if you set one" },
  { key = "qty", label = "Buy quantity", hint = "The smallest listing your quick-buy key takes (/goon quantity), shown under a buy cap" },
}

-- A few clean lines: Vendor, Market, Disenchant (for the whole stack), the price of
-- one on a stack, and your buy cap. The one that pays most is green. Hold Shift for
-- the details.
local function addLines(tooltip, itemID)
  if not FI.db or not FI.settings.tooltip or not itemID then return end
  if tooltip.fiLastItem == itemID and tooltip.fiLastAdded == GetTime() then return end
  local realm = FI:Realm()
  local it = realm and realm.items[itemID]
  local market = it and it.mkt
  local vendor = vendorPrice(itemID)
  -- last known material prices, however old (the line says so when they're over a day)
  local de, deComplete, deParts = FI.Disenchant:Value(itemID, FI.Disenchant.LAST_KNOWN)
  -- your quick-buy cap for this item, if you set one (/goon buycap)
  local cap = FI.QuickBuy and FI.QuickBuy:Caps()[itemID]
  if not (market or vendor or de or cap) then return end
  local count = stackCount(tooltip)
  local shift = IsShiftKeyDown()
  local soft, up = FI.colors.soft, FI.colors.up

  -- the lines you've left on: { label, key, value, prefix, each, text }. each: the price
  -- of one, not of the whole stack. text: shown as it is, for a line that isn't money.
  -- With nothing to show, Goonberg adds nothing at all.
  local on = FI.settings.tooltipLines or {}
  local stack = count > 1
  local rows, any = {}, false
  local function add(setting, label, key, value, prefix, each, text)
    if on[setting] == false then return end
    rows[#rows + 1] = { label, key, value, prefix, each, text }
    any = any or value ~= nil
  end
  add("vendor", "Vendor", "vendor", vendor)
  if stack and vendor then add("vendorEach", "Vendor (ea)", "vendor", vendor, nil, true) end
  add("market", "Market", "market", market)
  if stack and market then add("marketEach", "Market (ea)", "market", market, nil, true) end
  if de then
    local oldest = deParts and FI.Disenchant:OldestPrice(deParts)
    local old = oldest and time() - oldest > 86400
    add("de", old and ("Disenchant |cff9e998f(mats %s)|r"):format(FI.Ago(oldest)) or "Disenchant", "de", de, "~")
  end
  -- a cap is always a price each
  if cap then
    add("cap", stack and "Buy cap (ea)" or "Buy cap", "cap", cap, nil, true)
    -- ...and the smallest listing the quick-buy key takes goes with it (/goon quantity:
    -- one number for every item)
    local min = FI.QuickBuy:MinQty()
    add("qty", "Buy quantity", "qty", nil, nil, nil, min > 1 and (FI.Number(min) .. " or more") or "any")
  end
  if not any then return end

  -- what each way actually pays you: the vendor pays in full, the AH pays what
  -- you'd sell for (cheapest listing or market, whichever is lower) minus its 5% cut
  local sell = market and (FI.Crafting:SellPrice(itemID) or market)
  local net = {
    vendor = vendor,
    market = sell and sell * 0.95,
    de = de and de * 0.95,
  }
  local best, bestV
  for k, v in pairs(net) do
    if v and (not bestV or v > bestV) then best, bestV = k, v end
  end

  -- header: name on the left, how fresh the price is on the right
  local age
  if it and it.imported and (not it.seen or it.imported > it.seen) then
    age = "Auctionator, " .. FI.Ago(it.imported)
  elseif it and it.seen then
    age = "scanned " .. FI.Ago(it.seen)
  elseif not market then
    age = "not seen on the AH"
  end
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("|cffffd100Goonberg|r" .. (count > 1 and ("  |cff9e998fx%d|r"):format(count) or ""),
    age and ("|cff9e998f%s|r"):format(age) or "")

  for _, row in ipairs(rows) do
    local label, key, value, prefix, each = row[1], row[2], row[3], row[4], row[5]
    local r, g, b = soft[1], soft[2], soft[3]
    local vr, vg, vb = 1, 1, 1
    if best == key then r, g, b = up[1], up[2], up[3]; vr, vg, vb = up[1], up[2], up[3] end
    local text = row[6] or (value and ((prefix or "") .. FI.Coins(value * (each and 1 or count))) or "|cff9e998f-|r")
    tooltip:AddDoubleLine(label, text, r, g, b, vr, vg, vb)
  end

  if shift then
    local function detail(label, value)
      tooltip:AddDoubleLine("   " .. label, value, soft[1], soft[2], soft[3], soft[1], soft[2], soft[3])
    end
    if it and market and (on.market ~= false or on.marketEach ~= false) then
      local st = FI.History.Stats(it, time())
      if st.min then detail("Lowest now", FI.Coins(st.min))
      elseif it.seen and it.seen == realm.lastScan then detail("Lowest now", "none listed") end
      if st.c7 then detail("7 day change", FI.ColoredPercent(st.c7)) end
      if st.soldPerDay then detail("Est. sold / day", FI.Number(st.soldPerDay)) end
    end
    if de and deParts and on.de ~= false then
      for _, p in ipairs(deParts) do
        local qty = p.qty % 1 == 0 and tostring(p.qty) or ("%.1f"):format(p.qty)
        local pct = p.chance < 0.01 and ("%.1f"):format(p.chance * 100) or math.floor(p.chance * 100 + 0.5)
        local priceAge = p.t and time() - p.t > 86400 and (" |cff9e998f(" .. FI.Ago(p.t) .. ")|r") or ""
        detail(("%s%%  %s x%s%s"):format(pct, FI:ItemName(p.id), qty, p.converted and " (3:1 essence)" or ""),
          p.price and (FI.Coins(p.price * p.qty) .. priceAge) or "no price")
      end
      if not deComplete then detail("Some materials have no AH price yet", "") end
      local n = FI.Disenchant:Samples(itemID)
      if n > 0 then detail(("Odds include %d of your disenchants"):format(n), "") end
    end
    tooltip:AddLine("|cff9e998fGreen pays the most after the 5% AH cut.|r")
  end
  tooltip.fiLastItem, tooltip.fiLastAdded = itemID, GetTime()
  tooltip:Show()
end

local function itemFromTooltip(tooltip, data)
  if data and data.id then return data.id end
  if tooltip.GetItem then
    local _, link = tooltip:GetItem()
    return FI:ItemIDFromLink(link)
  end
end

FI:On("PLAYER_LOGIN", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip or tooltip == ShoppingTooltip1 then
        addLines(tooltip, itemFromTooltip(tooltip, data))
      end
    end)
  else
    for _, tip in ipairs({ GameTooltip, ItemRefTooltip }) do
      tip:HookScript("OnTooltipSetItem", function(self) addLines(self, itemFromTooltip(self)) end)
    end
  end
end)
