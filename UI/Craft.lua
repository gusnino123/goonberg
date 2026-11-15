-- Goonberg Terminal: crafting profit screen (/goon2 or /goon craft)
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.CraftTab
local K = { prof = "All", sortState = { sort = "profit", dir = -1 }, onlyProfit = false, search = "", view = "Overview",
  profSort = { sort = "pool", dir = -1 }, upSort = { sort = "delta", dir = -1 }, downSort = { sort = "delta", dir = 1 } }
FI.CraftTab = K
local W = FI.Widgets
local C = FI.colors

local ROWS, ROW_H = 30, 30
-- (the old side panel is kept hidden; the list expands in place instead)
local DETAIL_W = 320
local TOP = 90 -- the table starts below two rows of controls
-- numbers hang off the table's right edge (r = right side of the column)
local COLS = {
  { key = "cost", label = "Cost", r = -372 },
  { key = "sell", label = "AH Price", r = -276 },
  { key = "profit", label = "Profit*", r = -184 },
  { key = "margin", label = "Margin", r = -100 },
  { key = "sold", label = "Sold/Day", r = -14 },
}
local NAME_RIGHT = -440

-- money columns (each lines its amounts up across the rows)
local MONEY = { cost = W.MoneyColumn(), sell = W.MoneyColumn(), profit = W.MoneyColumn() }

-- how old a price is, short: "5 h", "3 d"
local function age(t)
  if not t then return nil end
  local a = time() - t
  if a < 3600 then return math.max(1, math.floor(a / 60)) .. " min" end
  if a < 86400 then return math.floor(a / 3600) .. " h" end
  return math.floor(a / 86400) .. " d"
end
-- a recipe whose prices aren't current: "· prices 3 d old" / "· not on the AH now"
local function staleNote(row)
  if row.unlisted then return "  |cffe8b84a· none listed now|r" end
  if (row.unlistedMats or 0) > 0 then return "  |cffe8b84a· a material isn't listed now|r" end
  if row.oldest and time() - row.oldest > 86400 then return ("  |cffe8b84a· prices %s old|r"):format(age(row.oldest)) end
  return ""
end
-- a cost with unpriced reagents: "?" alone if nothing is priced yet
local function costText(row)
  if row.missing > 0 then
    return row.cost > 0 and ("|cff9e998f%s + ?|r"):format(FI.Coins(row.cost)) or "|cff9e998f?|r"
  end
  return FI.Coins(row.cost)
end
local function setCost(cell, row)
  if row.missing > 0 then cell:SetText(costText(row)) else cell:SetMoney(row.cost) end
end

-- The list shows recipes; a clicked recipe expands in place to show its reagents
-- (quantity, price each, where the price comes from, line total) and a total line.
-- K.display holds what's on screen: { kind = "recipe"|"reagent"|"total", ... }
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"

function K:BuildDisplay()
  local d = {}
  for _, row in ipairs(self.rows) do
    d[#d + 1] = { kind = "recipe", row = row }
    if row.recipeID == self.expanded then
      for _, g in ipairs(row.reagents) do d[#d + 1] = { kind = "reagent", g = g, row = row } end
      d[#d + 1] = { kind = "total", row = row }
    end
  end
  self.display = d
end

function K:Toggle(row)
  self.expanded = (self.expanded ~= row.recipeID) and row.recipeID or nil
  self.selected = row.recipeID
  self:ShowDetail(row)
  self:BuildDisplay()
  self.list:SetCount(#self.display)
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.RowSelect(r) -- the selected recipe
  r.sub = W.RowBg(r, C.bg) -- a darker band under an expanded recipe's reagents
  local line = W.Tex(r, C.border, 0.6, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  r.toggle = r:CreateTexture(nil, "ARTWORK")
  r.toggle:SetSize(14, 14)
  r.toggle:SetPoint("LEFT", 10, 0)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = W.Text(r, 12, C.text)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", NAME_RIGHT, 0)
  r.cells = {}
  for _, col in ipairs(COLS) do
    if MONEY[col.key] then
      r.cells[col.key] = W.MoneyCell(r, col.r, MONEY[col.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, true)
      fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[col.key] = fs
    end
  end
  r:SetScript("OnEnter", function(self)
    local id = self.e and (self.e.kind == "reagent" and self.e.g.id or (self.e.kind == "recipe" and self.e.row.rec.o))
    if id then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
      GameTooltip:SetItemByID(id)
      if self.e.kind == "recipe" then K:AddBreakdown(self.e.row) end
      GameTooltip:AddLine(self.e.kind == "recipe" and "|cff9e998fClick to show what it takes to craft.|r" or "|cff9e998fClick to open its chart.|r")
      GameTooltip:Show()
    end
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:SetScript("OnClick", function(self)
    local e = self.e
    if not e then return end
    local id = e.kind == "reagent" and e.g.id or e.row.rec.o
    if IsModifiedClick("CHATLINK") then
      local link = FI:ItemLink(id)
      if link then ChatEdit_InsertLink(link) end
    elseif e.kind == "recipe" then
      K:Toggle(e.row)
    elseif e.kind == "reagent" then
      FI.UI:ShowItem(id)
    else
      K:Toggle(e.row) -- clicking the total line collapses
    end
  end)
  return r
end

local function clearCells(r)
  for _, fs in pairs(r.cells) do fs:SetText(""); setColor(fs, C.text) end
end

-- The numbers behind a recipe, for its tooltip
function K:AddBreakdown(row)
  local soft = C.soft
  local function line(l, v, c)
    c = c or C.text
    GameTooltip:AddDoubleLine(l, v, soft[1], soft[2], soft[3], c[1], c[2], c[3])
  end
  GameTooltip:AddLine(" ")
  if row.noSell then
    line("AH price", "not seen on the AH", C.muted)
  else
    local n = row.rec.n
    line(n == 1 and "AH price" or ("AH price (%s made)"):format(n % 1 == 0 and n or ("%.1f"):format(n)), FI.Coins(row.ahValue))
    line("AH cut (5%)", "-" .. FI.Coins(row.cut), C.down)
    line("You get", FI.Coins(row.sell))
  end
  line("Materials", row.missing > 0 and (FI.Coins(row.cost) .. " + ?") or FI.Coins(row.cost), C.down)
  if row.complete then
    line("Profit", (row.profit >= 0 and "+" or "-") .. FI.Coins(math.abs(row.profit)), row.profit >= 0 and C.up or C.down)
  end
  if row.unlisted then
    GameTooltip:AddLine(("None listed in your latest scan: this is the last price seen (%s ago)."):format(age(row.sellT)), C.gold[1], C.gold[2], C.gold[3], true)
  elseif row.sellT and time() - row.sellT > 86400 then
    GameTooltip:AddLine(("Its price is %s old: scan the AH for a current one."):format(age(row.sellT)), C.gold[1], C.gold[2], C.gold[3], true)
  end
  if (row.unlistedMats or 0) > 0 then
    GameTooltip:AddLine("A material wasn't listed in your latest scan: its cost is the last price seen.", C.gold[1], C.gold[2], C.gold[3], true)
  end
  for _, g in ipairs(row.reagents) do
    if g.how and g.how ~= "listings" and g.how ~= "market" then
      GameTooltip:AddLine(("%s: price from %s%s, not your own scan."):format(FI:ItemName(g.id), g.how,
        g.how == "Auctionator" and " (the lowest listing it saw that day)" or ""), C.gold[1], C.gold[2], C.gold[3], true)
    end
  end
  GameTooltip:AddLine("|cff9e998f/goon price <item> shows where any price comes from.|r")
end

local function updateRecipe(r, row)
  r.on = row.recipeID == K.selected
  r.bg:SetAlpha(r.on and 1 or 0)
  r.sub:SetAlpha(0)
  r.toggle:Show()
  r.toggle:SetTexture(row.recipeID == K.expanded and MINUS or PLUS)
  r.icon:ClearAllPoints()
  r.icon:SetPoint("LEFT", 30, 0)
  r.icon:SetSize(20, 20)
  r.icon:SetTexture(FI:ItemIcon(row.rec.o))
  local made = row.rec.n > 1 and ("  |cff9e998fx%s|r"):format(row.rec.n % 1 == 0 and row.rec.n or ("%.1f"):format(row.rec.n)) or ""
  r.name:SetText(row.name .. made .. staleNote(row))
  r.name:SetTextColor(FI:ItemQualityColor(row.rec.o))
  setCost(r.cells.cost, row)
  if row.noSell then r.cells.sell:SetText("|cff9e998fno AH data|r") else r.cells.sell:SetMoney(row.ahValue) end
  local c = FI.ChangeColor(row.profit)
  if row.complete then
    r.cells.profit:SetMoney(row.profit, true)
    setColor(r.cells.profit, c)
    r.cells.margin:SetText(row.margin and FI.Percent(row.margin) or "-")
    setColor(r.cells.margin, c)
  else
    r.cells.profit:SetText("-"); setColor(r.cells.profit, C.muted)
    r.cells.margin:SetText("-"); setColor(r.cells.margin, C.muted)
  end
  r.cells.sold:SetText(row.soldPerDay and FI.Number(row.soldPerDay) or "-")
  setColor(r.cells.sold, C.text)
end

-- one reagent: "Thorium Bar x2" | 25s 00c each | AH | 50s 00c
local function updateReagent(r, g)
  r.on = false
  r.bg:SetAlpha(0)
  r.sub:SetAlpha(1)
  r.toggle:Hide()
  r.icon:ClearAllPoints()
  r.icon:SetPoint("LEFT", 50, 0)
  r.icon:SetSize(16, 16)
  r.icon:SetTexture(FI:ItemIcon(g.id))
  r.name:SetText(("%s  |cff9e998fx%s|r"):format(FI:ItemName(g.id), g.qty))
  r.name:SetTextColor(FI:ItemQualityColor(g.id))
  clearCells(r)
  if g.price then
    r.cells.cost:SetText(FI.Coins(g.price) .. " ea")
    setColor(r.cells.cost, C.soft)
    local where = g.src == "vendor" and "Vendor" or ((g.how == "Auctionator" or g.how == "import") and "Auctionator" or "AH")
    local stale = g.src == "ah" and (g.unlisted or (g.t and time() - g.t > 86400))
    if g.src == "ah" then
      if g.unlisted then where = "AH · none now"
      elseif stale then where = "AH · " .. age(g.t) .. " old" end
    end
    r.cells.sell:SetText(where)
    setColor(r.cells.sell, stale and C.gold or C.muted)
    r.cells.profit:SetMoney(g.price * g.qty)
    setColor(r.cells.profit, C.soft)
  else
    r.cells.cost:SetText("no price yet")
    setColor(r.cells.cost, C.muted)
    r.cells.profit:SetText("?")
    setColor(r.cells.profit, C.muted)
  end
end

-- the expanded recipe's bottom line: total cost, what it sells for, profit
local function updateTotal(r, row)
  r.on = false
  r.bg:SetAlpha(0)
  r.sub:SetAlpha(1)
  r.toggle:Hide()
  r.icon:ClearAllPoints()
  r.icon:SetPoint("LEFT", 50, 0)
  r.icon:SetSize(16, 16)
  r.icon:SetTexture(nil)
  clearCells(r)
  r.name:SetText(row.noSell and "|cff9e998fTotal to craft|r"
    or ("|cff9e998fTotal to craft  ·  you get %s after the 5%% AH cut|r"):format(FI.Coins(row.sell)))
  setCost(r.cells.cost, row)
  setColor(r.cells.cost, C.text)
  if row.noSell then r.cells.sell:SetText("|cff9e998fno AH data|r") else r.cells.sell:SetMoney(row.ahValue) end
  if row.complete then
    local c = FI.ChangeColor(row.profit)
    r.cells.profit:SetMoney(row.profit, true)
    setColor(r.cells.profit, c)
    r.cells.margin:SetText(row.margin and FI.Percent(row.margin) or "-")
    setColor(r.cells.margin, c)
  else
    r.cells.profit:SetText(row.missing > 0 and "needs prices" or "-")
    setColor(r.cells.profit, C.muted)
  end
end

local function updateRow(r, i)
  local e = K.display[i]
  r.e = e
  if e.kind == "recipe" then updateRecipe(r, e.row)
  elseif e.kind == "reagent" then updateReagent(r, e.g)
  else updateTotal(r, e.row) end
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

  local h = W.Heading(d, "Reagents")
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
    l.price = W.Text(l, 12, C.text, true)
    l.price:SetPoint("RIGHT")
    l.price:SetJustifyH("RIGHT")
    d.lines[i] = l
  end

  local sum = W.Tex(d, C.border)
  sum:SetPoint("TOPLEFT", 14, -84 - 8 * 28 - 4)
  sum:SetPoint("RIGHT", -14, 0)
  sum:SetHeight(1)
  d.totals = {}
  local labels = { "Cost to craft", "AH price, minus the 5% cut", "Profit per craft" }
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
  d.sub:SetText(("%s  ·  makes %s"):format(row.prof, row.rec.n))
  for i, l in ipairs(d.lines) do
    local g = row.reagents[i]
    if g then
      l:Show()
      l.icon:SetTexture(FI:ItemIcon(g.id))
      l.name:SetText(("%s x%d"):format(FI:ItemName(g.id), g.qty))
      l.src:SetText(g.src == "vendor" and "Vendor" or (g.src == "ah" and (g.unlisted and "AH · none now"
        or (g.t and time() - g.t > 86400 and ("AH · " .. age(g.t) .. " old")) or "AH") or "No price"))
      l.price:SetText(g.price and FI.Coins(g.price * g.qty) or "-")
    else
      l:Hide()
    end
  end
  d.totals[1]:SetText(costText(row))
  d.totals[2]:SetText(row.noSell and "no AH data" or (FI.Coins(row.ahValue) .. " = " .. FI.Coins(row.sell)))
  if row.complete then
    local c = FI.ChangeColor(row.profit)
    d.totals[3]:SetText(("%s%s  (%s)"):format(row.profit >= 0 and "+" or "", FI.Coins(row.profit), row.margin and FI.Percent(row.margin) or "-"))
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
  self.profBar:SetSize(300, 26)
  self.profChoice = W.Dropdown(self.profBar, { "All" }, function(v) K.prof = v; K:Refresh() end, 160, "Profession")
  self.profChoice:SetPoint("LEFT")

  local only = W.Button(tab, "Profitable only", nil, 26, "pill")
  only:SetPoint("TOPRIGHT", -16, -16)
  local hint = W.Text(tab, 11, C.muted)
  hint:SetText("Click a column header to sort")
  hint:SetPoint("TOPRIGHT", -18, -59)
  only:SetScript("OnClick", function(self) K.onlyProfit = not K.onlyProfit; self:SetSelected(K.onlyProfit); K:Refresh() end)
  local search = W.EditBox(tab, 150, "Search")
  search:SetPoint("RIGHT", only, "LEFT", -12, 0)
  search:HookScript("OnTextChanged", function(self)
    K.search = self:GetText():lower()
    FI:Debounce("craftsearch", 0.2, function() K:Refresh() end)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -TOP)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)

  local head = W.TableHeader(tbl, 30)
  local cols = { { key = "name", label = "Crafted Item", x = 12, dir = 1 } }
  for _, col in ipairs(COLS) do cols[#cols + 1] = { key = col.key, label = col.label, r = col.r, dir = col.key == "cost" and 1 or -1 } end
  self.headers = W.SortHeaders(head, cols, self.sortState, function() K:Refresh() end)

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
  self.recipeParts = { self.profBar, hint, only, search, tbl }
  self.detail:Hide() -- details now open in place under each recipe
  self.overview = self:BuildOverview(tab)
  tab.Refresh = function() K:Refresh() end
  return tab
end

-- The professions you've scanned can change, so the dropdown's options are refreshed
function K:BuildProfBar()
  local profs = FI.Crafting:Professions()
  local key = table.concat(profs, "|")
  if key ~= self.profKey then
    self.profKey = key
    local values = { "All" }
    for _, p in ipairs(profs) do values[#values + 1] = p end
    self.profChoice:SetEntries(values)
  end
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
  local st = self.sortState
  -- profit and margin only mean something when every reagent has a price
  local get = ({
    profit = function(r) return r.complete and r.profit or nil end,
    margin = function(r) return r.complete and r.margin or nil end,
    sell = function(r) return not r.noSell and r.sell or nil end,
    sold = function(r) return r.soldPerDay end,
  })[st.sort]
  W.SortRows(rows, st.sort, st.dir, get)
  self.rows = rows
  MONEY.cost:Fit(rows, "cost")
  MONEY.sell:Fit(rows, function(row) return not row.noSell and row.ahValue end)
  MONEY.profit:Fit(rows, function(row) return row.complete and row.profit end)
  local fkey = self.prof .. st.sort .. st.dir .. tostring(self.onlyProfit) .. self.search
  if fkey ~= self.lastFilter then self.list.offset = 0; self.lastFilter = fkey end
  self:BuildDisplay()
  self.list:SetCount(#self.display)

  if #FI.Crafting:Professions() == 0 then
    self.empty:SetText("No recipes yet.\nOpen each of your profession windows once and Goonberg reads your recipes.\nThen visit the AH so it has prices.")
    self.empty:Show()
  elseif #rows == 0 then
    self.empty:SetText(self.onlyProfit and "Nothing profitable right now with these filters." or "No recipes match.")
    self.empty:Show()
  else
    self.empty:Hide()
  end
  self.footer:SetText(("%d recipes  ·  %d profitable right now  ·  *profit is after the 5%% AH cut  ·  materials: what buying them costs now (AH listings or vendor)"):format(#all, profitable))

  local keep
  for _, r in ipairs(rows) do if r.recipeID == self.selected then keep = r end end
  self:ShowDetail(keep)
end

-- (scans and merged prices refresh the open tab from the main window)
FI:On("FI_RECIPES_CHANGED", function() if K.frame and K.frame:IsVisible() then K:Refresh() end end)
FI:On("FI_LEDGER_CHANGED", function() if K.frame and K.frame:IsVisible() and K.view == "Overview" then K:Refresh() end end)
-- recipe names the game hadn't loaded yet
FI:On("FI_ITEM_LOADED", function()
  FI:Debounce("craftNames", 0.5, function() if K.frame and K.frame:IsVisible() then K:Refresh() end end)
end)
