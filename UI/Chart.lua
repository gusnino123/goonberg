-- Goonberg Terminal: chart tab (watchlist, candlestick chart, market depth, alerts)
local _, FI = ...
local T = { tf = "1W" }
FI.ChartTab = T
local W = FI.Widgets
local C = FI.colors
local H

local LEFT_W, RIGHT_W = 214, 256
local PAD = 18
local AXIS_W = 70
local PLOT_H, VOL_H = 250, 48

local TF = {
  ["15M"] = { span = 900, n = 3, label = "past 15 minutes", start = "15m ago", chg = "c15", sold = "sold15" },
  ["1H"] = { span = 3600, n = 12, label = "past hour", start = "1h ago", chg = "c1", sold = "sold1" },
  ["6H"] = { span = 6 * 3600, n = 24, label = "past 6 hours", start = "6h ago", chg = "c6", sold = "sold6" },
  ["12H"] = { span = 12 * 3600, n = 24, label = "past 12 hours", start = "12h ago", chg = "c12", sold = "sold12" },
  ["1D"] = { span = 86400, n = 24, label = "past 24 hours", start = "24h ago", chg = "c24", sold = "sold24" },
  ["1W"] = { span = 7 * 86400, n = 28, label = "past 7 days", start = "7d ago", chg = "c7", sold = "sold7" },
  ["1M"] = { span = 30 * 86400, n = 30, label = "past 30 days", start = "30d ago" },
  ["All"] = { n = 32, label = "all history", start = "first scan" },
}

-- Shift-clicking an item while one of our edit boxes has focus puts the link there
local focused
local function trackFocus(e)
  e:HookScript("OnEditFocusGained", function(self) focused = self end)
  e:HookScript("OnEditFocusLost", function(self) if focused == self then focused = nil end end)
end
if hooksecurefunc then
  hooksecurefunc("ChatEdit_InsertLink", function(link)
    if focused and focused:HasFocus() and link then focused:SetText(link) end
  end)
end

-- ---------------------------------------------------------------------------
-- Watchlist (left)
-- ---------------------------------------------------------------------------
local function buildWatchlist(tab)
  local side = W.Box(tab, C.side, C.border)
  side:SetPoint("TOPLEFT", 0, 0)
  side:SetPoint("BOTTOMLEFT", 0, 0)
  side:SetWidth(LEFT_W)

  local head = W.Heading(side, "WATCHLIST")
  head:SetPoint("TOPLEFT", 14, -14)

  local add = W.EditBox(side, LEFT_W - 28, "Add item: name or shift-click")
  add:SetPoint("TOPLEFT", 14, -34)
  trackFocus(add)
  add:SetScript("OnEnterPressed", function(self)
    local id = FI:FindItem(self:GetText())
    if id then
      FI.Alerts:Watch(id)
      T:SetItem(id)
      self:SetText("")
      self:ClearFocus()
    else
      FI:Print("Couldn't find \"%s\". Shift-click the item, or scan the AH first.", self:GetText())
    end
  end)

  local listHolder = CreateFrame("Frame", nil, side)
  listHolder:SetPoint("TOPLEFT", 0, -70)
  listHolder:SetPoint("BOTTOMRIGHT", 0, 0)

  local list = W.List(listHolder, 24, 44, function(parent)
    local r = CreateFrame("Button", nil, parent)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
    r.bg:SetAllPoints()
    r.line = W.Tex(r, C.border, 1, "BORDER")
    r.line:SetPoint("TOPLEFT"); r.line:SetPoint("TOPRIGHT"); r.line:SetHeight(1)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(26, 26)
    r.icon:SetPoint("LEFT", 12, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = W.Text(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
    r.name:SetPoint("RIGHT", -60, 0)
    r.price = W.Text(r, 12, C.gold, true)
    r.price:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 0)
    r.chg = W.Text(r, 12, C.up, true)
    r.chg:SetPoint("RIGHT", -12, 0)
    r.chg:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self) if not self.on then self.bg:SetAlpha(0.5) end end)
    r:SetScript("OnLeave", function(self) if not self.on then self.bg:SetAlpha(0) end end)
    r:SetScript("OnClick", function(self, button)
      if button == "RightButton" then FI.Alerts:Unwatch(self.itemID)
      elseif IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(FI:ItemLink(self.itemID))
      else T:SetItem(self.itemID) end
    end)
    return r
  end, function(r, i)
    local id = T.watch[i]
    r.itemID = id
    r.on = id == T.itemID
    r.bg:SetAlpha(r.on and 1 or 0)
    r.icon:SetTexture(FI:ItemIcon(id))
    r.name:SetText(FI:ItemName(id))
    local it = FI:Realm().items[id]
    if it and it.mkt then
      local s = H.Stats(it, time())
      r.price:SetText(FI.Money(it.mkt))
      r.chg:SetText(s.c7 and FI.Percent(s.c7) or "")
      local c = FI.ChangeColor(s.c7)
      r.chg:SetTextColor(c[1], c[2], c[3])
    else
      r.price:SetText("no data yet")
      r.chg:SetText("")
    end
  end)
  list:SetAllPoints(listHolder)
  tab.watchList = list

  local empty = W.Text(side, 11, C.muted)
  empty:SetPoint("TOPLEFT", 14, -82)
  empty:SetPoint("RIGHT", -14, 0)
  empty:SetWordWrap(true)
  empty:SetText("Add items to follow them here. Right-click an item to remove it.")
  tab.watchEmpty = empty
end

-- ---------------------------------------------------------------------------
-- Center: header, timeframe, chart, stats
-- ---------------------------------------------------------------------------
local function statBox(parent)
  local b = W.Box(parent, C.panel, C.border)
  b:SetHeight(50)
  b.label = W.Heading(b, "")
  b.label:SetPoint("TOPLEFT", 12, -9)
  b.value = W.Text(b, 15, C.text, true)
  b.value:SetPoint("BOTTOMLEFT", 12, 9)
  return b
end

local function buildCenter(tab)
  local center = CreateFrame("Frame", nil, tab)
  center:SetPoint("TOPLEFT", LEFT_W, 0)
  center:SetPoint("BOTTOMRIGHT", -RIGHT_W, 0)
  tab.center = center

  local icon = center:CreateTexture(nil, "ARTWORK")
  icon:SetSize(40, 40)
  icon:SetPoint("TOPLEFT", PAD, -PAD)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  tab.icon = icon

  local name = W.Text(center, 18, C.text)
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
  name:SetPoint("RIGHT", center, "RIGHT", -150, 0)
  tab.name = name

  local price = W.Text(center, 22, C.gold, true)
  price:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 12, -4)
  tab.price = price

  local pill = W.Box(center, C.up, C.up)
  pill:SetHeight(20)
  pill:SetPoint("LEFT", price, "RIGHT", 10, 0)
  pill.text = W.Text(pill, 12, C.bg, true)
  pill.text:SetPoint("CENTER")
  tab.pill = pill

  local tfLabel = W.Text(center, 11, C.muted)
  tfLabel:SetPoint("TOPLEFT", center, "TOPLEFT", PAD, -72)
  tfLabel:SetPoint("RIGHT", center, "RIGHT", -PAD, 0)
  tab.tfLabel = tfLabel

  local watchBtn = W.Button(center, "+ Watch", 96, 26, "pill")
  watchBtn:SetPoint("TOPRIGHT", -PAD, -PAD)
  watchBtn:SetScript("OnClick", function()
    if not T.itemID then return end
    if FI.Alerts:IsWatched(T.itemID) then FI.Alerts:Unwatch(T.itemID) else FI.Alerts:Watch(T.itemID) end
  end)
  tab.watchBtn = watchBtn

  -- (timeframes live in the chart's own top bar, so the title row never overlaps)
  tab.name:SetPoint("RIGHT", watchBtn, "LEFT", -12, 0)

  -- Interactive chart (UI/ChartView.lua)
  local view = FI.ChartView:Create(center, { preset = T.tf, onDraw = function(info) T:OnChartDrawn(info) end })
  view.box:SetPoint("TOPLEFT", PAD, -96)
  view.box:SetPoint("RIGHT", center, "RIGHT", -PAD, 0)
  view.box:SetHeight(360)
  tab.view = view
  tab.box = view.box
  local box = view.box

  -- Stats row
  local stats = {}
  local labels = { "HIGH", "LOW", "LISTED NOW", "EST. SOLD" }
  for i = 1, 4 do
    local s = statBox(center)
    s.label:SetText(labels[i])
    stats[i] = s
  end
  stats[1]:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -12)
  for i = 2, 4 do stats[i]:SetPoint("TOPLEFT", stats[i - 1], "TOPRIGHT", 10, 0) end
  center:SetScript("OnSizeChanged", function(self, w)
    local each = (w - PAD * 2 - 30) / 4
    for i = 1, 4 do stats[i]:SetWidth(each) end
  end)
  tab.stats = stats
end

-- ---------------------------------------------------------------------------
-- Right: depth and alerts
-- ---------------------------------------------------------------------------
local function buildRight(tab)
  local side = W.Box(tab, C.side, C.border)
  side:SetPoint("TOPRIGHT", 0, 0)
  side:SetPoint("BOTTOMRIGHT", 0, 0)
  side:SetWidth(RIGHT_W)

  local head = W.Heading(side, "MARKET DEPTH")
  head:SetPoint("TOPLEFT", 14, -16)
  tab.listed = W.Text(side, 11, C.muted)
  tab.listed:SetPoint("TOPRIGHT", -14, -16)
  tab.listed:SetJustifyH("RIGHT")

  local cols = { { "Price", "LEFT", 22 }, { "Qty", "RIGHT", -86 }, { "Total", "RIGHT", -22 } }
  for _, c in ipairs(cols) do
    local fs = W.Text(side, 10, C.muted)
    fs:SetText(c[1])
    if c[2] == "LEFT" then fs:SetPoint("TOPLEFT", c[3], -38) else fs:SetPoint("TOPRIGHT", c[3], -38); fs:SetJustifyH("RIGHT") end
  end

  tab.depthRows = {}
  for i = 1, 10 do
    local r = CreateFrame("Frame", nil, side)
    r:SetSize(RIGHT_W - 28, 22)
    r:SetPoint("TOPLEFT", 14, -52 - (i - 1) * 24)
    local bg = W.Tex(r, C.panel, 1, "BACKGROUND")
    bg:SetAllPoints()
    r.bar = W.Tex(r, C.down, 0.22, "BORDER")
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT")
    r.price = W.Text(r, 12, C.gold, true)
    r.price:SetPoint("LEFT", 8, 0)
    r.qty = W.Text(r, 12, C.text, true)
    r.qty:SetPoint("RIGHT", -72, 0)
    r.qty:SetJustifyH("RIGHT")
    r.cum = W.Text(r, 12, C.muted, true)
    r.cum:SetPoint("RIGHT", -8, 0)
    r.cum:SetJustifyH("RIGHT")
    tab.depthRows[i] = r
  end
  tab.wall = W.Text(side, 11, C.soft)
  tab.wall:SetPoint("TOPLEFT", 14, -52 - 10 * 24 - 6)
  tab.wall:SetPoint("RIGHT", -14, 0)
  tab.wall:SetWordWrap(true)

  -- Alerts
  local box = W.Box(side, C.panel, C.border)
  box:SetPoint("BOTTOMLEFT", 14, 14)
  box:SetPoint("BOTTOMRIGHT", -14, 14)
  box:SetHeight(176)
  local ah = W.Heading(box, "PRICE ALERTS")
  ah:SetPoint("TOPLEFT", 12, -12)

  local function alertRow(label, dir, y)
    local fs = W.Text(box, 12, C.text)
    fs:SetText(label)
    fs:SetPoint("TOPLEFT", 12, y - 6)
    local e = W.EditBox(box, 96, "e.g. 3g50s")
    e:SetPoint("TOPRIGHT", -12, y)
    e:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
      if not T.itemID then return end
      local text = self:GetText()
      if text == "" then
        FI.Alerts:SetAlert(T.itemID, dir, nil)
      else
        local copper = FI.ParseMoney(text)
        if not copper then FI:Print("Couldn't read \"%s\". Try 3g50s or 3.5.", text); return end
        FI.Alerts:SetAlert(T.itemID, dir, copper)
      end
      T:Refresh()
    end)
    return e
  end
  tab.belowBox = alertRow("Notify below", "below", -34)
  tab.aboveBox = alertRow("Notify above", "above", -66)

  tab.alertState = W.Text(box, 11, C.muted)
  tab.alertState:SetPoint("TOPLEFT", 12, -102)
  tab.alertState:SetPoint("RIGHT", -12, 0)
  tab.alertState:SetWordWrap(true)
  local hint = W.Text(box, 10, C.muted)
  hint:SetPoint("BOTTOMLEFT", 12, 12)
  hint:SetPoint("RIGHT", -12, 0)
  hint:SetWordWrap(true)
  hint:SetText("Checked on every scan against the lowest price. Enter to save, clear the box to remove.")
end

-- ---------------------------------------------------------------------------
function T:Build(parent)
  H = FI.History
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab
  self.watch = {}
  buildWatchlist(tab)
  buildCenter(tab)
  buildRight(tab)
  tab.Refresh = function() T:Refresh() end
  return tab
end

function T:SetItem(itemID)
  self.itemID = itemID
  if self.frame and self.frame:IsShown() then self:Refresh() end
end

-- Pick something sensible to show when nothing is selected
local function defaultItem()
  local list = FI.Alerts:List()
  if list[1] then return list[1] end
  local best, bestV
  for id, it in pairs(FI:Realm().items) do
    local v = (it.mkt or 0) * (it.qty or 0)
    if (it.seen or it.imported) and (not bestV or v > bestV) then best, bestV = id, v end
  end
  return best
end

local function setChange(tab, v)
  local c = FI.ChangeColor(v)
  tab.pill:SetBackdropColor(c[1], c[2], c[3], 1)
  tab.pill:SetBackdropBorderColor(c[1], c[2], c[3], 1)
  tab.pill.text:SetText(v and FI.Percent(v) or "new")
  tab.pill:SetWidth(tab.pill.text:GetStringWidth() + 14)
end

-- The chart grows with the window: whatever height the stats row doesn't need
function T:FitChart()
  local tab = self.frame
  local h = tab.center:GetHeight()
  if not h or h < 200 then return end
  tab.box:SetHeight(math.max(240, h - 96 - 62 - 16))
end

-- Header and stats follow whatever window the chart shows (preset, zoom or pan)
local PRESET_LABEL = {
  ["15M"] = "past 15 minutes", ["1H"] = "past hour", ["6H"] = "past 6 hours", ["12H"] = "past 12 hours",
  ["1D"] = "past 24 hours", ["1W"] = "past 7 days", ["1M"] = "past 30 days", ["All"] = "all history",
}
function T:OnChartDrawn(info)
  local tab = self.frame
  local view = tab.view
  self.tf = view.preset
  local it = self.itemID and FI:Realm().items[self.itemID]
  if not it or not it.mkt then return end
  local label = view.customSpan and ("showing " .. FI.Duration(info.span)) or (PRESET_LABEL[view.preset] or "")
  if info.offset and info.offset > 0 then label = label .. ", ending " .. FI.Duration(info.offset) .. " ago" end
  local fromAtr = it.imported and (not it.seen or it.imported > it.seen)
  tab.tfLabel:SetText(label .. "  -  " .. (fromAtr and ("from Auctionator " .. FI.Ago(it.imported)) or ("scanned " .. FI.Ago(it.seen))))
  setChange(tab, info.change)
  tab.stats[1].value:SetText(info.hi and info.hi > -math.huge and FI.Money(info.hi) or "-")
  tab.stats[2].value:SetText(info.lo and info.lo < math.huge and FI.Money(info.lo) or "-")
  tab.stats[4].label:SetText("EST. SOLD (WINDOW)")
  tab.stats[4].value:SetText(info.sold and FI.Number(info.sold) or "-")
end

function T:DrawDepth(it)
  local tab = self.frame
  local d = it and it.d
  local qmax, wallI = 0, nil
  if d then
    for i = 2, #d, 2 do if d[i] > qmax then qmax, wallI = d[i], i end end
  end
  local cum, below = 0, 0
  for i, r in ipairs(tab.depthRows) do
    local p, q = d and d[i * 2 - 1], d and d[i * 2]
    if p then
      cum = cum + q
      if wallI and i * 2 < wallI then below = below + q end
      r.price:SetText(FI.Money(p))
      r.qty:SetText(FI.Number(q))
      r.cum:SetText(FI.Number(cum))
      r.bar:SetWidth(math.max(1, q / qmax * r:GetWidth()))
      local col = (i * 2 == wallI) and C.gold or C.down
      r.bar:SetColorTexture(col[1], col[2], col[3], (i * 2 == wallI) and 0.3 or 0.2)
      r:Show()
    else
      r:Hide()
    end
  end
  tab.listed:SetText(it and it.qty and (FI.Number(it.qty) .. " listed") or "")
  if wallI and wallI > 2 and qmax >= 20 then
    tab.wall:SetText(("Wall: |cffe8b84a%s|r at %s. Only %s below it."):format(FI.Number(qmax), FI.Money(d[wallI - 1]), FI.Number(below)))
  elseif d and d[1] then
    tab.wall:SetText("No big wall right now.")
  else
    tab.wall:SetText("Nothing listed in the last scan.")
  end
end

function T:Refresh()
  local tab = self.frame
  if not tab then return end
  local realm = FI:Realm()
  self.watch = FI.Alerts:List()
  tab.watchList:SetCount(#self.watch)
  tab.watchEmpty:SetShown(#self.watch == 0)

  if not self.itemID or not realm.items[self.itemID] then
    self.itemID = self.itemID or defaultItem()
  end
  local id = self.itemID
  self:FitChart()
  if not id then
    tab.name:SetText("No data yet")
    tab.price:SetText("")
    tab.pill:Hide()
    tab.tfLabel:SetText("Open the Auction House and scan to start.")
    tab.icon:SetTexture(nil)
    tab.watchBtn:Hide()
    tab.view:SetItem(nil)
    tab.view.empty:SetText("Open the Auction House: Goonberg Terminal scans it and starts building charts.")
    self:DrawDepth(nil)
    return
  end
  local it = realm.items[id]
  tab.watchBtn:Show()
  tab.watchBtn:SetSelected(FI.Alerts:IsWatched(id))
  tab.watchBtn:SetLabel(FI.Alerts:IsWatched(id) and "Watching" or "+ Watch")
  tab.icon:SetTexture(FI:ItemIcon(id))
  tab.name:SetText(FI:ItemName(id))
  tab.name:SetTextColor(FI:ItemQualityColor(id))

  local w = realm.watch[id]
  tab.belowBox:SetText(w and w.below and FI.Money(w.below, true):gsub(" ", "") or "")
  tab.aboveBox:SetText(w and w.above and FI.Money(w.above, true):gsub(" ", "") or "")
  if w and (w.belowFired or w.aboveFired) then
    tab.alertState:SetText("|cffe8b84aTriggered.|r Re-arms when the price moves back.")
  elseif w and (w.below or w.above) then
    tab.alertState:SetText("|cff3fb68bArmed.|r")
  else
    tab.alertState:SetText("No alert set for this item.")
  end

  if not it or not it.mkt then
    tab.price:SetText("-")
    tab.pill:Hide()
    tab.tfLabel:SetText("Not seen on the AH yet")
    for _, s in ipairs(tab.stats) do s.value:SetText("-") end
    tab.view:SetItem(id)
    self:DrawDepth(nil)
    tab.watchList:Refresh()
    return
  end

  local now = time()
  local s = H.Stats(it, now)
  tab.price:SetText(FI.Money(it.mkt))
  tab.pill:Show()
  tab.stats[3].value:SetText(FI.Number(s.qty))
  tab.view:SetItem(id) -- draws, then OnChartDrawn fills the header and stats
  self:DrawDepth(it)
  tab.watchList:Refresh()
end

FI:On("FI_WATCH_CHANGED", function() if T.frame and T.frame:IsShown() then T:Refresh() end end)
FI:On("FI_ITEM_LOADED", function()
  FI:Debounce("chart", 0.3, function()
    if T.frame and T.frame:IsShown() then T:Refresh() end
  end)
end)
