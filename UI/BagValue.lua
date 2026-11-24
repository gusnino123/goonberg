-- Goonberg Terminal: what your bags are worth, beside the game's backpack.
-- A small panel next to WoW's own backpack window shows what your bags would fetch
-- at AH prices (the market you're viewing; soulbound items don't count). It only
-- appears with the game's default bags, not a bag addon's. Alt + drag moves it.
---@type string, GoonbergTerminal
local _, FI = ...
local BG = {}
FI.BagValue = BG
local W = FI.Widgets
local C = FI.colors

-- the game's backpack window, when it's open (bag frames are reused, so look each time)
local function backpack()
  for i = 1, (_G.NUM_CONTAINER_FRAMES or 13) do
    local cf = _G["ContainerFrame" .. i]
    if cf and cf:IsShown() and cf:GetID() == 0 then return cf end
  end
end

function BG:Build()
  if self.frame then return self.frame end
  local f = W.Box(UIParent, C.panel, C.gold, 0.95)
  f:SetSize(150, 26)
  f:SetFrameStrata("HIGH")
  f.label = W.Text(f, 11, C.gold)
  f.label:SetPoint("LEFT", 8, 0)
  f.label:SetText("Bags worth")
  f.value = W.Text(f, 12, C.text, true)
  f.value:SetPoint("RIGHT", -8, 0)
  f.value:SetJustifyH("RIGHT")
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("Your bags at AH prices (" .. FI:MarketName() .. ")")
    GameTooltip:AddLine("Only things you could sell: not soulbound items, not items without an AH price.", 0.82, 0.82, 0.82, true)
    GameTooltip:AddLine("|cff8b95a3Alt + drag to move it (/goon bags reset puts it back). /goon bags off hides this.|r", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", GameTooltip_Hide)
  FI.BankValue.AltMovable(f, "bagValuePos")
  f:Hide()
  self.frame = f
  return f
end

-- to the left of the backpack, top edges level, unless you've moved it
function BG:Place(bp)
  local f = self.frame
  f:ClearAllPoints()
  local p = FI.settings.bagValuePos
  if p and p.moved then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
  else
    local l, _, t = 0, 0, 0
    if bp.GetHitRectInsets then l, _, t = bp:GetHitRectInsets() end
    f:SetPoint("TOPRIGHT", bp, "TOPLEFT", (l or 0) - 2, -(t or 0) - 4)
  end
end

function BG:Update()
  local f = self.frame
  if not f then return end
  f.value:SetText(FI.Coins(FI.Ledger:BagValue()))
  f:SetWidth(math.max(150, f.label:GetStringWidth() + f.value:GetStringWidth() + 28))
end

-- show or hide it to match the backpack
function BG:Refresh()
  local bp = FI.settings.bagValue ~= false and backpack()
  if not bp then
    if self.frame then self.frame:Hide() end
    return
  end
  self:Build()
  self:Place(bp)
  self:Update()
  self.frame:Show()
end

-- bag frames get their bag number as they open, so check a moment after
local function soon() C_Timer.After(0, function() BG:Refresh() end) end
for i = 1, (_G.NUM_CONTAINER_FRAMES or 13) do
  local cf = _G["ContainerFrame" .. i]
  if cf then
    cf:HookScript("OnShow", soon)
    cf:HookScript("OnHide", soon)
  end
end
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "FI_MARKET_CHANGED", "FI_SCAN_DONE", "FI_DATA_MERGED" }) do
  FI:On(e, function() if BG.frame and BG.frame:IsShown() then BG:Update() end end)
end
