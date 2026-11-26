-- Goonberg Terminal: the Quick sell panel, beside the Auction House.
-- One row per sell preset (Sell.lua): click it to post that item at its saved price
-- and stack size, no typing, no splitting stacks. Save keeps the item in the AH's
-- Sell view with the price, quantity and duration you set there. Shift + right-click
-- a row removes it. Alt + drag moves the panel; /goon sell panel off hides it.
---@type string, GoonbergTerminal
local _, FI = ...
local SP = {}
FI.SellPanel = SP
local W = FI.Widgets
local C = FI.colors
local S = FI.Sell

local WIDTH, ROW, PAD, HEAD = 230, 30, 6, 24

local function ahFrame()
  local f = _G.AuctionHouseFrame or _G.AuctionFrame
  return f and f:IsShown() and f or nil
end

local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(ROW)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(ROW - 6, ROW - 6)
  r.icon:SetPoint("LEFT", 2, 0)
  r.name = W.Text(r, 12, C.text)
  r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -1)
  r.name:SetPoint("RIGHT", -52, 0)
  r.name:SetJustifyH("LEFT")
  r.name:SetWordWrap(false)
  r.info = W.Text(r, 11, C.soft, true)
  r.info:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 1)
  r.info:SetPoint("RIGHT", -52, 0)
  r.info:SetJustifyH("LEFT")
  r.info:SetWordWrap(false)
  r.have = W.Text(r, 11, C.muted, true)
  r.have:SetPoint("RIGHT", -4, 0)
  r.have:SetJustifyH("RIGHT")
  W.RowHover(r)
  r:SetScript("OnClick", function(self, button)
    if not self.id then return end
    if button == "RightButton" then
      if IsShiftKeyDown() then S:Remove(self.id) end
      return
    end
    S:PostPreset(self.id)
  end)
  r:HookScript("OnEnter", function(self)
    if not self.id then return end
    local p = S:Presets()[self.id]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) else GameTooltip:AddLine(FI:ItemName(self.id)) end
    if p then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(("|cffffd100Click:|r post %s at %s each (%s)"):format(
        p.qty and ("a stack of " .. p.qty) or "all you have", FI.Money(p.price), S.DurText(p.dur)), 1, 1, 1, true)
      GameTooltip:AddLine("|cff8b95a3Shift + right-click removes it. To change it, set it up in the Sell view and press Save.|r", 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  r:HookScript("OnLeave", GameTooltip_Hide)
  return r
end

function SP:Build()
  if self.frame then return self.frame end
  local f = W.Box(UIParent, C.panel, C.gold, 0.95)
  f:SetWidth(WIDTH)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f.title = W.Text(f, 12, C.gold)
  f.title:SetPoint("TOPLEFT", PAD + 2, -PAD - 1)
  f.title:SetText("Quick sell")
  f.save = W.Button(f, "Save", 56, 22)
  f.save:SetPoint("TOPRIGHT", -PAD, -2)
  f.save:SetScript("OnClick", function() S:SaveCommand("") end)
  f.save:SetScript("OnEnter", function(self)
    if self.Refresh then self:Refresh() end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Save the Sell view as a preset")
    GameTooltip:AddLine("Put an item in the AH's Sell slot and set its price each, quantity (the stack size you want) and duration, then press Save. After that one click on its row posts it.", 0.82, 0.82, 0.82, true)
    GameTooltip:AddLine("|cff8b95a3Or type /goon sell save Linen Cloth 25s x5|r", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  f.save:SetScript("OnLeave", function(self)
    if self.Refresh then self:Refresh() end
    GameTooltip_Hide()
  end)
  f.empty = W.Text(f, 11, C.muted)
  f.empty:SetPoint("TOPLEFT", PAD + 2, -HEAD - 4)
  f.empty:SetPoint("RIGHT", -PAD, 0)
  f.empty:SetJustifyH("LEFT")
  f.empty:SetText("Set up an item in the Sell view (price each, how many per post), then press Save. Click its row here to post it again.")
  f.rows = {}
  FI.BankValue.AltMovable(f, "sellPanelPos")
  f:Hide()
  self.frame = f
  return f
end

-- Unless you've moved it: to the left of the AH, top edges level (Goonberg's own
-- window docks on the right). An AH against the left edge has no room there, so the
-- panel goes under it instead, below the Buy / Sell / Auctions tabs.
function SP:Place(ah)
  local f = self.frame
  f:ClearAllPoints()
  local p = FI.settings.sellPanelPos
  if p and p.moved then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
    return
  end
  local left = ah:GetLeft()
  local room = left and left * ah:GetEffectiveScale() / f:GetEffectiveScale() or 0
  if room >= WIDTH + 8 then
    f:SetPoint("TOPRIGHT", ah, "TOPLEFT", -4, 0)
  else
    f:SetPoint("TOPLEFT", ah, "BOTTOMLEFT", 0, -34)
  end
end

function SP:Update()
  local ah = ahFrame()
  if not ah or not FI.ahOpen or FI.settings.sellPanel == false then
    if self.frame then self.frame:Hide() end
    return
  end
  local f = self:Build()
  local list = S:Sorted()
  for i, item in ipairs(list) do
    local r = f.rows[i]
    if not r then
      r = makeRow(f)
      r:SetPoint("TOPLEFT", PAD, -HEAD - (i - 1) * ROW)
      r:SetPoint("RIGHT", -PAD, 0)
      f.rows[i] = r
    end
    local p = item.p
    local _, total = S.Find(item.id)
    r.id = item.id
    r.icon:SetTexture(FI:ItemIcon(item.id))
    r.icon:SetDesaturated(total == 0)
    r.name:SetText(item.name)
    r.info:SetText(("%s each  %s  %s"):format(FI.Money(p.price), p.qty and ("x" .. p.qty) or "all", S.DurText(p.dur)))
    r.have:SetText(total > 0 and ("have " .. FI.Number(total)) or "none")
    r:SetAlpha(total > 0 and 1 or 0.5)
    r:Show()
  end
  for i = #list + 1, #f.rows do
    f.rows[i].id = nil
    f.rows[i]:Hide()
  end
  f.empty:SetShown(#list == 0)
  local body = #list > 0 and #list * ROW or (f.empty:GetStringHeight() + 8)
  f:SetHeight(HEAD + body + PAD)
  if not f:IsShown() then self:Place(ah) end
  f:Show()
end

local function later() FI:Debounce("sellPanel", 0.1, function() SP:Update() end) end
for _, e in ipairs({ "FI_SELL_PRESETS", "BAG_UPDATE_DELAYED", "FI_ITEM_LOADED", "FI_AH_CLOSED" }) do
  FI:On(e, later)
end
FI:On("FI_AH_OPEN", function() C_Timer.After(0.5, function() SP:Update() end) end)
