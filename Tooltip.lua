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

local function addLines(tooltip, itemID)
  if not FI.db or not FI.settings.tooltip or not itemID then return end
  if tooltip.fiLastItem == itemID and tooltip.fiLastAdded == GetTime() then return end
  local realm = FI:Realm()
  local it = realm and realm.items[itemID]
  local vendor = vendorPrice(itemID)
  local de, deComplete, deParts = FI.Disenchant:Value(itemID)

  -- Disenchant line (plus, holding Shift, what it breaks into)
  local function addDisenchant(mkt, count)
    if not de then return end
    local soft = FI.colors.soft
    -- Fair comparison: the item and its materials would both be sold on the AH
    -- (same 5% cut), so compare what the item sells for with what its mats sell for.
    local itemSell = FI.Crafting:SellPrice(itemID) or mkt
    local better = itemSell and de > itemSell
    local r, g, b = soft[1], soft[2], soft[3]
    if better or not mkt then r, g, b = FI.colors.up[1], FI.colors.up[2], FI.colors.up[3] end
    local label = better and "Disenchant (better than AH)" or "Disenchant"
    tooltip:AddDoubleLine(label, "~" .. FI.Money(de * count) .. (deComplete and "" or " ?"), r, g, b, 1, 1, 1)
    if IsShiftKeyDown() and deParts then
      for _, p in ipairs(deParts) do
        local qty = p.qty % 1 == 0 and tostring(p.qty) or ("%.1f"):format(p.qty)
        tooltip:AddDoubleLine(("   %s%%  %s x%s%s"):format(p.chance < 0.01 and ("%.1f"):format(p.chance * 100) or math.floor(p.chance * 100 + 0.5), FI:ItemName(p.id), qty, p.converted and " (as 3:1 essence)" or ""),
          p.price and FI.Money(p.price * p.qty) or "no price", soft[1], soft[2], soft[3], soft[1], soft[2], soft[3])
      end
      tooltip:AddLine("|cff8b95a3Estimate from the Forever disenchanting table (by required level).|r")
    end
  end

  if not it or not it.mkt then
    -- never seen on the AH: gear can still show what it disenchants for
    if de then
      tooltip:AddLine(" ")
      tooltip:AddDoubleLine("|cffe8b84aGoonberg|r", "|cff8b95a3not seen on the AH|r")
      addDisenchant(nil, stackCount(tooltip))
      tooltip.fiLastItem, tooltip.fiLastAdded = itemID, GetTime()
      tooltip:Show()
    end
    return
  end

  local s = FI.History.Stats(it, time())
  local gold, muted = FI.colors.gold, FI.colors.soft
  local count = stackCount(tooltip)

  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("|cffe8b84aGoonberg|r", ("7d %s"):format(FI.ColoredPercent(s.c7)))
  tooltip:AddDoubleLine("Market", FI.Money(it.mkt), muted[1], muted[2], muted[3], gold[1], gold[2], gold[3])
  if count > 1 then
    tooltip:AddDoubleLine(("Stack of %d"):format(count), FI.Money(it.mkt * count), muted[1], muted[2], muted[3], gold[1], gold[2], gold[3])
  end
  if s.min then
    tooltip:AddDoubleLine("Lowest now", FI.Money(s.min), muted[1], muted[2], muted[3], gold[1], gold[2], gold[3])
  elseif it.seen and it.seen == realm.lastScan then
    tooltip:AddDoubleLine("Lowest now", "none listed", muted[1], muted[2], muted[3], muted[1], muted[2], muted[3])
  end
  if s.soldPerDay then
    tooltip:AddDoubleLine("Est. sold / day", FI.Number(s.soldPerDay), muted[1], muted[2], muted[3], 1, 1, 1)
  end
  if vendor then
    -- vendor pays in full; the AH pays what you'd sell for (cheapest listing or
    -- market, whichever is lower) minus its 5% cut
    local better = vendor >= (FI.Crafting:SellPrice(itemID) or it.mkt) * 0.95
    local r, g, b = muted[1], muted[2], muted[3]
    if better then r, g, b = FI.colors.up[1], FI.colors.up[2], FI.colors.up[3] end
    tooltip:AddDoubleLine(better and "Vendor (better than AH)" or "Vendor", FI.Money(vendor * count), r, g, b, 1, 1, 1)
  end
  addDisenchant(it.mkt, count)
  if it.imported and (not it.seen or it.imported > it.seen) then
    tooltip:AddLine(("|cff8b95a3From Auctionator, %s|r"):format(FI.Ago(it.imported)))
  else
    tooltip:AddLine(("|cff8b95a3Scanned %s|r"):format(FI.Ago(it.seen or realm.lastScan)))
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
