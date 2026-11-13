-- Goonberg Terminal: crafting profit screen (/goon2 or /goon craft)
local _, FI = ...
local K = { prof = "All", sort = "Profit", onlyProfit = false, search = "", view = "Overview" }
FI.CraftTab = K
local W = FI.Widgets
local C = FI.colors

local ROWS, ROW_H = 30, 30
local DETAIL_W = 320
local TOP = 90 -- the table starts below two rows of controls
-- numbers hang off the table's right edge (r = right side of the column)
local COLS = {
  { key = "cost", label = "COST", r = -372 },
  { key = "sell", label = "SELLS FOR", r = -276 },
  { key = "profit", label = "PROFIT", r = -184 },
  { key = "margin", label = "MARGIN", r = -100 },
  { key = "sold", label = "SOLD/DAY", r = -14 },
}
local NAME_RIGHT = -440

local function money(v) return v and FI.Money(v) or "-" end
-- a cost with unpriced reagents: "?" alone if nothing is priced yet
local function costText(row)
  if row.missing > 0 then
    return row.cost > 0 and ("|cff8b95a3%s + ?|r"):format(FI.Money(row.cost)) or "|cff8b95a3?|r"
  end
  return FI.Money(row.cost)
end

local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
  r.bg:SetAllPoints()
  local line = W.Tex(r, C.border, 0.6, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", 12, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = W.Text(r, 12, C.text)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", NAME_RIGHT, 0)
  r.cells = {}
  for _, col in ipairs(COLS) do
    local fs = W.Text(r, 12, C.text, true)
    fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
    fs:SetJustifyH("RIGHT")
    r.cells[col.key] = fs
  end
  r:SetScript("OnEnter", function(self) if not self.on then self.bg:SetAlpha(0.5) end end)
  r:SetScript("OnLeave", function(self) if not self.on then self.bg:SetAlpha(0) end end)
  r:SetScript("OnClick", function(self)
    if IsModifiedClick("CHATLINK") then
      local link = FI:ItemLink(self.row.rec.o)
      if link then ChatEdit_InsertLink(link) end
    else
      K.selected = self.row.recipeID
      K:ShowDetail(self.row)
      K.list:Refresh()
    end
  end)
  return r
end

local function updateRow(r, i)
  local row = K.rows[i]
  r.row = row
  r.on = row.recipeID == K.selected
  r.bg:SetAlpha(r.on and 1 or 0)
  r.icon:SetTexture(FI:ItemIcon(row.rec.o))
  local made = row.rec.n > 1 and ("  |cff8b95a3x%s|r"):format(row.rec.n % 1 == 0 and row.rec.n or ("%.1f"):format(row.rec.n)) or ""
  r.name:SetText(row.name .. made)
  r.name:SetTextColor(FI:ItemQualityColor(row.rec.o))
  r.cells.cost:SetText(costText(row))
  r.cells.sell:SetText(row.noSell and "|cff8b95a3no AH data|r" or money(row.sell))
  local c = FI.ChangeColor(row.profit)
  if row.complete then
    r.cells.profit:SetText((row.profit >= 0 and "+" or "") .. FI.Money(row.profit))
    r.cells.profit:SetTextColor(c[1], c[2], c[3])
    r.cells.margin:SetText(row.margin and FI.Percent(row.margin) or "-")
    r.cells.margin:SetTextColor(c[1], c[2], c[3])
  else
    r.cells.profit:SetText("-")
    r.cells.profit:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    r.cells.margin:SetText("-")
    r.cells.margin:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
  end
  r.cells.sold:SetText(row.soldPerDay and FI.Number(row.soldPerDay) or "-")
end

local function buildDetail(tab)
  local d = W.Box(tab, C.panel, C.border)
  d:SetPoint("TOPRIGHT", -16, -TOP)
  d:SetPoint("BOTTOMRIGHT", -16, 16)
  d:SetWidth(DETAIL_W)
  K.detail = d

  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(36, 36)
  d.icon:SetPoint("TOPLEFT", 14, -14)
  d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.name = W.Text(d, 15, C.text)
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
  d.name:SetPoint("RIGHT", -14, 0)
  d.sub = W.Text(d, 11, C.muted)
  d.sub:SetPoint("BOTTOMLEFT", d.icon, "BOTTOMRIGHT", 10, 1)

  local h = W.Heading(d, "REAGENTS")
  h:SetPoint("TOPLEFT", 14, -66)

  d.lines = {}
  for i = 1, 8 do
    local l = CreateFrame("Frame", nil, d)
    l:SetHeight(26)
    l:SetPoint("TOPLEFT", 14, -84 - (i - 1) * 28)
    l:SetPoint("RIGHT", -14, 0)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetSize(20, 20)
    l.icon:SetPoint("LEFT")
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.name = W.Text(l, 11, C.text)
    l.name:SetPoint("LEFT", l.icon, "RIGHT", 8, 0)
    l.name:SetWidth(150)
    l.src = W.Text(l, 9, C.muted)
    l.src:SetPoint("RIGHT", -80, 0)
    l.src:SetJustifyH("RIGHT")
    l.price = W.Text(l, 12, C.gold, true)
    l.price:SetPoint("RIGHT")
    l.price:SetJustifyH("RIGHT")
    d.lines[i] = l
  end

  local sum = W.Tex(d, C.border)
  sum:SetPoint("TOPLEFT", 14, -84 - 8 * 28 - 4)
  sum:SetPoint("RIGHT", -14, 0)
  sum:SetHeight(1)
  d.totals = {}
  local labels = { "Cost to craft", "Sells for (after 5% AH cut)", "Profit per craft" }
  for i, label in ipairs(labels) do
    local l = W.Text(d, 12, C.soft)
    l:SetPoint("TOPLEFT", 14, -84 - 8 * 28 - 14 - (i - 1) * 22)
    l:SetText(label)
    local v = W.Text(d, 13, C.text, true)
    v:SetPoint("TOPRIGHT", -14, -84 - 8 * 28 - 14 - (i - 1) * 22)
    v:SetJustifyH("RIGHT")
    d.totals[i] = v
  end

  local watch = W.Button(d, "Watch reagents", nil, 28, "pill")
  watch:SetPoint("BOTTOMLEFT", 14, 14)
  watch:SetScript("OnClick", function()
    local row = K.detailRow
    if not row then return end
    for i = 1, #row.rec.r, 2 do FI.Alerts:Watch(row.rec.r[i]) end
    FI.Alerts:Watch(row.rec.o)
  end)
  local chart = W.Button(d, "Open chart", nil, 28, "pill")
  chart:SetPoint("LEFT", watch, "RIGHT", 8, 0)
  chart:SetScript("OnClick", function() if K.detailRow then FI.UI:ShowItem(K.detailRow.rec.o) end end)
  d.buttons = { watch, chart }

  d.empty = W.Text(d, 12, C.muted)
  d.empty:SetPoint("TOPLEFT", 14, -16)
  d.empty:SetPoint("RIGHT", -14, 0)
  d.empty:SetWordWrap(true)
  d.empty:SetText("Click a recipe to see its reagents and where each price comes from.")
end

function K:ShowDetail(row)
  local d = self.detail
  self.detailRow = row
  local has = row ~= nil
  d.empty:SetShown(not has)
  d.icon:SetShown(has); d.name:SetShown(has); d.sub:SetShown(has)
  for _, b in ipairs(d.buttons) do b:SetShown(has) end
  for _, v in ipairs(d.totals) do v:SetShown(has) end
  if not has then
    for _, l in ipairs(d.lines) do l:Hide() end
    return
  end
  d.icon:SetTexture(FI:ItemIcon(row.rec.o))
  d.name:SetText(row.name)
  d.name:SetTextColor(FI:ItemQualityColor(row.rec.o))
  d.sub:SetText(("%s  -  makes %s"):format(row.prof, row.rec.n))
  for i, l in ipairs(d.lines) do
    local g = row.reagents[i]
    if g then
      l:Show()
      l.icon:SetTexture(FI:ItemIcon(g.id))
      l.name:SetText(("%s x%d"):format(FI:ItemName(g.id), g.qty))
      l.src:SetText(g.src == "vendor" and "VENDOR" or (g.src == "ah" and "AH" or "NO PRICE"))
      l.price:SetText(g.price and FI.Money(g.price * g.qty) or "-")
    else
      l:Hide()
    end
  end
  d.totals[1]:SetText(costText(row))
  d.totals[2]:SetText(row.noSell and "no AH data" or FI.Money(row.sell))
  if row.complete then
    local c = FI.ChangeColor(row.profit)
    d.totals[3]:SetText(("%s%s  (%s)"):format(row.profit >= 0 and "+" or "", FI.Money(row.profit), row.margin and FI.Percent(row.margin) or "-"))
    d.totals[3]:SetTextColor(c[1], c[2], c[3])
  else
    d.totals[3]:SetText(row.missing > 0 and "scan more to price all reagents" or "item not seen on the AH")
    d.totals[3]:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
  end
end

function K:Build(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab
  self.rows = {}

  local views = W.Choice(tab, { "Overview", "Recipes" }, "seg", function(v) K.view = v; K:Refresh() end, 26)
  views:SetPoint("TOPLEFT", 16, -16)
  views:Select(self.view)
  self.viewChoice = views

  self.profBar = CreateFrame("Frame", nil, tab)
  self.profBar:SetPoint("TOPLEFT", 16, -52)
  self.profBar:SetSize(600, 26)

  local sortBy = W.Choice(tab, { "Profit", "Margin", "Sold/day" }, "seg", function(v) K.sort = v; K:Refresh() end, 26)
  sortBy:SetPoint("TOPRIGHT", -16, -16)
  sortBy:Select(self.sort)
  local only = W.Button(tab, "Profitable only", nil, 26, "pill")
  only:SetPoint("RIGHT", sortBy, "LEFT", -12, 0)
  only:SetScript("OnClick", function(self) K.onlyProfit = not K.onlyProfit; self:SetSelected(K.onlyProfit); K:Refresh() end)
  local search = W.EditBox(tab, 150, "Search")
  search:SetPoint("RIGHT", only, "LEFT", -12, 0)
  search:SetScript("OnTextChanged", function(self)
    if self.ph then self.ph:SetShown(self:GetText() == "") end
    K.search = self:GetText():lower()
    FI:Debounce("craftsearch", 0.2, function() K:Refresh() end)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -TOP)
  tbl:SetPoint("BOTTOMRIGHT", -(16 + DETAIL_W + 12), 16)

  local head = CreateFrame("Frame", nil, tbl)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(28)
  local hl = W.Tex(head, C.border)
  hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT"); hl:SetHeight(1)
  local it = W.Heading(head, "CRAFTED ITEM")
  it:SetPoint("LEFT", 12, 0)
  for _, col in ipairs(COLS) do
    local fs = W.Heading(head, col.label)
    fs:SetPoint("RIGHT", head, "RIGHT", col.r, 0)
    fs:SetJustifyH("RIGHT")
  end

  local holder = CreateFrame("Frame", nil, tbl)
  holder:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
  holder:SetPoint("BOTTOMRIGHT", tbl, "BOTTOMRIGHT", -1, 26)
  self.list = W.List(holder, ROWS, ROW_H, makeRow, updateRow)
  self.list:SetAllPoints(holder)

  self.empty = W.Text(tbl, 13, C.muted)
  self.empty:SetPoint("CENTER", holder, "CENTER")
  self.empty:SetJustifyH("CENTER")
  self.empty:SetWidth(560)
  self.empty:SetWordWrap(true)

  self.footer = W.Text(tbl, 10, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 12, 8)
  self.footer:SetPoint("RIGHT", -12, 0)

  buildDetail(tab)
  self:ShowDetail(nil)
  self.recipeParts = { self.profBar, sortBy, only, search, tbl, self.detail }
  self.overview = self:BuildOverview(tab)
  tab.Refresh = function() K:Refresh() end
  return tab
end

-- Profession buttons change as you scan professions, so they're rebuilt
function K:BuildProfBar()
  local profs = FI.Crafting:Professions()
  local key = table.concat(profs, "|")
  if key == self.profKey then return end
  self.profKey = key
  if self.profChoice then self.profChoice:Hide() end
  local values = { "All" }
  for _, p in ipairs(profs) do values[#values + 1] = p end
  self.profChoice = W.Choice(self.profBar, values, "pill", function(v) K.prof = v; K:Refresh() end, 26)
  self.profChoice:SetPoint("LEFT")
  if K.prof ~= "All" and not tContains(profs, K.prof) then K.prof = "All" end
  self.profChoice:Select(K.prof)
end

function K:Refresh()
  if not self.frame then return end
  local ov = self.view == "Overview"
  self.viewChoice:Select(self.view)
  for _, part in ipairs(self.recipeParts) do part:SetShown(not ov) end
  self.overview:SetShown(ov)
  if ov then return self:RefreshOverview() end
  self:BuildProfBar()
  local all = FI.Crafting:Rows(self.prof)
  local rows = {}
  local profitable = 0
  for _, r in ipairs(all) do
    if r.complete and r.profit > 0 then profitable = profitable + 1 end
    local ok = true
    if self.onlyProfit and not (r.complete and r.profit > 0) then ok = false end
    if ok and self.search ~= "" and not r.name:lower():find(self.search, 1, true) then ok = false end
    if ok then rows[#rows + 1] = r end
  end
  local key = self.sort
  local function val(r)
    if not r.complete then return nil end
    if key == "Margin" then return r.margin elseif key == "Sold/day" then return r.soldPerDay end
    return r.profit
  end
  table.sort(rows, function(a, b)
    local va, vb = val(a), val(b)
    if va == nil and vb == nil then return a.name < b.name end
    if va == nil then return false end
    if vb == nil then return true end
    if va == vb then return a.name < b.name end
    return va > vb
  end)
  self.rows = rows
  local fkey = self.prof .. self.sort .. tostring(self.onlyProfit) .. self.search
  if fkey ~= self.lastFilter then self.list.offset = 0; self.lastFilter = fkey end
  self.list:SetCount(#rows)

  if #FI.Crafting:Professions() == 0 then
    self.empty:SetText("No recipes yet.\nOpen each of your profession windows once and Goonberg reads your recipes.\nThen visit the AH so it has prices.")
    self.empty:Show()
  elseif #rows == 0 then
    self.empty:SetText(self.onlyProfit and "Nothing profitable right now with these filters." or "No recipes match.")
    self.empty:Show()
  else
    self.empty:Hide()
  end
  self.footer:SetText(("%d recipes  -  %d profitable right now  -  reagents priced at the cheaper of AH and vendor"):format(#all, profitable))

  local keep
  for _, r in ipairs(rows) do if r.recipeID == self.selected then keep = r end end
  self:ShowDetail(keep)
end

FI:On("FI_RECIPES_CHANGED", function() if K.frame and K.frame:IsShown() then K:Refresh() end end)
FI:On("FI_SCAN_DONE", function() if K.frame and K.frame:IsShown() then K:Refresh() end end)
