-- Goonberg Terminal: market overview (index, movers, sortable and filterable item table)
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.OverviewTab
local O = { cat = "All", move = "All", tf = "24h", sort = "sold", dir = -1, search = "", minP = nil, maxP = nil }
-- Timeframes: which change and sales figures each one uses
local TF = {
  ["15m"] = { chg = "c15", sold = "sold15", win = 900, label = "15m", long = "past 15 minutes" },
  ["1h"] = { chg = "c1", sold = "sold1", win = 3600, label = "1h", long = "past hour" },
  ["6h"] = { chg = "c6", sold = "sold6", win = 6 * 3600, label = "6h", long = "past 6 hours" },
  ["12h"] = { chg = "c12", sold = "sold12", win = 12 * 3600, label = "12h", long = "past 12 hours" },
  ["24h"] = { chg = "c24", sold = "sold24", win = 86400, label = "24h", long = "past 24 hours" },
  ["7d"] = { chg = "c7", sold = "sold7", win = 7 * 86400, label = "7d", long = "past 7 days" },
}
local TF_ENTRIES = {
  { "15 min", "15m" }, { "1 hour", "1h" }, { "6 hours", "6h" }, { "12 hours", "12h" }, { "24 hours", "24h" }, { "7 days", "7d" },
}
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
  { key = "name",  label = "Item",       x = 44, left = true },
  { key = "price", label = "Price",      r = -404, sort = true },
  { key = "chgA",  label = "24h %",      r = -314, sort = true },
  { key = "chg7",  label = "7d %",       r = -229, sort = true },
  { key = "qty",   label = "Listings",   r = -124, sort = true },
  { key = "sold",  label = "Est. Sold",  r = -14, sort = true },
}
local NAME_RIGHT = -504 -- item names stop here, before the price column
local PRICE = W.MoneyColumn()

local function card(parent, title, accent)
  local b = W.Box(parent, C.panel, accent and { 0.23, 0.2, 0.16 } or C.border)
  b:SetHeight(78)
  b.title = W.Heading(b, title)
  b.title:SetPoint("TOPLEFT", 14, -12)
  if accent then b.title:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end
  b.value = W.Text(b, 20, C.text, true)
  b.value:SetPoint("TOPLEFT", 14, -29)
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
    elseif col.key == "price" then
      r.cells.price = W.MoneyCell(r, col.r, PRICE)
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, true)
      if col.r then fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0) else fs:SetPoint("RIGHT", r, "LEFT", col.x, 0) end
      fs:SetJustifyH("RIGHT")
      if col.key == "rank" then fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
      r.cells[col.key] = fs
    end
  end

  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:AddLine("|cff9e998fClick to open the chart. Shift-click to link.|r")
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
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
  if row.loading then row.name, row.loading = FI:ItemName(row.id); row.lname = nil end
  r.name:SetText(row.name)
  r.name:SetTextColor(FI:ItemQualityColor(row.id))
  r.cat:ClearAllPoints()
  local room = r.name:GetWidth() or 200
  r.cat:SetPoint("LEFT", r.name, "LEFT", math.min(r.name:GetStringWidth(), room) + 8, 0)
  r.cat:SetShown(r.name:GetStringWidth() + 70 < room)
  r.cat:SetText(row.cat)
  r.cells.price:SetMoney(row.price)
  local aKey = O:ColAKey()
  local cA, c7 = FI.ChangeColor(row[aKey]), FI.ChangeColor(row.c7)
  r.cells.chgA:SetText(FI.Percent(row[aKey]))
  if row.thin then cA = C.muted end -- 1-2 listings: shown, but greyed (could be one seller)
  r.cells.chgA:SetTextColor(cA[1], cA[2], cA[3])
  r.cells.chg7:SetText(FI.Percent(row.c7))
  if row.thin then c7 = C.muted end
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
    card(tab, "Goonberg Index", true),
    card(tab, "Est. Gold Traded"),
    card(tab, "Listings on AH"),
    card(tab, "Top Gainer"),
    card(tab, "Top Loser"),
  }
  self.cards = cards
  cards[1]:SetPoint("TOPLEFT", 16, -16)
  for i = 2, 5 do cards[i]:SetPoint("TOPLEFT", cards[i - 1], "TOPRIGHT", 12, 0) end
  tab:SetScript("OnSizeChanged", function(_, w)
    local each = (w - 32 - 48) / 5
    for i = 1, 5 do cards[i]:SetWidth(each) end
  end)

  -- Filter row: search on the left (it takes whatever width is left), then the price
  -- range; hide, category, movers and time frame on the right. Each control's name
  -- sits above it, so the row fits the narrowest window.
  local ROW_Y = -122
  local function above(ctrl, text)
    local fs = W.Text(tab, 11, C.soft)
    fs:SetText(text)
    fs:SetPoint("BOTTOMLEFT", ctrl, "TOPLEFT", 2, 3)
    return fs
  end

  local tfs = W.Dropdown(tab, TF_ENTRIES, function(v) O.tf = v; O:Refresh() end, 110)
  tfs:SetPoint("TOPRIGHT", -16, ROW_Y)
  tfs:Select(self.tf)
  above(tfs, "Time frame")
  local moves = W.Dropdown(tab, { { "Gainers & losers", "All" }, "Gainers", "Losers" }, function(v) O.move = v; O:Refresh() end, 140)
  moves:SetPoint("RIGHT", tfs, "LEFT", -12, 0)
  moves:Select(self.move)
  above(moves, "Movers")
  local cats = W.Dropdown(tab, FI.categories, function(v) O.cat = v; O:Refresh() end, 130)
  cats:SetPoint("RIGHT", moves, "LEFT", -12, 0)
  cats:Select(self.cat)
  above(cats, "Category")
  -- categories to leave out of the list (and the top gainer/loser), kept between sessions
  local hideList = {}
  for _, c in ipairs(FI.categories) do if c ~= "All" then hideList[#hideList + 1] = c end end
  local hide = W.CheckDropdown(tab, hideList,
    function(c) return O:Hidden()[c] == true end,
    function(c)
      local h = O:Hidden()
      h[c] = not h[c] or nil
      O.list.offset = 0
      O:Refresh()
    end, 130, nil,
    function()
      local n, first = 0, nil
      for _, c in ipairs(hideList) do if O:Hidden()[c] then n = n + 1; first = first or c end end
      if n == 0 then return "Nothing" end
      return n == 1 and first or (first .. " +" .. (n - 1))
    end)
  hide:SetPoint("RIGHT", cats, "LEFT", -12, 0)
  above(hide, "Hide")

  -- price range per unit (1g50s, 75s, 1.5 = gold); either box may be blank
  local function priceBox(hint, field)
    local e = W.EditBox(tab, 70, hint, true)
    e:HookScript("OnTextChanged", function(self)
      local t = self:GetText()
      local v = FI.ParseMoney(t)
      O[field] = (v and v > 0) and v or nil
      -- red text while what's typed isn't a price
      local bad = t:gsub("%s", "") ~= "" and not v
      local c = bad and C.down or C.text
      self:SetTextColor(c[1], c[2], c[3])
      FI:Debounce("ovprice", 0.3, function() O:Refresh() end)
    end)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("Price per unit")
      GameTooltip:AddLine("Type 1g50s, 75s or 1.5 (gold). Leave a box blank for no limit.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    e:HookScript("OnLeave", GameTooltip_Hide)
    return e
  end
  local maxBox = priceBox("max", "maxP")
  maxBox:SetPoint("RIGHT", hide, "LEFT", -20, 0)
  local to = W.Text(tab, 12, C.soft)
  to:SetText("to")
  to:SetPoint("RIGHT", maxBox, "LEFT", -6, 0)
  local minBox = priceBox("min", "minP")
  minBox:SetPoint("RIGHT", to, "LEFT", -6, 0)
  above(minBox, "Price")

  local search = W.EditBox(tab, 240, "Search items")
  search:SetPoint("TOPLEFT", 16, ROW_Y)
  search:SetPoint("RIGHT", minBox, "LEFT", -20, 0)
  search:HookScript("OnTextChanged", function(self)
    O.search = self:GetText():lower()
    FI:Debounce("ovsearch", 0.2, function() O:Refresh() end)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  -- Table
  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, ROW_Y - 36)
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
      b.arrow:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
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
  note:SetText("Grey % = only 1-2 listed (could be one seller)   ·   Est. sold = units gone between scans")

  tab.Refresh = function() O:Refresh() end
  return tab
end

function O:UpdateHeaders()
  for _, b in ipairs(self.headers) do
    local on = b.col.key == self.sort
    local c = on and C.gold or C.soft
    b.text:SetTextColor(c[1], c[2], c[3])
    if b.arrow then
      b.arrow:SetShown(on)
      if on then b.arrow:SetDown(self.dir < 0) end
      -- right-aligned headers make room for the arrow so it sits beside its own column
      if not b.col.left then
        b.text:ClearAllPoints()
        b.text:SetPoint("RIGHT", b, "RIGHT", on and -12 or 0, 0)
      end
    end
    if b.col.key == "sold" then
      b.text:SetText("Est. Sold " .. TF[self.tf].label)
      b:SetWidth(b.text:GetStringWidth() + 2)
    elseif b.col.key == "chgA" then
      b.text:SetText((self.tf == "7d" and "24h" or TF[self.tf].label) .. " %")
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

function O:Hidden()
  FI.settings.ovHide = FI.settings.ovHide or {}
  return FI.settings.ovHide
end

function O:Refresh()
  if not self.frame then return end
  local hidden = self:Hidden()
  local realm = FI:Realm()
  local now = time()
  local data, building = H.OverviewAsync(realm, now)
  if building then self:SetBuilding(true) end
  if not data then return end -- first build still running; FI_OVERVIEW_READY refreshes
  local tf = TF[self.tf]

  -- Cards
  local level = H.IndexLevel(realm)
  local ich = H.IndexChange(realm, now, tf.win)
  setCard(self.cards[1], level and ("%.1f"):format(level) or "-", ich and FI.Percent(ich) or "", ich,
    ("Top %d items by gold traded"):format(H.INDEX_SIZE))
  setCard(self.cards[2], FI.Coins(data.gold[tf.sold] or 0), nil, nil, tf.long .. ", estimated")
  setCard(self.cards[3], FI.Number(data.listed), nil, nil, ("%s items tracked"):format(FI.Number(#data.rows)))

  local key = tf.chg
  local up, down
  for _, s in ipairs(data.rows) do
    -- ignore thin markets so one odd listing can't top the list
    -- top gainer/loser: on the AH now with a real market (5+ listed), not one seller
    if s[key] and s.onAH and s.qty >= 5 and not hidden[s.cat] then
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
    -- picking a category by name shows it even if it's also hidden
    local ok = (self.cat == "All" and not hidden[s.cat]) or s.cat == self.cat
    if ok and (self.minP or self.maxP) then
      local p = s.price
      ok = p and (not self.minP or p >= self.minP) and (not self.maxP or p <= self.maxP) or false
    end
    if ok and self.move ~= "All" then
      local v = s[key]
      ok = v and not s.thin and ((self.move == "Gainers" and v > 0) or (self.move == "Losers" and v < 0))
    end
    if ok then
      -- looked up once per scan, not every refresh (again if the game was still loading it)
      if not s.name or s.loading then s.name, s.loading = FI:ItemName(s.id); s.lname = nil end
      if self.search ~= "" then
        s.lname = s.lname or s.name:lower()
        if not s.lname:find(self.search, 1, true) then ok = false end
      end
    end
    if ok then rows[#rows + 1] = s end
  end
  local sk, dir = self.sort, self.dir
  local function val(s)
    if sk == "price" then return s.price
    -- sorting by change puts thin markets (1-2 listed) after real ones
    elseif sk == "chgA" then return not s.thin and s[self:ColAKey()] or nil
    elseif sk == "chg7" then return not s.thin and s.c7 or nil
    elseif sk == "qty" then return s.qty
    else return s[tf.sold] end
  end
  -- work out each row's sort value once, not on every comparison
  for i = 1, #rows do local r = rows[i]; r._sv = val(r) or false end
  table.sort(rows, function(a, b)
    local va, vb = a._sv, b._sv
    if va == false then va = nil end
    if vb == false then vb = nil end
    if va == nil and vb == nil then return a.name < b.name end
    if va == nil then return false end -- missing values always last
    if vb == nil then return true end
    if va == vb then return a.name < b.name end
    if dir < 0 then return va > vb else return va < vb end
  end)
  self.rows = rows
  PRICE:Fit(rows, "price")
  local filterKey = table.concat({ self.cat, self.move, self.tf, self.sort, self.dir, self.search,
    self.minP or "", self.maxP or "" }, "|")
  if self.lastFilter ~= filterKey then
    self.list.offset = 0
    self.lastFilter = filterKey
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
  self.footer:SetText(("Showing %s of %s items  ·  scroll for more, shift-scroll pages"):format(FI.Number(#rows), FI.Number(#data.rows)))
end

function O:SetBuilding(on)
  if not self.frame then return end
  if not self.busy then
    self.busy = self.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.busy:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -12, 6)
    self.busy:SetText("Updating market data...")
  end
  self.busy:SetShown(on)
end

FI:On("FI_OVERVIEW_READY", function()
  O:SetBuilding(false)
  if O.frame and O.frame:IsVisible() then O:Refresh() end
end)

FI:On("FI_ITEM_LOADED", function()
  FI:Debounce("overview", 0.5, function()
    if O.frame and O.frame:IsShown() then O.list:Refresh() end
  end)
end)
