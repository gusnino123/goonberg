-- Goonberg Terminal: interactive price chart (TradingView-style)
--   Crosshair with live legend (O/H/L/C, est. sold, change) and axis tags
--   Mouse wheel zooms the time range around the cursor; drag pans back in time
--   Candles, line or area; 7 and 25 moving averages; usual price / typical low lines
--   Right-click sets a price alert there; drag an alert line to move it
---@type string, GoonbergTerminal
local _, FI = ...
---A chart. V is the prototype: V:Create() makes a view that carries its own frames.
---@class GT.ChartView
---@field [string] any
local V = {}
FI.ChartView = V
local W = FI.Widgets
local C = FI.colors

local AXIS_W, VOL_H, TOP_BAR, LEGEND_H = 72, 44, 34, 18
local MIN_SPAN = 3 * 3600
local CANDLE_PX = 8 -- target width of one candle (body + gap)
local MA_COLORS = { { 0.40, 0.68, 1.00 }, { 0.75, 0.55, 0.98 } } -- MA 7, MA 25
local REF_USUAL, REF_LOW = { 0.55, 0.62, 0.72 }, { 0.25, 0.71, 0.55 }

V.PRESETS = {
  { "15M", 900 }, { "1H", 3600 }, { "6H", 6 * 3600 }, { "12H", 12 * 3600 },
  { "1D", 86400 }, { "1W", 7 * 86400 }, { "1M", 30 * 86400 }, { "All", nil },
}
local PRESET_SPAN = {}
for _, p in ipairs(V.PRESETS) do PRESET_SPAN[p[1]] = p[2] end

-- Candle size: the finest that keeps candles about CANDLE_PX wide on this chart
local SLOTS = { 300, 600, 900, 1800, 3600, 2 * 3600, 3 * 3600, 4 * 3600, 6 * 3600, 8 * 3600, 12 * 3600,
  86400, 2 * 86400, 3 * 86400, 7 * 86400 }
local function slotFor(span, width)
  local most = math.max(20, math.floor((width or 400) / CANDLE_PX))
  for _, s in ipairs(SLOTS) do if span / s <= most then return s end end
  return SLOTS[#SLOTS]
end
local function slotName(s)
  if s < 3600 then return (s / 60) .. "-minute" end
  if s < 86400 then return (s / 3600) .. "-hour" end
  if s == 7 * 86400 then return "weekly" end
  return s == 86400 and "daily" or ((s / 86400) .. "-day")
end
-- local time zone offset, so daily candles and labels start at your midnight
local function tzOffset()
  local now = time()
  local u = date("!*t", now)
  u.isdst = date("*t", now).isdst
  return now - time(u)
end
-- time axis: the tick spacing that gives about 5 labels
local TICKS = { 900, 1800, 3600, 2 * 3600, 3 * 3600, 6 * 3600, 12 * 3600, 86400, 2 * 86400, 7 * 86400, 14 * 86400, 30 * 86400 }

-- an axis label for a tick: hours within a day, the day at midnight and for day ticks
local function timeLabel(t, span, tick)
  tick = tick or 3600
  if tick >= 86400 then return date(span <= 14 * 86400 and "%a %d" or "%b %d", t) end
  local d = date("*t", t)
  if d.hour == 0 and d.min == 0 then return date("%a %d", t) end
  return date("%H:%M", t)
end

local function setTex(t, col, a) t:SetColorTexture(col[1], col[2], col[3], a or 1) end

-- ---------------------------------------------------------------------------
function V:Create(parent, opts)
  local box = W.Box(parent, C.panel, C.border)
  local view = setmetatable({ box = box, opts = opts or {} }, { __index = V })
  view.preset = (opts and opts.preset) or "1W"
  view.offset = 0          -- seconds between "now" and the right edge
  view.style = "Candles"
  view.showMA, view.showRef = true, false

  -- Top bar: timeframes | style | indicators | back to now
  local tfNames = {}
  for _, p in ipairs(V.PRESETS) do tfNames[#tfNames + 1] = p[1] end
  view.tfChoice = W.Choice(box, tfNames, "seg", function(v) view:SetPreset(v) end, 24)
  view.tfChoice:SetPoint("TOPLEFT", 10, -6)
  view.styleChoice = W.Choice(box, { "Candles", "Line", "Area" }, "seg", function(v) view.style = v; view:Draw() end, 24)
  view.styleChoice:SetPoint("LEFT", view.tfChoice, "RIGHT", 10, 0)
  view.styleChoice:Select(view.style)
  view.maBtn = W.Button(box, "MA 7/25", nil, 24, "pill")
  view.maBtn:SetPoint("LEFT", view.styleChoice, "RIGHT", 10, 0)
  view.maBtn:SetScript("OnClick", function(self) view.showMA = not view.showMA; self:SetSelected(view.showMA); view:Draw() end)
  view.maBtn:SetSelected(view.showMA)
  view.refBtn = W.Button(box, "Usual price", nil, 24, "pill")
  view.refBtn:SetPoint("LEFT", view.maBtn, "RIGHT", 6, 0)
  view.refBtn:SetScript("OnClick", function(self) view.showRef = not view.showRef; self:SetSelected(view.showRef); view:Draw() end)
  -- One toolbar row when it fits; on a narrow chart the chart style and indicator
  -- buttons move to a second row instead of running off the edge.
  function view:LayoutBar()
    local w = self.box:GetWidth() or 0
    local need = self.tfChoice:GetWidth() + 10 + self.styleChoice:GetWidth() + 10 + self.maBtn:GetWidth() + 6 + self.refBtn:GetWidth() + 20
    local rows = (w > 0 and need > w) and 2 or 1
    if rows == self.barRows then return false end
    self.barRows = rows
    self.styleChoice:ClearAllPoints()
    if rows == 1 then
      self.styleChoice:SetPoint("LEFT", self.tfChoice, "RIGHT", 10, 0)
    else
      self.styleChoice:SetPoint("TOPLEFT", self.tfChoice, "BOTTOMLEFT", 0, -6)
    end
    local top = TOP_BAR + (rows - 1) * 30
    self.legend:ClearAllPoints()
    self.legend:SetPoint("TOPLEFT", 14, -(top + 2))
    self.legend:SetPoint("RIGHT", self.box, "RIGHT", -AXIS_W, 0)
    self.plot:ClearAllPoints()
    self.plot:SetPoint("TOPLEFT", 14, -(top + LEGEND_H + 6))
    self.plot:SetPoint("BOTTOMRIGHT", self.box, "BOTTOMRIGHT", -AXIS_W, VOL_H + 30)
    return true
  end
  box:HookScript("OnSizeChanged", function() if view.plot and view:LayoutBar() then view:Draw() end end)

  view.nowBtn = W.Button(box, "Back to now", nil, 24, "gold")
  view.nowBtn:SetPoint("TOPRIGHT", -10, -6)
  view.nowBtn:SetScript("OnClick", function() view.offset = 0; view:Draw() end)
  view.nowBtn:Hide()

  -- Legend (top-left of the plot)
  view.legend = W.Text(box, 11, C.soft, true)
  view.legend:SetPoint("RIGHT", box, "RIGHT", -AXIS_W, 0)

  -- Plot, volume, axes
  local plot = CreateFrame("Frame", nil, box)
  plot:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -AXIS_W, VOL_H + 30)
  plot:EnableMouse(true)
  plot:EnableMouseWheel(true)
  view.plot = plot
  -- candles are drawn on a canvas the plot clips, so ones half off the edge while
  -- panning are cut cleanly instead of spilling over the axis
  if plot.SetClipsChildren then plot:SetClipsChildren(true) end
  local canvas = CreateFrame("Frame", nil, plot)
  canvas:SetAllPoints()
  view.canvas = canvas
  view:LayoutBar()
  local vol = CreateFrame("Frame", nil, box)
  vol:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -6)
  vol:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -6)
  vol:SetHeight(VOL_H - 6)
  if vol.SetClipsChildren then vol:SetClipsChildren(true) end
  local volCanvas = CreateFrame("Frame", nil, vol)
  volCanvas:SetAllPoints()
  view.volCanvas = volCanvas
  local volLine = W.Tex(vol, C.border)
  volLine:SetPoint("TOPLEFT"); volLine:SetPoint("TOPRIGHT"); volLine:SetHeight(1)
  view.vol = vol

  view.empty = W.Text(box, 13, C.muted)
  view.empty:SetPoint("CENTER", plot, "CENTER")
  view.empty:SetJustifyH("CENTER")
  view.empty:SetWordWrap(true)
  view.empty:SetWidth(380)

  local function tex(p, layer) return function() return p:CreateTexture(nil, layer or "ARTWORK") end end
  view.candles = W.Pool(tex(canvas))
  view.vols = W.Pool(tex(volCanvas))
  view.grid = W.Pool(tex(canvas, "BACKGROUND"))
  view.labels = W.Pool(function() return W.Text(box, 10, C.muted, true) end)
  view.xlabels = W.Pool(function() return W.Text(box, 10, C.muted) end)
  view.lines = W.Pool(function() return W.Line(canvas, C.gold, 1.5) or canvas:CreateTexture() end)
  -- how to use it, always in view (bottom-left, under the time axis)
  view.hint = W.Text(box, 10, C.muted)
  view.hint:SetPoint("BOTTOMLEFT", 14, 4)
  view.hint:SetText("Scroll to zoom  ·  drag to move  ·  double-click to reset  ·  right-click to set a price alert")
  view.slotText = W.Text(box, 10, C.muted)
  view.slotText:SetPoint("BOTTOMRIGHT", -14, 4)
  view.tags = W.Pool(function()
    local f = W.Box(box, C.up, C.up)
    f:SetHeight(18)
    f:SetFrameLevel(plot:GetFrameLevel() + 5)
    f.text = W.Text(f, 11, C.bg, true)
    f.text:SetPoint("CENTER")
    return f
  end)

  -- Crosshair (drawn above everything)
  local over = CreateFrame("Frame", nil, plot)
  over:SetAllPoints()
  over:SetFrameLevel(plot:GetFrameLevel() + 8)
  view.vline = over:CreateTexture(nil, "OVERLAY"); setTex(view.vline, C.muted, 0.7); view.vline:SetWidth(1)
  view.hline = over:CreateTexture(nil, "OVERLAY"); setTex(view.hline, C.muted, 0.7); view.hline:SetHeight(1)
  view.priceTag = W.Box(box, C.raised, C.muted)
  view.priceTag:SetHeight(18)
  view.priceTag:SetFrameLevel(plot:GetFrameLevel() + 9)
  view.priceTag.text = W.Text(view.priceTag, 11, C.text, true)
  view.priceTag.text:SetPoint("CENTER")
  view.timeTag = W.Box(box, C.raised, C.muted)
  view.timeTag:SetHeight(18)
  view.timeTag:SetFrameLevel(plot:GetFrameLevel() + 9)
  view.timeTag.text = W.Text(view.timeTag, 10, C.text)
  view.timeTag.text:SetPoint("CENTER")
  view:HideCrosshair()

  view:Hook()
  return view
end

function V:HideCrosshair()
  self.vline:Hide(); self.hline:Hide(); self.priceTag:Hide(); self.timeTag:Hide()
  self.hover = nil
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
function V:SetItem(itemID)
  if itemID ~= self.itemID then self.offset = 0 end
  self.itemID = itemID
  self:Draw()
end

function V:SetPreset(name)
  self.preset = name
  self.customSpan = nil
  self.offset = 0
  self:Draw()
end

function V:Item()
  return self.itemID and FI:Realm().items[self.itemID]
end

-- The whole history's span (for "All" and the zoom-out limit)
function V:MaxSpan(it, now)
  return math.max(86400, FI.History.Span(it or {}, now))
end

function V:Span(it, now)
  if self.customSpan then return self.customSpan end
  return PRESET_SPAN[self.preset] or self:MaxSpan(it, now)
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function sma(closes, n, i)
  if i < n then return nil end
  local s = 0
  for k = i - n + 1, i do s = s + closes[k] end
  return s / n
end

function V:Draw()
  local now = time()
  local it = self:Item()
  for _, p in ipairs({ self.candles, self.vols, self.grid, self.labels, self.xlabels, self.lines, self.tags }) do p:Reset() end
  self.tfChoice:Select(not self.customSpan and self.preset or nil)
  self.nowBtn:SetShown(self.offset > 0)

  local plot = self.plot
  local PW, PH = plot:GetWidth(), plot:GetHeight()
  if not PW or PW < 10 then PW = 400 end
  if not PH or PH < 10 then PH = 220 end
  self.PW, self.PH = PW, PH

  local span = self:Span(it, now)
  local maxSpan = self:MaxSpan(it, now)
  self.offset = math.max(0, math.min(self.offset, maxSpan))
  local endT = now - self.offset
  local startT = endT - span
  local slot = slotFor(span, PW)
  self.tz = self.tz or tzOffset()
  self.endT, self.span, self.slot, self.n = endT, span, slot, span / slot
  local series = (it and it.h) and FI.History.CandleSeries(it, slot, self.tz) or {}
  -- the visible candles plus one each side, so lines run to the edges
  local candles, first = FI.History.CandleRange(series, startT - slot, endT + slot, slot)
  self.data = candles
  -- MAs need the candles just before the window too
  self.series, self.seriesFirst = series, first
  self.slotText:SetText(slotName(slot) .. " candles")

  local info = { span = span, offset = self.offset, candles = #candles }
  if #candles == 0 then
    self.empty:SetText(it and "No price history in this window.\nScroll to zoom out, or drag to look further back." or "Pick an item to chart.")
    self.empty:Show()
    self.legend:SetText("")
    if self.opts.onDraw then self.opts.onDraw(info) end
    return
  end
  self.empty:Hide()
  local function xOf(t) return (t - startT) / span * PW end
  self.xOf = xOf

  -- Price range: candles, plus MAs, reference and alert lines that are close by
  local hi, lo, vmax = -math.huge, math.huge, 0
  local closes = {}
  for i, c in ipairs(candles) do
    if c.t + slot > startT and c.t < endT then
      hi, lo = math.max(hi, c.hi), math.min(lo, c.lo)
      vmax = math.max(vmax, c.v)
    end
    closes[i] = c.c
  end
  if hi < lo then for _, c in ipairs(candles) do hi, lo = math.max(hi, c.hi), math.min(lo, c.lo) end end
  local extras = {}
  local w = FI:Realm().watch[self.itemID]
  if w and w.below then extras[#extras + 1] = { w.below, "alert", "below" } end
  if w and w.above then extras[#extras + 1] = { w.above, "alert", "above" } end
  local lt = self.showRef and it and FI.History.LongTerm(it, now)
  if lt and lt.historical then extras[#extras + 1] = { lt.historical, "usual" } end
  if lt and lt.typicalLow then extras[#extras + 1] = { lt.typicalLow, "low" } end
  for _, e in ipairs(extras) do
    if e[1] < lo and e[1] > lo * 0.6 then lo = e[1] end
    if e[1] > hi and e[1] < hi * 1.6 then hi = e[1] end
  end
  if hi == lo then hi, lo = hi * 1.05, lo * 0.95 end
  local pad = (hi - lo) * 0.08
  hi, lo = hi + pad, math.max(0, lo - pad)
  self.hi, self.lo = hi, lo
  local function y(p) return (p - lo) / (hi - lo) * PH end
  self.y = y

  -- Grid and price axis
  for k = 0, 4 do
    local p = lo + (hi - lo) * k / 4
    local g = self.grid:Get()
    setTex(g, C.border, 0.6)
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y(p))
    g:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, y(p))
    g:SetHeight(1)
    local l = self.labels:Get()
    l:ClearAllPoints()
    l:SetPoint("LEFT", plot, "BOTTOMRIGHT", 8, y(p))
    l:SetText(FI.Money(p))
  end
  -- Time axis: labels on round times (midnight, 6:00...), sliding with the chart
  local tick = TICKS[#TICKS]
  for _, st in ipairs(TICKS) do if span / st <= 5 then tick = st; break end end
  local tz = self.tz
  local t0 = math.ceil((startT + tz) / tick) * tick - tz
  for t = t0, endT, tick do
    local x = xOf(t)
    if x > 20 and x < PW - 20 then
      local l = self.xlabels:Get()
      l:ClearAllPoints()
      l:SetPoint("TOP", self.vol, "BOTTOMLEFT", x, -4)
      l:SetText(timeLabel(t, span, tick))
      local g = self.grid:Get()
      setTex(g, C.border, 0.35)
      g:ClearAllPoints()
      g:SetPoint("TOPLEFT", plot, "TOPLEFT", math.floor(x), 0)
      g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(x), 0)
      g:SetWidth(1)
    end
  end

  -- Candles / line / area, and volume
  local slotW = slot / span * PW
  -- tight candles: 70% of the slot, always at least a 1-pixel gap between them
  local bw = math.max(1, math.min(math.floor(slotW * 0.7 + 0.5), math.floor(slotW) - 1))
  local pts = {}
  for _, c in ipairs(candles) do
    local x = xOf(c.t + slot / 2)
    c.x = x
    local col = c.c >= c.o and C.up or C.down
    if self.style == "Candles" then
      local wick = self.candles:Get()
      setTex(wick, col, 0.9)
      wick:ClearAllPoints()
      wick:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(x), y(c.lo))
      wick:SetSize(1, math.max(1, y(c.hi) - y(c.lo)))
      local body = self.candles:Get()
      setTex(body, col)
      body:ClearAllPoints()
      body:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(x - bw / 2 + 0.5), y(math.min(c.o, c.c)))
      body:SetSize(bw, math.max(1, math.abs(y(c.o) - y(c.c))))
    else
      pts[#pts + 1] = { x, y(c.c) }
      if self.style == "Area" then
        local col2 = self.candles:Get()
        setTex(col2, C.gold, 0.10)
        col2:ClearAllPoints()
        col2:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(x - slotW / 2 + 0.5), 0)
        col2:SetSize(math.max(1, math.ceil(slotW)), math.max(1, y(c.c)))
      end
    end
    if c.v > 0 and vmax > 0 then
      local v = self.vols:Get()
      setTex(v, col, 0.35)
      v:ClearAllPoints()
      v:SetPoint("BOTTOMLEFT", self.vol, "BOTTOMLEFT", math.floor(x - bw / 2 + 0.5), 0)
      v:SetSize(bw, math.max(1, c.v / vmax * (VOL_H - 10)))
    end
  end
  local function polyline(points, col, thick)
    for i = 2, #points do
      local l = self.lines:Get()
      if l.SetStartPoint then
        l:SetColorTexture(col[1], col[2], col[3], 1)
        l:SetThickness(thick or 1.5)
        l:SetStartPoint("BOTTOMLEFT", plot, points[i - 1][1], points[i - 1][2])
        l:SetEndPoint("BOTTOMLEFT", plot, points[i][1], points[i][2])
      end
    end
  end
  if #pts > 0 then polyline(pts, C.gold, 1.5) end

  -- Moving averages: computed over the whole series, so they start at the left edge
  local maNow = {}
  if self.showMA then
    local series, f = self.series, self.seriesFirst
    for k, len in ipairs({ 7, 25 }) do
      local mpts = {}
      local sum, from = 0, math.max(1, f - len + 1)
      for i = from, f + #candles - 1 do
        sum = sum + series[i].c
        if i - len >= from then sum = sum - series[i - len].c end
        if i - from + 1 >= len and i >= f then
          local c = series[i]
          local m = sum / len
          mpts[#mpts + 1] = { c.x or xOf(c.t + slot / 2), y(m) }
          if c.t < endT then maNow[k] = m end
        end
      end
      polyline(mpts, MA_COLORS[k], 1)
    end
  end
  self.maNow = maNow

  -- Horizontal lines: reference prices, alerts, last price
  local function hline(price, col, label, left, alpha)
    if price < lo or price > hi then return end
    local g = self.grid:Get()
    setTex(g, col, alpha or 0.8)
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y(price))
    g:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, y(price))
    g:SetHeight(1)
    local tag = self.tags:Get()
    tag:ClearAllPoints()
    tag.text:SetText(label)
    tag:SetWidth(tag.text:GetStringWidth() + 12)
    if left then
      tag:SetPoint("LEFT", plot, "BOTTOMLEFT", 4, y(price))
      tag:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
      tag.text:SetTextColor(col[1], col[2], col[3])
    else
      tag:SetPoint("LEFT", plot, "BOTTOMRIGHT", 4, y(price))
      tag:SetBackdropColor(col[1], col[2], col[3], 1)
      tag.text:SetTextColor(C.bg[1], C.bg[2], C.bg[3])
    end
    tag:SetBackdropBorderColor(col[1], col[2], col[3], 1)
  end
  self.alertYs = {}
  for _, e in ipairs(extras) do
    if e[2] == "alert" then
      hline(e[1], C.gold, "ALERT " .. FI.Money(e[1]), true)
      self.alertYs[#self.alertYs + 1] = { dir = e[3], price = e[1] }
    elseif e[2] == "usual" then
      hline(e[1], REF_USUAL, "USUAL " .. FI.Money(e[1]), true, 0.5)
    else
      hline(e[1], REF_LOW, "TYPICAL LOW " .. FI.Money(e[1]), true, 0.5)
    end
  end
  local vis = {}
  for _, c in ipairs(candles) do if c.t + slot > startT and c.t < endT then vis[#vis + 1] = c end end
  if #vis == 0 then vis = candles end
  local last, first = vis[#vis].c, vis[1].o
  hline(last, last >= first and C.up or C.down, FI.Money(last), false)

  -- Summary for the header (and the legend when not hovering)
  local sold, wHi, wLo = 0, -math.huge, math.huge
  for _, c in ipairs(vis) do sold = sold + c.v; wHi = math.max(wHi, c.hi); wLo = math.min(wLo, c.lo) end
  info.first, info.last, info.sold, info.hi, info.lo = first, last, sold, wHi, wLo
  info.change = first > 0 and (last - first) / first * 100 or nil
  info.startT, info.endT = startT, endT
  self.info = info
  self.drawn = (self.drawn or 0) + 1
  self:Legend(nil)
  if self.opts.onDraw then self.opts.onDraw(info) end
end

-- Legend: the candle under the cursor, or the latest one
function V:Legend(c)
  if not c and self.data then
    for i = #self.data, 1, -1 do if self.data[i].t < (self.endT or math.huge) then c = self.data[i]; break end end
  end
  if not c then self.legend:SetText(""); return end
  local chg = c.o > 0 and (c.c - c.o) / c.o * 100 or nil
  local col = (c.c >= c.o) and "ff3fb68b" or "fff0613a"
  local parts = {
    ("O |c%s%s|r"):format(col, FI.Money(c.o)),
    ("H |c%s%s|r"):format(col, FI.Money(c.hi)),
    ("L |c%s%s|r"):format(col, FI.Money(c.lo)),
    ("C |c%s%s|r"):format(col, FI.Money(c.c)),
    ("|c%s%s|r"):format(col, FI.Percent(chg)),
    ("sold %s"):format(FI.Number(c.v)),
  }
  if self.showMA and self.maNow then
    if self.maNow[1] then parts[#parts + 1] = ("|cff66adffMA7 %s|r"):format(FI.Money(self.maNow[1])) end
    if self.maNow[2] then parts[#parts + 1] = ("|cffbf8cfaMA25 %s|r"):format(FI.Money(self.maNow[2])) end
  end
  self.legend:SetText(table.concat(parts, "   "))
end

-- ---------------------------------------------------------------------------
-- Mouse: crosshair, zoom, pan, alerts
-- ---------------------------------------------------------------------------
function V:Cursor()
  local plot = self.plot
  local scale = plot:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local left, bottom = plot:GetLeft() or 0, plot:GetBottom() or 0
  return cx / scale - left, cy / scale - bottom
end

function V:PriceAtY(py)
  return self.lo + (py / self.PH) * (self.hi - self.lo)
end

function V:UpdateCrosshair(force)
  if not self.data or #self.data == 0 or not self.PW then return self:HideCrosshair() end
  local x, py = self:Cursor()
  -- nothing moved since the last frame: nothing to do
  if not force and x == self.cx and py == self.cy and self.drawn == self.cDrawn then return end
  self.cx, self.cy, self.cDrawn = x, py, self.drawn
  if x < 0 or x > self.PW or py < 0 or py > self.PH then return self:HideCrosshair() end
  -- snap to the candle under the cursor (they're in time order: binary search)
  local data = self.data
  local lo, hi = 1, #data
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if (data[mid].x or 0) < x then lo = mid + 1 else hi = mid end
  end
  local best = data[lo]
  if lo > 1 and math.abs((data[lo - 1].x or 0) - x) < math.abs((best.x or 0) - x) then best = data[lo - 1] end
  local plot = self.plot
  self.vline:ClearAllPoints()
  self.vline:SetPoint("TOPLEFT", plot, "TOPLEFT", math.floor(best.x), 0)
  self.vline:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", math.floor(best.x), 0)
  self.hline:ClearAllPoints()
  self.hline:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, py)
  self.hline:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, py)
  self.priceTag.text:SetText(FI.Money(self:PriceAtY(py)))
  self.priceTag:SetWidth(self.priceTag.text:GetStringWidth() + 12)
  self.priceTag:ClearAllPoints()
  self.priceTag:SetPoint("LEFT", plot, "BOTTOMRIGHT", 4, py)
  if self.hover ~= best then
    self.timeTag.text:SetText(date(self.slot < 86400 and "%b %d %H:%M" or "%a %b %d", best.t))
    self.timeTag:SetWidth(self.timeTag.text:GetStringWidth() + 12)
  end
  self.timeTag:ClearAllPoints()
  self.timeTag:SetPoint("TOP", self.vol, "BOTTOMLEFT", math.max(30, math.min(self.PW - 30, best.x)), -2)
  self.vline:Show(); self.hline:Show(); self.priceTag:Show(); self.timeTag:Show()
  if self.hover ~= best then
    self.hover = best
    self:Legend(best)
  end
end

-- Zoom the time range around the cursor (wheel up = closer), in small steps
function V:Zoom(delta)
  local it = self:Item()
  if not it or not self.PW then return end
  local now = time()
  local x = math.max(0, math.min(self.PW, (self:Cursor())))
  local span = self.span or self:Span(it, now)
  local startT = (self.endT or now) - span
  local anchor = startT + x / self.PW * span
  local newSpan = math.max(MIN_SPAN, math.min(self:MaxSpan(it, now) * 1.1, span * (delta > 0 and 0.85 or 1 / 0.85)))
  local newEnd = anchor + (1 - x / self.PW) * newSpan
  self.customSpan = newSpan
  self.offset = math.max(0, now - newEnd)
  self:Draw()
end

-- Double-click: back to the timeframe you picked, ending now
function V:Reset()
  self.customSpan = nil
  self.offset = 0
  self:Draw()
end

function V:Hook()
  local view, plot = self, self.plot
  plot:SetScript("OnMouseWheel", function(_, delta) view:Zoom(delta) end)
  plot:SetScript("OnMouseDown", function(_, button)
    if not view.data or #view.data == 0 then return end
    local x, py = view:Cursor()
    if button == "RightButton" then
      -- set an alert at this price: below the current price = "below", else "above"
      local price = math.floor(view:PriceAtY(py) + 0.5)
      local it = view:Item()
      local dir = (it and it.mkt and price < it.mkt) and "below" or "above"
      FI.Alerts:SetAlert(view.itemID, dir, price)
      view:Draw()
      return
    end
    local t = GetTime()
    if view.lastClick and t - view.lastClick < 0.35 then
      view.lastClick = nil
      view.panX = nil
      return view:Reset()
    end
    view.lastClick = t
    -- grab an alert line if the cursor is on it, otherwise move the chart
    for _, a in ipairs(view.alertYs or {}) do
      if math.abs(view.y(a.price) - py) <= 5 then
        view.dragAlert = a.dir
        return
      end
    end
    view.panX, view.panOffset, view.panSpan = x, view.offset, view.span
  end)
  plot:SetScript("OnMouseUp", function()
    if view.dragAlert then
      local _, py = view:Cursor()
      local price = math.floor(view:PriceAtY(math.max(0, math.min(view.PH or 0, py))) + 0.5)
      FI.Alerts:SetAlert(view.itemID, view.dragAlert, price)
      view.dragAlert = nil
      view:Draw()
    end
    view.panX = nil
  end)
  plot:SetScript("OnLeave", function() view:HideCrosshair(); view:Legend(nil) end)
  plot:SetScript("OnUpdate", function()
    if view.panX then
      -- follow the mouse every frame it moves: the chart slides with it
      local x = view:Cursor()
      if x ~= view.panLastX then
        view.panLastX = x
        if math.abs(x - view.panX) > 2 then view.lastClick = nil end -- a drag isn't half a double-click
        local newOffset = math.max(0, view.panOffset + (x - view.panX) / view.PW * (view.panSpan or view.span))
        if newOffset ~= view.offset then
          view.offset = newOffset
          view:Draw()
        end
      end
    end
    if plot:IsMouseOver() then view:UpdateCrosshair() elseif view.hover then view:HideCrosshair(); view:Legend(nil) end
  end)
end

V.AXIS_W, V.VOL_H, V.TOP_BAR, V.LEGEND_H = AXIS_W, VOL_H, TOP_BAR, LEGEND_H
