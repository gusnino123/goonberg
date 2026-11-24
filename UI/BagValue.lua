-- Goonberg Terminal: what your bags are worth, beside the game's backpack.
-- A small panel by WoW's own backpack window (or the Combined Backpack) shows what your bags would fetch
-- at AH prices (the market you're viewing; soulbound items don't count). It only
-- appears with the game's default bags, not a bag addon's. Alt + drag moves it.
---@type string, GoonbergTerminal
local _, FI = ...
local BG = {}
FI.BagValue = BG
local W = FI.Widgets
local C = FI.colors

-- the game's backpack window, when it's open, and whether it's the Combined Backpack
-- (all bags in one window). Separate bag frames are reused, so look each time.
local function backpack()
  local combined = _G.ContainerFrameCombinedBags
  if combined and combined:IsShown() then return combined, true end
  for i = 1, (_G.NUM_CONTAINER_FRAMES or 13) do
    local cf = _G["ContainerFrame" .. i]
    if cf and cf:IsShown() and cf:GetID() == 0 then return cf, false end
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

-- Unless you've moved it: just above the Combined Backpack, right edges level (beside
-- it would cover the other bag windows); to the left of a separate backpack, top edges
-- level (other bags stack above that one)
function BG:Place(bp, combined)
  local f = self.frame
  f:ClearAllPoints()
  local p = FI.settings.bagValuePos
  local l, r, t = 0, 0, 0
  if bp.GetHitRectInsets then l, r, t = bp:GetHitRectInsets() end
  if p and p.moved then
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p.x, p.y)
  elseif combined then
    f:SetPoint("BOTTOMRIGHT", bp, "TOPRIGHT", -(r or 0) - 4, -(t or 0) + 2)
  else
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
  local bp, combined
  if FI.settings.bagValue ~= false then bp, combined = backpack() end
  if not bp then
    if self.frame then self.frame:Hide() end
    return
  end
  self:Build()
  self:Place(bp, combined)
  self:Update()
  self.frame:Show()
end

-- bag frames get their bag number as they open, so check a moment after
local function soon() C_Timer.After(0, function() BG:Refresh() end) end
local hooked = {}
local function hookBags()
  local frames = { _G.ContainerFrameCombinedBags }
  for i = 1, (_G.NUM_CONTAINER_FRAMES or 13) do frames[#frames + 1] = _G["ContainerFrame" .. i] end
  for _, cf in pairs(frames) do
    if cf and not hooked[cf] then
      hooked[cf] = true
      cf:HookScript("OnShow", soon)
      cf:HookScript("OnHide", soon)
    end
  end
end
hookBags()
FI:On("PLAYER_LOGIN", hookBags) -- (in case a bag frame only exists once the UI is up)
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "FI_MARKET_CHANGED", "FI_SCAN_DONE", "FI_DATA_MERGED" }) do
  FI:On(e, function() if BG.frame and BG.frame:IsShown() then BG:Update() end end)
end
