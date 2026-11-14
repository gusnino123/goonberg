-- Goonberg Terminal: main window (header, tabs, scan button, docking beside the AH)
local _, FI = ...
local UI = { tabs = {} }
FI.UI = UI
local W = FI.Widgets
local C = FI.colors

UI.WIDTH, UI.HEIGHT = 1060, 640
UI.MIN_W, UI.MIN_H = 900, 600
UI.HEADER = 48

local function savePosition(f)
  if f.docked then return end
  local point, _, relPoint, x, y = f:GetPoint(1)
  FI.db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

local function restorePosition(f)
  f:ClearAllPoints()
  local p = FI.db.window
  if p and p.point then
    f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
  else
    f:SetPoint("CENTER")
  end
  f.docked = false
end

-- The logo: the goblin's face in a gold frame (gold coin if the model can't load)
local function logo(parent)
  local f = W.Box(parent, C.bg, C.gold)
  f:SetSize(34, 34)
  local coin = f:CreateTexture(nil, "ARTWORK")
  coin:SetPoint("TOPLEFT", 1, -1)
  coin:SetPoint("BOTTOMRIGHT", -1, 1)
  coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  coin:Hide()
  local face = W.Goblin(f, true, function() coin:Show() end)
  face:SetPoint("TOPLEFT", 1, -1)
  face:SetPoint("BOTTOMRIGHT", -1, 1)
  f:SetScript("OnShow", face.Load)
  f.face = face
  return f
end

function UI:Build()
  if self.frame then return self.frame end
  local f = W.Box(UIParent, C.bg, C.border)
  self.frame = f
  -- saved size, never bigger than the screen
  local size = FI.db.size or {}
  local maxW, maxH = UIParent:GetWidth() or self.WIDTH, UIParent:GetHeight() or self.HEIGHT
  local w = math.max(self.MIN_W, math.min(size.w or self.WIDTH, maxW - 20))
  local h = math.max(self.MIN_H, math.min(size.h or self.HEIGHT, maxH - 20))
  f:SetSize(w, h)
  f:SetScale(FI.db.scale or 1)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(self.MIN_W, self.MIN_H, 2400, 1500)
  elseif f.SetMinResize then
    f:SetMinResize(self.MIN_W, self.MIN_H)
  end
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()
  W.Shadow(f)
  _G.GoonbergTerminalFrame = f
  tinsert(UISpecialFrames, "GoonbergTerminalFrame") -- Escape closes it

  -- Header
  local head = W.Box(f, C.side, C.border)
  head:SetPoint("TOPLEFT", 0, 0)
  head:SetPoint("TOPRIGHT", 0, 0)
  head:SetHeight(self.HEADER)
  head:EnableMouse(true)
  head:RegisterForDrag("LeftButton")
  head:SetScript("OnDragStart", function() f.docked = false; f:StartMoving() end)
  head:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)

  local mark = logo(head)
  mark:SetPoint("LEFT", 16, 0)
  mark.face.Load()
  local title = W.Text(head, 15, C.text, false, "")
  title:SetText("GOONBERG")
  title:SetPoint("LEFT", mark, "RIGHT", 10, 6)
  local sub = W.Text(head, 10, C.gold)
  sub:SetText("TERMINAL")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)

  local keys = { Overview = "overview", Deals = "deals", Chart = "chart", Crafting = "craft", ["P&L"] = "pnl" }
  self.tabLabels = { overview = "Overview", deals = "Deals", chart = "Chart", craft = "Crafting", pnl = "P&L" }
  local tabs = W.Choice(head, { "Overview", "Deals", "Chart", "Crafting", "P&L" }, "tab", function(v) UI:Show(keys[v]) end, self.HEADER - 1)
  tabs:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 170, 1)
  for _, b in pairs(tabs.buttons) do b:SetWidth(b:GetWidth() + 12) end
  -- re-space after widening
  local x = 0
  for _, name in ipairs({ "Overview", "Deals", "Chart", "Crafting", "P&L" }) do
    local b = tabs.buttons[name]
    b:ClearAllPoints(); b:SetPoint("LEFT", tabs, "LEFT", x, 0)
    x = x + b:GetWidth()
  end
  tabs:SetWidth(x)
  self.tabBar = tabs

  local close = CreateFrame("Button", nil, head, "UIPanelCloseButton")
  close:SetPoint("RIGHT", -6, 0)
  close:SetScript("OnClick", function() f:Hide() end)

  local scan = W.Button(head, "Scan AH", 96, 30, "gold")
  scan:SetPoint("RIGHT", close, "LEFT", -8, 0)
  scan:SetScript("OnClick", function() FI.Scanner:Start(true) end)
  self.scanButton = scan

  local status = W.Text(head, 11, C.muted)
  status:SetPoint("RIGHT", scan, "LEFT", -12, 0)
  status:SetJustifyH("RIGHT")
  self.status = status
  local dot = W.Tex(head, C.up)
  dot:SetSize(7, 7)
  dot:SetPoint("RIGHT", status, "LEFT", -6, 0)
  self.statusDot = dot

  -- Body: tabs fill this
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 1, -self.HEADER)
  body:SetPoint("BOTTOMRIGHT", -1, 1)
  self.body = body

  self.tabs.overview = FI.OverviewTab:Build(body)
  self.tabs.chart = FI.ChartTab:Build(body)
  self.tabs.deals = FI.DealsTab:Build(body)
  self.tabs.pnl = FI.PnLTab:Build(body)
  self.tabs.craft = FI.CraftTab:Build(body)

  f:SetScript("OnShow", function() UI:UpdateStatus() end)
  -- refresh the status line every few seconds (cooldown countdown)
  f.elapsed = 0
  f:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 1 then self.elapsed = 0; UI:UpdateStatus() end
  end)

  -- resize grip, bottom-right corner
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetFrameLevel(f:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    FI.db.size = { w = math.floor(f:GetWidth() + 0.5), h = math.floor(f:GetHeight() + 0.5) }
    savePosition(f)
    UI:Relayout()
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize")
    GameTooltip:AddLine("|cff8b95a3/goon scale 0.9 makes everything smaller|r", 1, 1, 1)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", GameTooltip_Hide)
  -- redraw while resizing (charts and columns depend on the size)
  f:SetScript("OnSizeChanged", function() FI:Debounce("relayout", 0.1, function() UI:Relayout() end) end)

  restorePosition(f)
  self:Show("overview", true)
  return f
end

function UI:UpdateStatus()
  if not self.frame then return end
  local S = FI.Scanner
  local realm = FI:Realm()
  local text, color
  if S.state == "waiting" then
    text, color = "Waiting for the Auction House...", C.gold
  elseif S.state == "processing" then
    text, color = ("Scanning %d%%"):format(math.floor((S:Progress() or 0) * 100)), C.gold
  else
    local scans = realm.scans or 0
    local shared = realm.lastShared
    if shared and shared.t == realm.lastScan then
      text = ("Last scan %s by %s (guild)"):format(FI.Ago(realm.lastScan), shared.from)
    else
      text = ("Last scan %s  ·  %d scans"):format(FI.Ago(realm.lastScan), scans)
    end
    local q = FI.Sync and FI.Sync:QueueLength() or 0
    if q > 0 then text = text .. ("  ·  sharing with guild (%d)"):format(q) end
    color = (realm.lastScan > 0 and time() - realm.lastScan < 3600) and C.up or C.muted
  end
  self.status:SetText(text)
  self.statusDot:SetColorTexture(color[1], color[2], color[3], 1)

  local b = self.scanButton
  if S.state ~= "idle" then
    b:SetLabel("Scanning")
    b:Disable()
  elseif not FI.ahOpen then
    b:SetLabel("Scan AH")
    b:Disable()
  else
    local left = S:CooldownLeft()
    if left > 0 then
      b:SetLabel(("Scan in %d:%02d"):format(math.floor(left / 60), left % 60))
      b:Disable()
    else
      b:SetLabel("Scan AH")
      b:Enable()
    end
  end
end

-- Redraw the current tab at the window's new size
function UI:Relayout()
  if not self.frame or not self.frame:IsShown() then return end
  local t = self.current and self.tabs[self.current]
  if t and t.Refresh then t:Refresh() end
end

function UI:SetScale(scale)
  FI.db.scale = scale
  if self.frame then self.frame:SetScale(scale) end
end

function UI:ResetSize()
  FI.db.size, FI.db.scale, FI.db.window = nil, nil, nil
  if self.frame then
    self.frame:SetScale(1)
    self.frame:SetSize(math.min(self.WIDTH, (UIParent:GetWidth() or self.WIDTH) - 20), math.min(self.HEIGHT, (UIParent:GetHeight() or self.HEIGHT) - 20))
    restorePosition(self.frame)
  end
end

function UI:Show(tab, noOpen)
  self:Build()
  tab = tab or self.current or "overview"
  self.current = tab
  for name, t in pairs(self.tabs) do t:SetShown(name == tab) end
  self.tabBar:Select(self.tabLabels[tab])
  if not noOpen then self.frame:Show() end
  if self.tabs[tab].Refresh then self.tabs[tab]:Refresh() end
end

function UI:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function UI:ShowItem(itemID)
  self:Build()
  if itemID then FI.ChartTab:SetItem(itemID) end
  self:Show("chart")
end

-- Open beside the Auction House when it opens; go back to the saved spot when it closes
local function ahFrame()
  return _G.AuctionHouseFrame or _G.AuctionFrame
end

FI:On("FI_AH_OPEN", function()
  if not FI.settings.dock then return end
  local f = UI:Build()
  local ah = ahFrame()
  if ah and ah:GetRight() then
    local room = (UIParent:GetRight() or 0) - ah:GetRight()
    f:ClearAllPoints()
    if room >= f:GetWidth() * f:GetEffectiveScale() / UIParent:GetEffectiveScale() then
      f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
    else
      f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    end
    f.docked = true
  end
  UI:Show()
end)

FI:On("FI_AH_CLOSED", function()
  if UI.frame and UI.frame.docked then
    UI.frame:Hide()
    restorePosition(UI.frame)
  end
  UI:UpdateStatus()
end)

for _, e in ipairs({ "FI_SCAN_STATE", "FI_SCAN_PROGRESS" }) do
  FI:On(e, function() UI:UpdateStatus() end)
end

for _, e in ipairs({ "FI_SCAN_DONE", "FI_DATA_MERGED" }) do
  FI:On(e, function()
    if UI.frame and UI.frame:IsShown() and UI.current and UI.tabs[UI.current].Refresh then
      UI.tabs[UI.current]:Refresh()
    end
  end)
end
