-- Goonberg Terminal: round button under the minimap (click to open the terminal)
---@type string, GoonbergTerminal
local _, FI = ...
local W = FI.Widgets

local button

local function place()
  button:ClearAllPoints()
  local p = FI.db.minimap
  if p and p.x then
    button:SetPoint("CENTER", Minimap, "CENTER", p.x, p.y)
  else
    -- default: just below the minimap
    button:SetPoint("TOP", Minimap, "BOTTOM", 0, -6)
  end
end

local function showTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine("|cffe8b84aGoonberg Terminal|r")
  local realm = FI:Realm()
  local level = FI.History.IndexLevel(realm)
  if level then
    local ch = FI.History.IndexChange(realm, time(), 86400)
    GameTooltip:AddDoubleLine("Goonberg Index", ("%.1f  %s"):format(level, FI.ColoredPercent(ch)), 0.76, 0.79, 0.83, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Last scan", FI.Ago(realm.lastScan), 0.76, 0.79, 0.83, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("|cff8b95a3Click|r open or close the terminal", 1, 1, 1)
  GameTooltip:AddLine("|cff8b95a3Right-click|r your P&L", 1, 1, 1)
  GameTooltip:AddLine("|cff8b95a3Drag|r move this button", 1, 1, 1)
  GameTooltip:Show()
end

local function build()
  if button or not Minimap then return end
  button = CreateFrame("Button", "GoonbergTerminalMinimapButton", Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(22, 22)
  bg:SetPoint("CENTER")

  -- gold coin underneath; the goblin's face goes on top when his model loads
  local coin = button:CreateTexture(nil, "ARTWORK")
  coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  coin:SetSize(20, 20)
  coin:SetPoint("CENTER")
  if coin.SetMask then
    coin:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  end

  local face = W.Goblin(button, true, nil)
  face:SetSize(19, 19)
  face:SetPoint("CENTER")
  face:SetFrameLevel(button:GetFrameLevel() + 1)
  face:EnableMouse(false)
  face.Load()

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  -- the border sits on its own frame so it draws over the goblin model
  local top = CreateFrame("Frame", nil, button)
  top:SetAllPoints()
  top:SetFrameLevel(button:GetFrameLevel() + 2)
  border:SetParent(top)

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then FI.UI:Show("pnl") else FI.UI:Toggle() end
  end)
  button:SetScript("OnEnter", showTooltip)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:SetScript("OnDragStart", function(self)
    GameTooltip_Hide()
    self:SetScript("OnUpdate", function()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      local mx, my = Minimap:GetCenter()
      local x, y = cx / scale - mx, cy / scale - my
      self:ClearAllPoints()
      self:SetPoint("CENTER", Minimap, "CENTER", x, y)
      FI.db.minimap = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  place()
end

function FI:SetMinimapButton(show)
  FI.settings.minimapButton = show
  if show then
    build()
    if button then place(); button:Show() end
  elseif button then
    button:Hide()
  end
end

FI:On("PLAYER_LOGIN", function()
  if FI.settings.minimapButton == nil then FI.settings.minimapButton = true end
  FI:SetMinimapButton(FI.settings.minimapButton)
end)
