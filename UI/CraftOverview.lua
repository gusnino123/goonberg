-- Goonberg Terminal: crafting overview (how all your recipes are doing)
local _, FI = ...
local K = FI.CraftTab
local W = FI.Widgets
local C = FI.colors

local CHART_H = 120

local function card(parent, title)
  local b = W.Box(parent, C.panel, C.border)
  b:SetHeight(78)
  b.title = W.Heading(b, title)
  b.title:SetPoint("TOPLEFT", 14, -12)
  b.value = W.Text(b, 20, C.text, true)
  b.value:SetPoint("TOPLEFT", 14, -29)
  b.value:SetPoint("RIGHT", -14, 0)
  b.sub = W.Text(b, 10, C.muted)
  b.sub:SetPoint("BOTTOMLEFT", 14, 10)
  b.sub:SetPoint("RIGHT", -14, 0)
  return b
end

local function section(parent, title)
  local b = W.Box(parent, C.panel, C.border)
  b.title = W.Heading(b, title)
  b.title:SetPoint("TOPLEFT", 14, -12)
  return b
end

-- a list of recipe lines (movers): icon, name, profit now, change
local function moverRows(box, count)
  box.rows = {}
  for i = 1, count do
    local r = CreateFrame("Button", nil, box)
    r:SetHeight(28)
    r:SetPoint("TOPLEFT", 1, -34 - (i - 1) * 30)
    r:SetPoint("RIGHT", -1, 0)
    r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 13, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = W.Text(r, 12, C.text)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetWidth(200)
    r.now = W.Text(r, 12, C.text, true)
    r.now:SetPoint("RIGHT", -110, 0)
    r.now:SetJustifyH("RIGHT")
    r.delta = W.Text(r, 12, C.up, true)
    r.delta:SetPoint("RIGHT", -14, 0)
    r.delta:SetJustifyH("RIGHT")
    r:SetScript("OnEnter", function(self) self.bg:SetAlpha(0.5) end)
    r:SetScript("OnLeave", function(self) self.bg:SetAlpha(0) end)
    r:SetScript("OnClick", function(self)
      K.view = "Recipes"
      K.prof = "All"
      K.selected = self.recipeID
      K:Refresh()
    end)
    box.rows[i] = r
  end
  box.empty = W.Text(box, 11, C.muted)
  box.empty:SetPoint("TOPLEFT", 14, -40)
  box.empty:SetPoint("RIGHT", -14, 0)
  box.empty:SetWordWrap(true)
  box.empty:SetText("Needs a week of scans to compare against.")
end

local function fillMovers(box, list)
  local any = false
  for i, r in ipairs(box.rows) do
    local m = list[i]
    if m then
      any = true
      r:Show()
      r.recipeID = m.row.recipeID
      r.icon:SetTexture(FI:ItemIcon(m.row.rec.o))
      r.name:SetText(m.row.name)
      r.name:SetTextColor(FI:ItemQualityColor(m.row.rec.o))
      local cNow = FI.ChangeColor(m.row.profit)
      r.now:SetText((m.row.profit >= 0 and "+" or "") .. FI.Coins(m.row.profit))
      r.now:SetTextColor(cNow[1], cNow[2], cNow[3])
      local c = FI.ChangeColor(m.delta)
      r.delta:SetText((m.delta >= 0 and "+" or "") .. FI.Coins(m.delta))
      r.delta:SetTextColor(c[1], c[2], c[3])
    else
      r:Hide()
    end
  end
  box.empty:SetShown(not any)
end

function K:BuildOverview(tab)
  local f = CreateFrame("Frame", nil, tab)
  f:SetPoint("TOPLEFT", 0, -56)
  f:SetPoint("BOTTOMRIGHT", 0, 0)

  -- cards
  local cards = {
    card(f, "RECIPES"),
    card(f, "PROFITABLE NOW"),
    card(f, "MEDIAN MARGIN"),
    card(f, "DAILY PROFIT POOL"),
    card(f, "CRAFTS SOLD, 7 DAYS"),
  }
  cards[1]:SetPoint("TOPLEFT", 16, 0)
  for i = 2, 5 do cards[i]:SetPoint("TOPLEFT", cards[i - 1], "TOPRIGHT", 12, 0) end
  f:SetScript("OnSizeChanged", function(self, w)
    local each = (w - 32 - 48) / 5
    for i = 1, 5 do cards[i]:SetWidth(each) end
    local half = (w - 32 - 12) / 2
    self.chartBox:SetWidth(half)
    self.up:SetWidth(half)
  end)
  f.cards = cards

  -- margin chart (14 days)
  local chart = section(f, "MEDIAN MARGIN OF YOUR RECIPES, LAST 14 DAYS")
  chart:SetPoint("TOPLEFT", 16, -90)
  chart:SetSize(520, 206)
  f.chartBox = chart
  local plot = CreateFrame("Frame", nil, chart)
  plot:SetPoint("TOPLEFT", 14, -36)
  plot:SetPoint("RIGHT", chart, "RIGHT", -14, 0)
  plot:SetHeight(CHART_H)
  local zero = W.Tex(plot, C.border)
  zero:SetHeight(1)
  f.zero = zero
  f.plot = plot
  f.bars, f.dayLabels = {}, {}
  for i = 1, 14 do
    local b = CreateFrame("Frame", nil, plot)
    b.tex = W.Tex(b, C.up, 0.85)
    b.tex:SetAllPoints()
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(date("%A %b %d", self.day.t), 1, 1, 1)
      GameTooltip:AddDoubleLine("Median margin", self.day.margin and FI.Percent(self.day.margin) or "-", 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Recipes priced", self.day.n, 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    f.bars[i] = b
    local l = W.Text(chart, 9, C.muted)
    l:SetJustifyH("CENTER")
    f.dayLabels[i] = l
  end
  f.chartEmpty = W.Text(chart, 12, C.muted)
  f.chartEmpty:SetPoint("CENTER", plot, "CENTER")
  f.chartEmpty:SetJustifyH("CENTER")
  f.chartEmpty:SetText("Builds up as you scan over the next days.")

  -- by profession
  local profs = section(f, "BY PROFESSION")
  profs:SetPoint("TOPLEFT", chart, "TOPRIGHT", 12, 0)
  profs:SetPoint("RIGHT", f, "RIGHT", -16, 0)
  profs:SetHeight(206)
  local heads = { { "RECIPES", -300 }, { "PROFITABLE", -220 }, { "MEDIAN", -140 }, { "POOL / DAY", -14 } }
  local hf = CreateFrame("Frame", nil, profs)
  hf:SetPoint("TOPLEFT", 0, -3)
  hf:SetPoint("TOPRIGHT", 0, -3)
  hf:SetHeight(26)
  K.profHeaders = W.SortHeaders(hf, {
    { key = "known", label = "RECIPES", r = -300 }, { key = "profitable", label = "PROFITABLE", r = -220 },
    { key = "medianMargin", label = "MEDIAN", r = -140 }, { key = "pool", label = "POOL / DAY", r = -14 },
  }, K.profSort, function() K:RefreshOverview() end)
  f.profRows = {}
  for i = 1, 6 do
    local r = CreateFrame("Button", nil, profs)
    r:SetHeight(26)
    r:SetPoint("TOPLEFT", 1, -34 - (i - 1) * 28)
    r:SetPoint("RIGHT", -1, 0)
    r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
    r.bg:SetAllPoints()
    r.name = W.Text(r, 12, C.text)
    r.name:SetPoint("LEFT", 13, 0)
    r.cells = {}
    for k, h in ipairs(heads) do
      local fs = W.Text(r, 12, C.text, true)
      fs:SetPoint("RIGHT", h[2] + 1, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[k] = fs
    end
    r:SetScript("OnEnter", function(self)
      self.bg:SetAlpha(0.5)
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      GameTooltip:AddLine(self.prof or "")
      if self.bestData then
        GameTooltip:AddDoubleLine("Best recipe", self.bestData.name, 0.76, 0.79, 0.83, 1, 1, 1)
        if self.bestData.margin then GameTooltip:AddDoubleLine("Its margin", FI.Percent(self.bestData.margin), 0.76, 0.79, 0.83, 0.25, 0.71, 0.55) end
      end
      GameTooltip:AddLine("|cff8b95a3Click to see these recipes.|r")
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.bg:SetAlpha(0); GameTooltip_Hide() end)
    r:SetScript("OnClick", function(self) K.view = "Recipes"; K.prof = self.prof; K:Refresh() end)
    f.profRows[i] = r
  end
  f.profEmpty = W.Text(profs, 12, C.muted)
  f.profEmpty:SetPoint("TOPLEFT", 14, -40)
  f.profEmpty:SetPoint("RIGHT", -14, 0)
  f.profEmpty:SetWordWrap(true)
  f.profEmpty:SetText("Open each of your profession windows once so Goonberg learns your recipes.")

  -- movers
  local up = section(f, "GETTING MORE PROFITABLE (VS. 7 DAYS AGO)")
  up:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -12)
  up:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
  up:SetWidth(509)
  local down = section(f, "GETTING LESS PROFITABLE")
  down:SetPoint("TOPLEFT", up, "TOPRIGHT", 12, 0)
  down:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
  for _, pair in ipairs({ { up, K.upSort }, { down, K.downSort } }) do
    local box, state = pair[1], pair[2]
    local hf = CreateFrame("Frame", nil, box)
    hf:SetPoint("TOPLEFT", 0, -3)
    hf:SetPoint("TOPRIGHT", 0, -3)
    hf:SetHeight(26)
    box.headers = W.SortHeaders(hf, {
      { key = "now", label = "PROFIT NOW", r = -110 }, { key = "delta", label = "CHANGE", r = -14 },
    }, state, function() K:RefreshOverview() end)
    moverRows(box, 6)
  end
  f.up, f.down = up, down
  return f
end

function K:RefreshOverview()
  local f = self.overview
  local o = FI.Crafting:Overview()

  -- cards
  local c = f.cards
  c[1].value:SetText(FI.Number(o.known))
  c[1].sub:SetText(("%d with all prices known"):format(o.priced))
  c[2].value:SetText(FI.Number(o.profitable))
  c[2].value:SetTextColor(C.up[1], C.up[2], C.up[3])
  c[2].sub:SetText(o.priced > 0 and ("%d%% of priced recipes"):format(math.floor(o.profitable / o.priced * 100 + 0.5)) or "")
  local mc = FI.ChangeColor(o.medianMargin)
  c[3].value:SetText(o.medianMargin and FI.Percent(o.medianMargin) or "-")
  c[3].value:SetTextColor(mc[1], mc[2], mc[3])
  c[3].sub:SetText(o.best and ("Best: %s (%s)"):format(o.best.name, FI.Percent(o.best.margin or 0)) or "")
  c[4].value:SetText(FI.Coins(o.pool))
  c[4].value:SetTextColor(C.text[1], C.text[2], C.text[3])
  c[4].sub:SetText("a day at today's sales pace")
  c[5].value:SetText(FI.Coins(o.sold7))
  c[5].sub:SetText("AH sales of items you can craft")

  -- chart
  local plot = f.plot
  local W_ = plot:GetWidth()
  if not W_ or W_ < 10 then W_ = 490 end
  local maxAbs, any = 1, false
  for _, d in ipairs(o.days) do
    if d.margin then any = true; maxAbs = math.max(maxAbs, math.abs(d.margin)) end
  end
  local hasNeg = false
  for _, d in ipairs(o.days) do if d.margin and d.margin < 0 then hasNeg = true end end
  local zeroY = hasNeg and CHART_H / 2 or 0
  local span = hasNeg and CHART_H / 2 or CHART_H
  f.zero:ClearAllPoints()
  f.zero:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, zeroY)
  f.zero:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, zeroY)
  local slot = W_ / 14
  local bw = math.floor(slot * 0.62)
  for i, b in ipairs(f.bars) do
    local d = o.days[i]
    b.day = d
    local x = (i - 1) * slot + (slot - bw) / 2
    local label = f.dayLabels[i]
    label:ClearAllPoints()
    label:SetPoint("TOP", plot, "BOTTOMLEFT", x + bw / 2, -6)
    label:SetText(i == 14 and "today" or date("%d", d.t))
    if d.margin then
      local h = math.max(2, math.abs(d.margin) / maxAbs * (span - 4))
      local col = d.margin >= 0 and C.up or C.down
      b.tex:SetColorTexture(col[1], col[2], col[3], 0.85)
      b:ClearAllPoints()
      b:SetSize(bw, h)
      if d.margin >= 0 then
        b:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, zeroY)
      else
        b:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", x, zeroY)
      end
      b:Show()
    else
      b:Hide()
    end
  end
  f.chartEmpty:SetShown(not any)

  -- professions, in the order picked by clicking a column header
  local profList = {}
  for i, p in ipairs(o.profList) do profList[i] = p end
  W.SortRows(profList, self.profSort.sort, self.profSort.dir)
  for i, r in ipairs(f.profRows) do
    local p = profList[i]
    if p then
      r:Show()
      r.prof = p.name
      r.name:SetText(p.name)
      r.bestData = p.best
      r.cells[1]:SetText(p.known)
      r.cells[2]:SetText(p.profitable)
      r.cells[2]:SetTextColor(C.up[1], C.up[2], C.up[3])
      local pc = FI.ChangeColor(p.medianMargin)
      r.cells[3]:SetText(p.medianMargin and FI.Percent(p.medianMargin) or "-")
      r.cells[3]:SetTextColor(pc[1], pc[2], pc[3])
      r.cells[4]:SetText(FI.Coins(p.pool))
      r.cells[4]:SetTextColor(C.text[1], C.text[2], C.text[3])
    else
      r:Hide()
    end
  end
  f.profEmpty:SetShown(#o.profList == 0)

  -- movers: best improvements first, then the biggest drops
  local ups, downs = {}, {}
  for _, m in ipairs(o.movers) do if m.delta > 0 then ups[#ups + 1] = m end end
  for i = #o.movers, 1, -1 do if o.movers[i].delta < 0 then downs[#downs + 1] = o.movers[i] end end
  local nowOf = function(m) return m.row and m.row.profit end
  W.SortRows(ups, self.upSort.sort, self.upSort.dir, self.upSort.sort == "now" and nowOf or nil)
  W.SortRows(downs, self.downSort.sort, self.downSort.dir, self.downSort.sort == "now" and nowOf or nil)
  fillMovers(f.up, ups)
  fillMovers(f.down, downs)
end
