-- Goonberg Terminal: what your bank is worth, on the game's bank window.
-- A small panel under WoW's bank window shows the bank's value at AH prices (the
-- market you're viewing); hover it for item by item and your other characters'
-- banks. With a bag addon that replaces the bank window, the panel sits at the top
-- of the screen instead. Alt + drag moves it anywhere; the spot is remembered.
---@type string, GoonbergTerminal
local _, FI = ...
local BV = {}
FI.BankValue = BV
local W = FI.Widgets
local C = FI.colors

local function money(v) return FI.Money(math.floor((v or 0) + 0.5)) end
local function ago(t)
  local a = time() - (t or 0)
  if a < 3600 then return math.max(1, math.floor(a / 60)) .. " min ago" end
  if a < 86400 then return math.floor(a / 3600) .. " h ago" end
  return math.floor(a / 86400) .. " days ago"
end

-- Alt + left-drag moves `f`; the spot is kept in FI.settings[key] (TOPLEFT of the
-- screen). A plain drag does nothing, so the panel can't be knocked out of place.
function BV.AltMovable(f, key)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    if not IsAltKeyDown() then return end
    self.dragging = true
    GameTooltip_Hide()
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    if not self.dragging then return end
    self.dragging = false
    self:StopMovingOrSizing()
    if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end
    local left, top = self:GetLeft(), self:GetTop()
    if not left or not top then return end
    local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    FI.settings[key] = { x = math.floor(left * s + 0.5), y = math.floor(top * s - UIParent:GetHeight() + 0.5), moved = true }
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", FI.settings[key].x, FI.settings[key].y)
  end)
end

function BV:Build()
  if self.frame then return self.frame end
  -- the addon's own panel (the game's tooltip edge, gold)
  local f = W.Box(UIParent, C.panel, C.gold, 0.95)
  f:SetSize(230, 44)
  f:SetFrameStrata("HIGH")
  f.label = W.Text(f, 11, C.gold)
  f.label:SetPoint("TOPLEFT", 10, -8)
  f.label:SetText("Bank worth")
  f.value = W.Text(f, 13, C.text, true)
  f.value:SetPoint("TOPRIGHT", -10, -7)
  f.value:SetJustifyH("RIGHT")
  f.sub = W.Text(f, 10, C.muted)
  f.sub:SetPoint("BOTTOMLEFT", 10, 7)
  f.sub:SetPoint("RIGHT", -10, 0)
  f.sub:SetJustifyH("LEFT")
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self) BV:Tooltip(self) end)
  f:SetScript("OnLeave", GameTooltip_Hide)
  -- Alt + drag moves it; once moved it stays there instead of under the bank window
  BV.AltMovable(f, "bankValuePos")
  f:Hide()
  self.frame = f
  return f
end

-- Under the game's bank window when it's the one showing; otherwise on its own
function BV:Place()
  local f = self.frame
  local bank = _G.BankFrame
  f:ClearAllPoints()
  local p = FI.settings.bankValuePos
  if p and p.moved then
    -- you Alt-dragged it somewhere: it opens there from now on
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
    f.onBank = false
  elseif bank and bank:IsShown() then
    -- just under the window's art (its hit-rect insets mark the transparent edges)
    local l, _, _, b = 0, 0, 0, 0
    if bank.GetHitRectInsets then l, _, _, b = bank:GetHitRectInsets() end
    f:SetPoint("TOPLEFT", bank, "BOTTOMLEFT", (l or 0) + 4, (b or 0) + 2)
    f.onBank = true
  else
    if p then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
    f.onBank = false
  end
end

function BV:Update()
  local f = self.frame
  if not f then return end
  local total, list, _, unpriced = FI.Ledger:BankValue()
  f.value:SetText(total and FI.Coins(total) or "|cff8b95a3counting...|r")
  local n = list and #list or 0
  f.sub:SetText(("%d kind%s of item at %s prices%s"):format(n, n == 1 and "" or "s", FI:MarketName(),
    (unpriced or 0) > 0 and ("  ·  " .. unpriced .. " unpriced") or ""))
  f:SetWidth(math.max(230, f.label:GetStringWidth() + f.value:GetStringWidth() + 40, f.sub:GetStringWidth() + 24))
end

function BV:Show()
  if FI.settings.bankValue == false then return end
  self:Build()
  self:Place()
  self:Update()
  self.frame:Show()
end

function BV:Hide()
  if self.frame then self.frame:Hide(); GameTooltip_Hide() end
end

-- the bank item by item, and your other characters' banks
function BV:Tooltip(owner)
  local L = FI.Ledger
  local total, list, t, unpriced, bound = L:BankValue()
  local soft = C.soft
  local function line(l, v, c)
    c = c or C.text
    GameTooltip:AddDoubleLine(l, v, soft[1], soft[2], soft[3], c[1], c[2], c[3])
  end
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
  GameTooltip:AddLine("Your bank at AH prices (" .. FI:MarketName() .. ")")
  if not total then
    GameTooltip:AddLine("Counting what's in it...", 0.82, 0.82, 0.82, true)
  else
    for i = 1, math.min(12, #list) do
      local e = list[i]
      line(("%s%s"):format(e.n > 1 and (e.n .. "x ") or "", FI:ItemName(e.id) or ("item " .. e.id)), money(e.value))
    end
    if #list > 12 then line(("and %d more"):format(#list - 12), "") end
    line("Total", money(total), C.gold)
    if (unpriced or 0) > 0 then
      GameTooltip:AddLine(("%d kind%s of item without an AH price (not counted)."):format(unpriced, unpriced == 1 and "" or "s"), 0.55, 0.58, 0.64, true)
    end
    if (bound or 0) > 0 then
      GameTooltip:AddLine(("%d soulbound item%s (can't be sold, not counted)."):format(bound, bound == 1 and "" or "s"), 0.55, 0.58, 0.64, true)
    end
    if t and time() - t > 60 then GameTooltip:AddLine("As of " .. ago(t) .. ".", 0.55, 0.58, 0.64) end
  end
  local me, others, sum = UnitName("player"), {}, 0
  for _, b in ipairs(L:Banks()) do
    if b.who ~= me then others[#others + 1] = b; sum = sum + b.total end
  end
  if #others > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Your other characters' banks")
    for _, b in ipairs(others) do line("  " .. b.who, money(b.total)) end
    line("All banks", money(sum + (total or 0)), C.gold)
  end
  GameTooltip:AddLine("|cff8b95a3Prices from the market picked in Goonberg (Horde/Alliance or Neutral AH). Alt + drag to move it (/goon bank reset puts it back). /goon bank off hides this.|r", 1, 1, 1, true)
  GameTooltip:Show()
end

FI:On("BANKFRAME_OPENED", function()
  BV:Show()
  -- (a bag addon may show its own bank window a moment later: place it again then)
  C_Timer.After(0.4, function() if BV.frame and BV.frame:IsShown() then BV:Place(); BV:Update() end end)
end)
FI:On("BANKFRAME_CLOSED", function() BV:Hide() end)
for _, e in ipairs({ "FI_BANK_CHANGED", "FI_MARKET_CHANGED", "FI_SCAN_DONE", "FI_DATA_MERGED" }) do
  FI:On(e, function() if BV.frame and BV.frame:IsShown() then BV:Update() end end)
end
