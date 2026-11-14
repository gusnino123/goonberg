-- Goonberg Terminal: market overview (index, movers, sortable and filterable item table)
local _, FI = ...
local O = { cat = "All", move = "All", tf = "24h", sort = "sold", dir = -1, search = "" }
-- Timeframes: which change and sales figures each one uses
local TF = {
  ["15m"] = { chg = "c15", sold = "sold15", win = 900, label = "15M", long = "past 15 minutes" },
  ["1h"] = { chg = "c1", sold = "sold1", win = 3600, label = "1H", long = "past hour" },
  ["6h"] = { chg = "c6", sold = "sold6", win = 6 * 3600, label = "6H", long = "past 6 hours" },
  ["12h"] = { chg = "c12", sold = "sold12", win = 12 * 3600, label = "12H", long = "past 12 hours" },
  ["24h"] = { chg = "c24", sold = "sold24", win = 86400, label = "24H", long = "past 24 hours" },
  ["7d"] = { chg = "c7", sold = "sold7", win = 7 * 86400, label = "7D", long = "past 7 days" },
}
local TF_ORDER = { "15m", "1h", "6h", "12h", "24h", "7d" }
O.TF = TF
FI.OverviewTab = O
local W = FI.Widgets
local C = FI.colors
local H

local ROWS, ROW_H = 40, 28

-- Column layout. Rank and item hang off the left edge; the numbers hang off the
-- right edge (r = offset of the column's right side), so the table can be resized.
local COLS = {
  { key = "rank",  label = "#",          x = 34 },
  { key = "name",  label = "ITEM",       x = 44, left = true },
  { key = "price", label = "PRICE",      r = -404, sort = true },
  { key = "chgA",  label = "24H %",      r = -314, sort = true },
  { key = "chg7",  label = "7D %",       r = -229, sort = true },
  { key = "qty",   label = "LISTINGS",   r = -124, sort = true },
  { key = "sold",  label = "EST. SOLD",  r = -14, sort = true },
}
local NAME_RIGHT = -504 -- item names stop here, before the price column

local function card(parent, title, accent)
  local b = W.Box(parent, C.panel, accent and { 0.23, 0.2, 0.16 } or C.border)
  b:SetHeight(72)
  b.title = W.Heading(b, title)
  b.title:SetPoint("TOPLEFT", 14, -12)
  if accent then b.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
  b.value = W.Text(b, 20, C.text, true)
  b.value:SetPoint("TOPLEFT", 14, -30)
  b.value:SetPoint("RIGHT", -14, 0)
  b.extra = W.Text(b, 12, C.up, true)
  b.extra:SetPoint("LEFT", b.value, "LEFT", 0, 0) -- moved after text is set
  b.sub = W.Text(b, 10, C.muted)
  b.sub:SetPoint("BOTTOMLEFT", 14, 10)
  b.sub:SetPoint("RIGHT", -14, 0)
  return b
end

-- A small chevron drawn with two lines (sort direction)
local function chevron(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(8, 5)
  f.a = W.Line(f, C.gold, 1.5)
  f.b = W.Line(f, C.gold, 1.5)
  function f:SetDown(down)
    if not self.a then return end
    if down then
      self.a:SetStartPoint("TOPLEFT", self, 0, 0); self.a:SetEndPoint("BOTTOM", self, 0, 0)
      self.b:SetStartPoint("BOTTOM", self, 0, 0); self.b:SetEndPoint("TOPRIGHT", self, 0, 0)
    else
      self.a:SetStartPoint("BOTTOMLEFT", self, 0, 0); self.a:SetEndPoint("TOP", self, 0, 0)
      self.b:SetStartPoint("TOP", self, 0, 0); self.b:SetEndPoint("BOTTOMRIGHT", self, 0, 0)
    end
  end
  return f
end

local function makeRow(parent, i)
  local r = CreateFrame("Button", nil, parent)
  r:RegisterForClicks("LeftButtonUp")
  r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
  r.bg:SetAllPoints()
  local line = W.Tex(r, C.border, 0.6, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)

  r.cells = {}
  for _, col in ipairs(COLS) do
    if col.key == "name" then
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(18, 18)
      r.icon:SetPoint("LEFT", col.x, 0)
      r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      r.name = W.Text(r, 12, C.text)
      r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
      r.name:SetPoint("RIGHT", r, "RIGHT", NAME_RIGHT, 0)
      r.cat = W.Text(r, 10, C.muted)
      r.cat:SetPoint("LEFT", r.icon, "RIGHT", 8, 0) -- moved next to the name on update
    else
      local fs = W.Text(r, 12, col.key == "price" and C.gold or C.text, true)
      if col.r then fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0) else fs:SetPoint("RIGHT", r, "LEFT", col.x, 0) end
      fs:SetJustifyH("RIGHT")
      if col.key == "rank" then fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
      r.cells[col.key] = fs
    end
  end

  r:SetScript("OnEnter", function(self)
    self.bg:SetAlpha(0.6)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:AddLine("|cff8b95a3Click to open the chart. Shift-click to link.|r")
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.bg:SetAlpha(0); GameTooltip_Hide() end)
  r:SetScript("OnClick", function(self)
    if IsModifiedClick("CHATLINK") then
      local link = FI:ItemLink(self.itemID)
      if link then ChatEdit_InsertLink(link) end
    else
      FI.UI:ShowItem(self.itemID)
    end
  end)
  return r
end

local function updateRow(r, i)
  local row = O.rows[i]
  r.itemID = row.id
  r.cells.rank:SetText(i)
  r.icon:SetTexture(FI:ItemIcon(row.id))
  r.name:SetText(row.name)
  r.name:SetTextColor(FI:ItemQualityColor(row.id))
  r.cat:ClearAllPoints()
  local room = r.name:GetWidth() or 200
  r.cat:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), room) + 8, 0)
  r.cat:SetShown(r.name:GetStringWidth() + 70 < room)
  r.cat:SetText(row.cat)
  r.cells.price:SetText(FI.Money(row.price))
  local aKey = O:ColAKey()
  local cA, c7 = FI.ChangeColor(row[aKey]), FI.ChangeColor(row.c7)
  r.cells.chgA:SetText(FI.Percent(row[aKey]))
  r.cells.chgA:SetTextColor(cA[1], cA[2], cA[3])
  r.cells.chg7:SetText(FI.Percent(row.c7))
  r.cells.chg7:SetTextColor(c7[1], c7[2], c7[3])
  r.cells.qty:SetText(FI.Number(row.qty))
  r.cells.sold:SetText(FI.Number(row[TF[O.tf].sold]))
end

function O:Build(parent)
  H = FI.History
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab
  self.rows = {}

  -- Summary cards
  local cards = {
    card(tab, "GOONBERG INDEX", true),
    card(tab, "EST. GOLD TRADED"),
    card(tab, "LISTINGS ON AH"),
    card(tab, "TOP GAINER"),
    card(tab, "TOP LOSER"),
  }
  self.cards = cards
  cards[1]:SetPoint("TOPLEFT", 16, -16)
  for i = 2, 5 do cards[i]:SetPoint("TOPLEFT", cards[i - 1], "TOPRIGHT", 12, 0) end
  tab:SetScript("OnSizeChanged", function(_, w)
    local each = (w - 32 - 48) / 5
    for i = 1, 5 do cards[i]:SetWidth(each) end
  end)

  -- Category filter
  local cats = W.Choice(tab, FI.categories, "pill", function(v) O.cat = v; O:Refresh() end, 26)
  cats:SetPoint("TOPLEFT", 16, -102)
  cats:Select(self.cat)

  -- Search, movers, timeframe
  local search = W.EditBox(tab, 240, "Search items")
  search:SetPoint("TOPLEFT", 16, -136)
  search:SetScript("OnTextChanged", function(self)
    if self.ph then self.ph:SetShown(self:GetText() == "") end
    O.search = self:GetText():lower()
    FI:Debounce("ovsearch", 0.2, function() O:Refresh() end)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  local tfs = W.Choice(tab, TF_ORDER, "seg", function(v) O.tf = v; O:Refresh() end, 26)
  tfs:SetPoint("TOPRIGHT", -16, -136)
  tfs:Select(self.tf)
  local moves = W.Choice(tab, { "All", "Gainers", "Losers" }, "seg", function(v) O.move = v; O:Refresh() end, 26)
  moves:SetPoint("RIGHT", tfs, "LEFT", -12, 0)
  moves:Select(self.move)

  -- Table
  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -172)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)

  local head = W.TableHeader(tbl, 30)
  self.headers = {}
  for _, col in ipairs(COLS) do
    local b = CreateFrame("Button", nil, head)
    b:SetHeight(30)
    b.text = W.Heading(b, col.label)
    if col.left then
      b:SetPoint("LEFT", head, "LEFT", col.x, 0)
      b.text:SetPoint("LEFT")
    else
      if col.r then b:SetPoint("RIGHT", head, "RIGHT", col.r, 0) else b:SetPoint("RIGHT", head, "LEFT", col.x, 0) end
      b.text:SetPoint("RIGHT")
      b.text:SetJustifyH("RIGHT")
    end
    b:SetWidth(b.text:GetStringWidth() + 2)
    if col.sort then
      b.arrow = chevron(b)
      b.arrow:SetPoint("RIGHT", b.text, "LEFT", -5, 0)
      b:SetScript("OnClick", function()
        if O.sort == col.key then O.dir = -O.dir else O.sort, O.dir = col.key, -1 end
        O:Refresh()
      end)
      b:SetScript("OnEnter", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
      b:SetScript("OnLeave", function() O:UpdateHeaders() end)
    end
    b.col = col
    self.headers[#self.headers + 1] = b
  end

  local holder = CreateFrame("Frame", nil, tbl)
  holder:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
  holder:SetPoint("BOTTOMRIGHT", tbl, "BOTTOMRIGHT", -1, 26)
  self.list = W.List(holder, ROWS, ROW_H, makeRow, updateRow)
  self.list:SetAllPoints(holder)

  self.empty = W.Text(tbl, 13, C.muted)
  self.empty:SetPoint("CENTER", holder, "CENTER")
  self.empty:SetJustifyH("CENTER")

  self.footer = W.Text(tbl, 10, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 14, 8)
  local note = W.Text(tbl, 10, C.muted)
  note:SetPoint("BOTTOMRIGHT", -14, 8)
  note:SetJustifyH("RIGHT")
  note:SetText("Est. sold = units that left the AH between scans (sold, cancelled or expired)")

  tab.Refresh = function() O:Refresh() end
  return tab
end

function O:UpdateHeaders()
  for _, b in ipairs(self.headers) do
    local on = b.col.key == self.sort
    local c = on and C.gold or C.muted
    b.text:SetTextColor(c[1], c[2], c[3])
    if b.arrow then
      b.arrow:SetShown(on)
      if on then b.arrow:SetDown(self.dir < 0) end
    end
    if b.col.key == "sold" then
      b.text:SetText("EST. SOLD " .. TF[self.tf].label)
      b:SetWidth(b.text:GetStringWidth() + 2)
    elseif b.col.key == "chgA" then
      b.text:SetText((self.tf == "7d" and "24H" or TF[self.tf].label) .. " %")
      b:SetWidth(b.text:GetStringWidth() + 2)
    end
  end
end

-- the first change column shows the chosen timeframe (24h when 7d is chosen)
function O:ColAKey()
  return self.tf == "7d" and "c24" or TF[self.tf].chg
end

local function setCard(c, value, extra, extraValue, sub)
  c.value:SetText(value or "-")
  c.extra:ClearAllPoints()
  c.extra:SetPoint("LEFT", c.value, "LEFT", c.value:GetStringWidth() + 8, -1)
  c.extra:SetText(extra or "")
  local col = FI.ChangeColor(extraValue)
  c.extra:SetTextColor(col[1], col[2], col[3])
  c.sub:SetText(sub or "")
end

function O:Refresh()
  if not self.frame then return end
  local realm = FI:Realm()
  local now = time()
  local data = H.Overview(realm, now)
  local tf = TF[self.tf]

  -- Cards
  local level = H.IndexLevel(realm)
  local ich = H.IndexChange(realm, now, tf.win)
  setCard(self.cards[1], level and ("%.1f"):format(level) or "-", ich and FI.Percent(ich) or "", ich,
    ("Top %d items, weighted by gold traded"):format(H.INDEX_SIZE))
  setCard(self.cards[2], FI.Money(data.gold[tf.sold] or 0), nil, nil, tf.long .. ", estimated")
  setCard(self.cards[3], FI.Number(data.listed), nil, nil, ("%s items tracked"):format(FI.Number(#data.rows)))

  local key = tf.chg
  local up, down
  for _, s in ipairs(data.rows) do
    -- ignore thin markets so one odd listing can't top the list
    if s[key] and (s.qty >= 5 or s.sold7 >= 5) then
      if not up or s[key] > up[key] then up = s end
      if not down or s[key] < down[key] then down = s end
    end
  end
  setCard(self.cards[4], up and FI:ItemName(up.id) or "-", nil, nil, up and FI.Percent(up[key]) or "")
  setCard(self.cards[5], down and FI:ItemName(down.id) or "-", nil, nil, down and FI.Percent(down[key]) or "")
  self.cards[4].value:SetFont(W.FONT, 14, ""); self.cards[5].value:SetFont(W.FONT, 14, "")
  self.cards[4].sub:SetTextColor(C.up[1], C.up[2], C.up[3])
  self.cards[5].sub:SetTextColor(C.down[1], C.down[2], C.down[3])

  -- Rows
  local rows = {}
  for _, s in ipairs(data.rows) do
    local ok = self.cat == "All" or s.cat == self.cat
    if ok and self.move ~= "All" then
      local v = s[key]
      ok = v and ((self.move == "Gainers" and v > 0) or (self.move == "Losers" and v < 0))
    end
    if ok then
      s.name = FI:ItemName(s.id)
      if self.search ~= "" and not s.name:lower():find(self.search, 1, true) then ok = false end
    end
    if ok then rows[#rows + 1] = s end
  end
  local sk, dir = self.sort, self.dir
  local function val(s)
    if sk == "price" then return s.price
    elseif sk == "chgA" then return s[self:ColAKey()]
    elseif sk == "chg7" then return s.c7
    elseif sk == "qty" then return s.qty
    else return s[tf.sold] end
  end
  table.sort(rows, function(a, b)
    local va, vb = val(a), val(b)
    if va == nil and vb == nil then return a.name < b.name end
    if va == nil then return false end -- missing values always last
    if vb == nil then return true end
    if va == vb then return a.name < b.name end
    if dir < 0 then return va > vb else return va < vb end
  end)
  self.rows = rows
  if self.lastFilter ~= (self.cat .. self.move .. self.tf .. self.sort .. self.dir .. self.search) then
    self.list.offset = 0
    self.lastFilter = self.cat .. self.move .. self.tf .. self.sort .. self.dir .. self.search
  end
  self.list:SetCount(#rows)
  self:UpdateHeaders()

  if #data.rows == 0 then
    self.empty:SetText("No market data yet.\nOpen the Auction House: Goonberg Terminal scans it automatically.")
    self.empty:Show()
  elseif #rows == 0 then
    self.empty:SetText("No items match these filters.")
    self.empty:Show()
  else
    self.empty:Hide()
  end
  self.footer:SetText(("Showing %s of %s items  -  scroll for more, shift-scroll pages"):format(FI.Number(#rows), FI.Number(#data.rows)))
end

FI:On("FI_ITEM_LOADED", function()
  FI:Debounce("overview", 0.5, function()
    if O.frame and O.frame:IsShown() then O.list:Refresh() end
  end)
end)
