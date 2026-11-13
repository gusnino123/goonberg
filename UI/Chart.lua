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

  local tfs = W.Choice(center, { "1H", "6H", "12H", "1D", "1W", "1M", "All" }, "seg", function(v) T.tf = v; T:Refresh() end, 26)
  -- timeframes sit on the title row, left of the watch button; the item name
  -- stops before them so nothing overlaps on narrow windows
  tfs:SetPoint("RIGHT", watchBtn, "LEFT", -10, 0)
  tab.name:SetPoint("RIGHT", tfs, "LEFT", -12, 0)
  tfs:Select(T.tf)
  tab.tfs = tfs

  -- Chart box
  local box = W.Box(center, C.panel, C.border)
  box:SetPoint("TOPLEFT", PAD, -96)
  box:SetPoint("RIGHT", center, "RIGHT", -PAD, 0)
  box:SetHeight(PLOT_H + VOL_H + 58)
  tab.box = box

  local plot = CreateFrame("Frame", nil, box)
  plot:SetPoint("TOPLEFT", 14, -14)
  plot:SetPoint("RIGHT", box, "RIGHT", -AXIS_W, 0)
  plot:SetHeight(PLOT_H)
  tab.plot = plot

  local vol = CreateFrame("Frame", nil, box)
  vol:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -10)
  vol:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -10)
  vol:SetHeight(VOL_H)
  local volLine = W.Tex(vol, C.border)
  volLine:SetPoint("TOPLEFT"); volLine:SetPoint("TOPRIGHT"); volLine:SetHeight(1)
  tab.vol = vol

  tab.xStart = W.Text(box, 10, C.muted)
  tab.xStart:SetPoint("TOPLEFT", vol, "BOTTOMLEFT", 0, -6)
  local xMid = W.Text(box, 10, C.muted)
  xMid:SetPoint("TOP", vol, "BOTTOM", 0, -6)
  xMid:SetText("bars: est. sold")
  local xEnd = W.Text(box, 10, C.muted)
  xEnd:SetPoint("TOPRIGHT", vol, "BOTTOMRIGHT", 0, -6)
  xEnd:SetText("now")

  tab.emptyChart = W.Text(box, 13, C.muted)
  tab.emptyChart:SetPoint("CENTER", plot, "CENTER")
  tab.emptyChart:SetJustifyH("CENTER")
  tab.emptyChart:SetWordWrap(true)
  tab.emptyChart:SetWidth(380)

  local function tex(parent) return function() return parent:CreateTexture(nil, "ARTWORK") end end
  tab.candlePool = W.Pool(tex(plot))
  tab.volPool = W.Pool(tex(vol))
  tab.gridPool = W.Pool(function() local t = plot:CreateTexture(nil, "BACKGROUND"); return t end)
  tab.labelPool = W.Pool(function() return W.Text(box, 10, C.muted, true) end)
  tab.tagPool = W.Pool(function()
    local f = W.Box(box, C.up, C.up)
    f:SetHeight(18)
    f:SetFrameLevel(plot:GetFrameLevel() + 5)
    f.text = W.Text(f, 11, C.bg, true)
    f.text:SetPoint("CENTER")
    return f
  end)
  tab.hoverPool = W.Pool(function()
    local h = CreateFrame("Frame", nil, plot)
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self)
      local c = self.candle
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.when, 1, 1, 1)
      GameTooltip:AddDoubleLine("Open", FI.Money(c.o), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("High", FI.Money(c.hi), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Low", FI.Money(c.lo), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Close", FI.Money(c.c), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Est. sold", FI.Number(c.v), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", GameTooltip_Hide)
    return h
  end)

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
  local boxH = h - 100 - 62 - 16
  local plotH = math.max(120, boxH - VOL_H - 58)
  self.plotH = plotH
  tab.plot:SetHeight(plotH)
  tab.box:SetHeight(plotH + VOL_H + 58)
end

function T:DrawChart(it)
  local tab = self.frame
  self:FitChart()
  tab.candlePool:Reset(); tab.volPool:Reset(); tab.gridPool:Reset()
  tab.labelPool:Reset(); tab.tagPool:Reset(); tab.hoverPool:Reset()

  local now = time()
  local tf = TF[self.tf]
  local span = tf.span or H.Span(it, now)
  local n = tf.n
  local candles = H.Candles(it, now, span, n)
  tab.xStart:SetText(tf.start)
  if #candles == 0 then
    tab.emptyChart:SetText("No price history in this timeframe yet.\nEach AH scan adds a point; charts fill in as you scan.")
    tab.emptyChart:Show()
    return
  end
  tab.emptyChart:Hide()

  local plot = tab.plot
  local PW = plot:GetWidth()
  if not PW or PW < 10 then PW = 400 end
  local hi, lo, vmax = -math.huge, math.huge, 0
  for _, c in ipairs(candles) do
    if c.hi > hi then hi = c.hi end
    if c.lo < lo then lo = c.lo end
    if c.v > vmax then vmax = c.v end
  end
  local w = FI:Realm().watch[self.itemID]
  local lines = {}
  if w and w.below then lines[#lines + 1] = { w.below, "ALERT " .. FI.Money(w.below) } end
  if w and w.above then lines[#lines + 1] = { w.above, "ALERT " .. FI.Money(w.above) } end
  for _, l in ipairs(lines) do
    -- only stretch the scale for alerts that are reasonably close
    if l[1] < lo and l[1] > lo * 0.6 then lo = l[1] end
    if l[1] > hi and l[1] < hi * 1.6 then hi = l[1] end
  end
  if hi == lo then hi, lo = hi * 1.05, lo * 0.95 end
  local pad = (hi - lo) * 0.08
  hi, lo = hi + pad, math.max(0, lo - pad)
  local PLOT_H = self.plotH or PLOT_H
  local function y(p) return (p - lo) / (hi - lo) * PLOT_H end

  -- grid + price labels
  for k = 0, 4 do
    local p = lo + (hi - lo) * k / 4
    local g = tab.gridPool:Get()
    g:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.7)
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y(p))
    g:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, y(p))
    g:SetHeight(1)
    local l = tab.labelPool:Get()
    l:ClearAllPoints()
    l:SetPoint("LEFT", plot, "BOTTOMRIGHT", 8, y(p))
    l:SetText(FI.Money(p))
  end

  local slot = PW / n
  local bw = math.max(3, math.floor(slot * 0.6))
  local start = now - span
  for _, c in ipairs(candles) do
    local x = c.slot * slot + slot / 2
    local col = c.c >= c.o and C.up or C.down
    local wick = tab.candlePool:Get()
    wick:SetColorTexture(col[1], col[2], col[3], 1)
    wick:ClearAllPoints()
    wick:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(x), y(c.lo))
    wick:SetSize(1, math.max(1, y(c.hi) - y(c.lo)))
    local body = tab.candlePool:Get()
    body:SetColorTexture(col[1], col[2], col[3], 1)
    body:ClearAllPoints()
    body:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(x - bw / 2 + 0.5), y(math.min(c.o, c.c)))
    body:SetSize(bw, math.max(2, math.abs(y(c.o) - y(c.c))))
    if c.v > 0 and vmax > 0 then
      local v = tab.volPool:Get()
      v:SetColorTexture(col[1], col[2], col[3], 0.4)
      v:ClearAllPoints()
      v:SetPoint("BOTTOMLEFT", tab.vol, "BOTTOMLEFT", math.floor(x - bw / 2 + 0.5), 0)
      v:SetSize(bw, math.max(1, c.v / vmax * (VOL_H - 4)))
    end
    local hov = tab.hoverPool:Get()
    hov:ClearAllPoints()
    hov:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c.slot * slot, 0)
    hov:SetSize(math.max(2, slot), PLOT_H)
    hov.candle = c
    local t0 = start + c.slot * span / n
    hov.when = date(span <= 86400 and "%a %H:%M" or "%b %d, %H:%M", t0)
  end

  local function hline(price, color, label, labelOnLeft, dark)
    local g = tab.gridPool:Get()
    g:SetColorTexture(color[1], color[2], color[3], 0.8)
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y(price))
    g:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, y(price))
    g:SetHeight(1)
    local tag = tab.tagPool:Get()
    tag:ClearAllPoints()
    tag.text:SetText(label)
    tag:SetWidth(tag.text:GetStringWidth() + 12)
    if labelOnLeft then
      tag:SetPoint("LEFT", plot, "BOTTOMLEFT", 4, y(price))
      tag:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
      tag.text:SetTextColor(color[1], color[2], color[3])
    else
      tag:SetPoint("LEFT", plot, "BOTTOMRIGHT", 4, y(price))
      tag:SetBackdropColor(color[1], color[2], color[3], 1)
      tag.text:SetTextColor(C.bg[1], C.bg[2], C.bg[3])
    end
    tag:SetBackdropBorderColor(color[1], color[2], color[3], 1)
  end
  for _, l in ipairs(lines) do
    if l[1] >= lo and l[1] <= hi then hline(l[1], C.gold, l[2], true) end
  end
  local last = candles[#candles].c
  local first = candles[1].o
  hline(last, last >= first and C.up or C.down, FI.Money(last), false)
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
  tab.tfs:Select(self.tf)
  if not id then
    tab.name:SetText("No data yet")
    tab.price:SetText("")
    tab.pill:Hide()
    tab.tfLabel:SetText("Open the Auction House and scan to start.")
    tab.icon:SetTexture(nil)
    tab.watchBtn:Hide()
    tab.emptyChart:SetText("Open the Auction House: Goonberg Terminal scans it and starts building charts.")
    tab.emptyChart:Show()
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
    self:DrawChart({ h = {} })
    self:DrawDepth(nil)
    tab.watchList:Refresh()
    return
  end

  local now = time()
  local s = H.Stats(it, now)
  tab.price:SetText(FI.Money(it.mkt))
  tab.pill:Show()
  local tfChange
  if TF[self.tf].chg then tfChange = s[TF[self.tf].chg] else
    local h = it.h
    local firstP
    local span = TF[self.tf].span or H.Span(it, now)
    for i = 1, #h, H.STRIDE do
      if h[i] >= now - span and h[i + 1] > 0 then firstP = h[i + 1]; break end
    end
    if firstP and firstP > 0 then tfChange = (it.mkt - firstP) / firstP * 100 end
  end
  setChange(tab, tfChange)
  local fromAtr = it.imported and (not it.seen or it.imported > it.seen)
  tab.tfLabel:SetText(TF[self.tf].label .. "  -  " .. (fromAtr and ("from Auctionator " .. FI.Ago(it.imported)) or ("scanned " .. FI.Ago(it.seen))))

  -- High/low over the timeframe
  local span = TF[self.tf].span or H.Span(it, now)
  local hi, lo
  for i = 1, #it.h, H.STRIDE do
    local t, m = it.h[i], it.h[i + 1]
    if t >= now - span and m > 0 then
      if not hi or m > hi then hi = m end
      if not lo or m < lo then lo = m end
    end
  end
  tab.stats[1].value:SetText(FI.Money(hi))
  tab.stats[2].value:SetText(FI.Money(lo))
  tab.stats[3].value:SetText(FI.Number(s.qty))
  local soldKey = TF[self.tf].sold or "sold7"
  tab.stats[4].label:SetText("EST. SOLD " .. ((TF[self.tf].sold and self.tf) or "7D"):upper())
  tab.stats[4].value:SetText(FI.Number(s[soldKey]))

  self:DrawChart(it)
  self:DrawDepth(it)
  tab.watchList:Refresh()
end

FI:On("FI_WATCH_CHANGED", function() if T.frame and T.frame:IsShown() then T:Refresh() end end)
FI:On("FI_ITEM_LOADED", function()
  FI:Debounce("chart", 0.3, function()
    if T.frame and T.frame:IsShown() then T:Refresh() end
  end)
end)
