-- Goonberg Terminal: Auction House value on every item tooltip (bags, bank, mail, links...)
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

-- Three clean lines: Vendor, Market, Disenchant (for the whole stack).
-- The one that pays most is green. Hold Shift for the details.
local function addLines(tooltip, itemID)
  if not FI.db or not FI.settings.tooltip or not itemID then return end
  if tooltip.fiLastItem == itemID and tooltip.fiLastAdded == GetTime() then return end
  local realm = FI:Realm()
  local it = realm and realm.items[itemID]
  local market = it and it.mkt
  local vendor = vendorPrice(itemID)
  local de, deComplete, deParts = FI.Disenchant:Value(itemID)
  if not (market or vendor or de) then return end
  local count = stackCount(tooltip)
  local shift = IsShiftKeyDown()
  local soft, up = FI.colors.soft, FI.colors.up

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
  tooltip:AddDoubleLine("|cffe8b84aGoonberg|r" .. (count > 1 and ("  |cff8b95a3x%d|r"):format(count) or ""),
    age and ("|cff8b95a3%s|r"):format(age) or "")

  local function line(label, key, value, prefix)
    local r, g, b = soft[1], soft[2], soft[3]
    local vr, vg, vb = 1, 1, 1
    if best == key then r, g, b = up[1], up[2], up[3]; vr, vg, vb = up[1], up[2], up[3] end
    local text = value and ((prefix or "") .. FI.Coins(value * count)) or "|cff8b95a3-|r"
    tooltip:AddDoubleLine(label, text, r, g, b, vr, vg, vb)
  end
  line("Vendor", "vendor", vendor)
  line("Market", "market", market)
  if de then line("Disenchant", "de", de, "~") end

  if shift then
    local function detail(label, value)
      tooltip:AddDoubleLine("   " .. label, value, soft[1], soft[2], soft[3], soft[1], soft[2], soft[3])
    end
    if it and market then
      local st = FI.History.Stats(it, time())
      if count > 1 then detail("Market, each", FI.Money(market)) end
      if st.min then detail("Lowest now", FI.Money(st.min))
      elseif it.seen and it.seen == realm.lastScan then detail("Lowest now", "none listed") end
      if st.c7 then detail("7 day change", FI.ColoredPercent(st.c7)) end
      if st.soldPerDay then detail("Est. sold / day", FI.Number(st.soldPerDay)) end
    end
    if de and deParts then
      for _, p in ipairs(deParts) do
        local qty = p.qty % 1 == 0 and tostring(p.qty) or ("%.1f"):format(p.qty)
        local pct = p.chance < 0.01 and ("%.1f"):format(p.chance * 100) or math.floor(p.chance * 100 + 0.5)
        detail(("%s%%  %s x%s%s"):format(pct, FI:ItemName(p.id), qty, p.converted and " (3:1 essence)" or ""),
          p.price and FI.Money(p.price * p.qty) or "no price")
      end
      if not deComplete then detail("Some materials have no AH price yet", "") end
    end
    tooltip:AddLine("|cff8b95a3Green pays the most after the 5% AH cut.|r")
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
