-- Goonberg Terminal: Auctions tab
-- Your auctions (read the last time you were at the Auction House) and the mail
-- coming from them: money from sales, and items from auctions that ran out.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.AuctionsTab
local T = { sort = { sort = "ends", dir = 1 } }
FI.AuctionsTab = T
local W = FI.Widgets
local C = FI.colors

local ROW_H = 28
local MAIL_H = 210
local NAME_RIGHT = -680
local COLS = {
  { key = "q", label = "Qty", r = -645, dir = -1 },
  { key = "each", label = "Each", r = -550, dir = -1 },
  { key = "buy", label = "Buyout", r = -455, dir = -1 },
  { key = "bid", label = "Bid", r = -360, dir = -1 },
  { key = "fee", label = "Fee", r = -265, dir = -1 },
  { key = "dep", label = "Deposit", r = -170, dir = -1 },
  { key = "ends", label = "Ends", r = -16, dir = 1 },
}
local MAIL_COLS = {
  { key = "q", label = "Qty", r = -470, nosort = true },
  { key = "gross", label = "Sold for", r = -340, nosort = true },
  { key = "net", label = "You get", r = -210, nosort = true },
  { key = "due", label = "Arrives", r = -16, nosort = true },
}
local MONEY = { each = W.MoneyColumn(), buy = W.MoneyColumn(), bid = W.MoneyColumn(), fee = W.MoneyColumn(), dep = W.MoneyColumn() }
local MAIL_MONEY = { gross = W.MoneyColumn(), net = W.MoneyColumn() }

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- "in 3 h", "in 2 to 8 h", "ended": when an auction runs out
local function endsText(e, now)
  if e.sold then return "|cff66c761Sold|r", -1 end
  if not e.expHi then return "-", math.huge end
  if e.expHi <= now then return "|cff8b95a3ended|r", 0 end
  local lo = math.max(0, (e.expLo or e.expHi) - now)
  local hi = e.expHi - now
  if hi - lo < 300 then return "in " .. FI.Duration(hi), hi end
  return ("in %s to %s"):format(FI.Duration(lo), FI.Duration(hi)), hi
end

local function itemCells(r)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", 12, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = W.Text(r, 12, C.text)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetJustifyH("LEFT")
end

local function showItem(r, id, name, tag)
  r.icon:SetTexture(id and FI:ItemIcon(id) or 134400)
  local n = (id and FI:ItemName(id)) or name or "?"
  r.name:SetText(n .. (tag or ""))
  if id then r.name:SetTextColor(FI:ItemQualityColor(id)) else setColor(r.name, C.text) end
end

local function itemTooltip(self)
  local e = self.entry
  if not e then return end
  GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
  if e.id then GameTooltip:SetItemByID(e.id) else GameTooltip:AddLine(e.n or "?") end
  return e
end

-- ---------------------------------------------------------------------------
-- Your auctions
-- ---------------------------------------------------------------------------
local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.RowBg(r)
  local rule = W.Tex(r, C.border, 0.6, "BORDER")
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  itemCells(r)
  r.name:SetPoint("RIGHT", r, "RIGHT", NAME_RIGHT, 0)
  r.cells = {}
  for _, c in ipairs(COLS) do
    if MONEY[c.key] then
      r.cells[c.key] = W.MoneyCell(r, c.r, MONEY[c.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, true)
      fs:SetPoint("RIGHT", r, "RIGHT", c.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[c.key] = fs
    end
  end
  r:SetScript("OnEnter", function(self)
    local e = itemTooltip(self)
    if not e then return end
    local soft = C.soft
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Auction house", e.m == "neutral" and "Neutral" or "Your faction", soft[1], soft[2], soft[3], 1, 1, 1)
    if e.posted then GameTooltip:AddDoubleLine("Posted", FI.Ago(e.posted), soft[1], soft[2], soft[3], 1, 1, 1) end
    local fee = FI.Auctions.Fee(e)
    if fee then
      GameTooltip:AddDoubleLine(("AH cut (%d%%) if it sells"):format(FI.Auctions.CutRate(e.m) * 100), FI.Coins(fee), soft[1], soft[2], soft[3], 1, 1, 1)
    end
    if e.dep then
      GameTooltip:AddDoubleLine("Deposit", FI.Coins(e.dep) .. " (back if it sells, lost if not)", soft[1], soft[2], soft[3], 1, 1, 1)
    else
      GameTooltip:AddLine("Deposit unknown: Goonberg notes it when you post an auction.", 0.55, 0.58, 0.64, true)
    end
    if e.sold then
      GameTooltip:AddDoubleLine("Sold", e.soldAt and FI.Ago(e.soldAt) or "while you were away", soft[1], soft[2], soft[3], C.up[1], C.up[2], C.up[3])
    elseif e.expHi and e.expLo and e.expHi - e.expLo >= 300 then
      GameTooltip:AddLine("The game only tells you a range for how long is left. Each visit to the Auction House narrows it.", 0.55, 0.58, 0.64, true)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  return r
end

local function updateRow(r, i)
  local row = T.rows[i]
  r.entry = row.e
  if r.bg.SetStripe then r.bg:SetStripe(i) end
  showItem(r, row.e.id, row.e.n, row.e.m == "neutral" and "  |cff8b95a3neutral AH|r" or nil)
  r.cells.q:SetText(FI.Number(row.e.q or 1))
  r.cells.each:SetMoney(row.each)
  r.cells.buy:SetMoney(row.buy)
  r.cells.bid:SetMoney(row.bid)
  setColor(r.cells.bid, row.bid and C.text or C.muted)
  r.cells.fee:SetMoney(row.fee)
  r.cells.dep:SetMoney(row.dep)
  setColor(r.cells.dep, row.dep and C.text or C.muted)
  r.cells.ends:SetText(row.endsText)
end

-- ---------------------------------------------------------------------------
-- Mail on the way
-- ---------------------------------------------------------------------------
local function makeMailRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.RowBg(r)
  local rule = W.Tex(r, C.border, 0.6, "BORDER")
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  itemCells(r)
  r.name:SetPoint("RIGHT", r, "RIGHT", -510, 0)
  r.cells = {}
  for _, c in ipairs(MAIL_COLS) do
    if MAIL_MONEY[c.key] then
      r.cells[c.key] = W.MoneyCell(r, c.r, MAIL_MONEY[c.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, true)
      fs:SetPoint("RIGHT", r, "RIGHT", c.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[c.key] = fs
    end
  end
  r:SetScript("OnEnter", function(self)
    local m = itemTooltip(self)
    if not m then return end
    local soft = C.soft
    GameTooltip:AddLine(" ")
    if m.expired then
      GameTooltip:AddLine("Ran out without selling: the item comes back by mail.", soft[1], soft[2], soft[3], true)
    else
      if m.soldAt then GameTooltip:AddDoubleLine("Sold", date("%H:%M", m.soldAt) .. " (" .. FI.Ago(m.soldAt) .. ")", soft[1], soft[2], soft[3], 1, 1, 1) end
      GameTooltip:AddDoubleLine("Arrives", date("%H:%M", m.due), soft[1], soft[2], soft[3], 1, 1, 1)
      if m.approx then
        GameTooltip:AddLine("Sold while you were away: it arrives by this time at the latest.", 0.55, 0.58, 0.64, true)
      end
      if not m.gross then
        GameTooltip:AddLine("Goonberg hadn't seen this auction's price. Open your auctions at the Auction House once so it knows them.", 0.55, 0.58, 0.64, true)
      end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  return r
end

local function updateMailRow(r, i)
  local m = T.mail[i]
  r.entry = m
  if r.bg.SetStripe then r.bg:SetStripe(i) end
  showItem(r, m.id, m.n, m.expired and "  |cff8b95a3returned|r" or nil)
  r.cells.q:SetText(m.q and FI.Number(m.q) or "-")
  if m.expired then
    r.cells.gross:SetText("-"); r.cells.net:SetText("-")
    setColor(r.cells.net, C.muted)
  else
    r.cells.gross:SetMoney(m.gross)
    r.cells.net:SetMoney(m.net)
    setColor(r.cells.net, m.net and C.up or C.muted)
  end
  local left = m.due - time()
  if left <= 0 then
    r.cells.due:SetText("|cff66c761in your mailbox|r")
  else
    r.cells.due:SetText((m.approx and "by " or "") .. date("%H:%M", m.due) .. "  |cff8b95a3in " .. FI.Duration(left) .. "|r")
  end
end

-- ---------------------------------------------------------------------------
function T:Build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  self.summary = W.Text(f, 13, C.text)
  self.summary:SetPoint("TOPLEFT", 18, -20)
  self.summary:SetPoint("RIGHT", -170, 0)
  self.summary:SetJustifyH("LEFT")

  self.refresh = W.Button(f, "Refresh", 120, 24)
  self.refresh:SetPoint("TOPRIGHT", -16, -14)
  self.refresh:SetScript("OnClick", function()
    if not FI.Auctions:Query() then FI:Print("Open the Auction House to refresh your auctions.") end
  end)
  self.refresh:HookScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Read your auctions again")
    GameTooltip:AddLine("Works at the Auction House. Goonberg also reads them each time you open it.", 0.76, 0.79, 0.83, true)
    GameTooltip:Show()
  end)
  self.refresh:HookScript("OnLeave", GameTooltip_Hide)

  -- your auctions
  local tbl = W.Box(f, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -50)
  tbl:SetPoint("BOTTOMRIGHT", -16, MAIL_H + 26)
  local head = W.TableHeader(tbl, 30)
  local cols = { { key = "name", label = "Your auctions", x = 44, dir = 1 } }
  for _, c in ipairs(COLS) do cols[#cols + 1] = c end
  self.headers = W.SortHeaders(head, cols, self.sort, function() T:Refresh() end)
  local holder = CreateFrame("Frame", nil, tbl)
  holder:SetPoint("TOPLEFT", 1, -31)
  holder:SetPoint("BOTTOMRIGHT", -1, 26)
  self.list = W.List(holder, 16, ROW_H, makeRow, updateRow)
  self.list:SetAllPoints(holder)
  holder:SetScript("OnSizeChanged", function() T.list:SetCount(#(T.rows or {})) end)
  self.empty = W.Text(tbl, 12, C.soft)
  self.empty:SetPoint("TOPLEFT", 24, -50)
  self.empty:SetPoint("RIGHT", -24, 0)
  self.empty:SetJustifyH("LEFT")
  self.empty:SetWordWrap(true)
  self.footer = W.Text(tbl, 11, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 14, 8)
  self.footer:SetPoint("RIGHT", -14, 0)
  self.footer:SetJustifyH("LEFT")

  -- mail on the way
  local mail = W.Box(f, C.panel, C.border)
  mail:SetPoint("BOTTOMLEFT", 16, 16)
  mail:SetPoint("BOTTOMRIGHT", -16, 16)
  mail:SetHeight(MAIL_H)
  local mhead = W.TableHeader(mail, 30)
  local mcols = { { key = "name", label = "Mail on the way", x = 44, nosort = true } }
  for _, c in ipairs(MAIL_COLS) do mcols[#mcols + 1] = c end
  W.SortHeaders(mhead, mcols, {}, function() end)
  local mholder = CreateFrame("Frame", nil, mail)
  mholder:SetPoint("TOPLEFT", 1, -31)
  mholder:SetPoint("BOTTOMRIGHT", -1, 1)
  self.mailList = W.List(mholder, 7, ROW_H, makeMailRow, updateMailRow)
  self.mailList:SetAllPoints(mholder)
  mholder:SetScript("OnSizeChanged", function() T.mailList:SetCount(#(T.mail or {})) end)
  self.mailEmpty = W.Text(mail, 12, C.soft)
  self.mailEmpty:SetPoint("TOPLEFT", 24, -50)
  self.mailEmpty:SetPoint("RIGHT", -24, 0)
  self.mailEmpty:SetJustifyH("LEFT")
  self.mailEmpty:SetWordWrap(true)
  self.mailEmpty:SetText("Nothing on the way. When an auction sells, its money shows here with the time it reaches your mailbox.")

  -- countdowns tick while the tab is open
  local tick = 0
  f:SetScript("OnUpdate", function(_, dt)
    tick = tick + dt
    if tick >= 5 then tick = 0; T:Refresh() end
  end)
  self.rows, self.mail = {}, {}
  return f
end

function T:Refresh()
  if not self.frame then return end
  local A = FI.Auctions
  local d = A:Data()
  local now = time()

  -- sold auctions are listed only under Mail on the way
  local rows, upValue = {}, 0
  for _, e in ipairs(A:All()) do
    if not e.sold then
      local text, sortEnds = endsText(e, now)
      local buy = (e.buy and e.buy > 0) and e.buy or nil
      local bid = (e.bid and e.bid > 0) and e.bid or nil
      rows[#rows + 1] = {
        e = e, name = (e.id and FI:ItemName(e.id)) or e.n or "", q = e.q or 1,
        each = (buy or bid) and A.UnitPrice(e) or nil, buy = buy, bid = bid,
        fee = A.Fee(e), dep = e.dep,
        ends = sortEnds, endsText = text,
      }
      upValue = upValue + (buy or bid or 0)
    end
  end
  local up = #rows
  W.SortRows(rows, self.sort.sort, self.sort.dir)
  self.rows = rows
  for k, col in pairs(MONEY) do col:Fit(rows, k) end
  self.headers:Update()
  self.list:SetCount(#rows)

  local mail = {}
  for _, m in ipairs(d.incoming) do mail[#mail + 1] = m end
  table.sort(mail, function(a, b) return a.due < b.due end)
  self.mail = mail
  for k, col in pairs(MAIL_MONEY) do col:Fit(mail, k) end
  self.mailList:SetCount(#mail)
  self.mailEmpty:SetShown(#mail == 0)

  local coming = 0
  for _, m in ipairs(mail) do coming = coming + (m.net or 0) end
  local parts = {}
  parts[#parts + 1] = ("%d up"):format(up)
  if up > 0 and upValue > 0 then parts[#parts] = parts[#parts] .. " (" .. FI.Coins(upValue) .. " at buyout)" end
  local sold = 0
  for _, m in ipairs(mail) do if not m.expired then sold = sold + 1 end end
  if sold > 0 then parts[#parts + 1] = ("|cff66c761%d sold|r"):format(sold) end
  if coming > 0 then parts[#parts + 1] = FI.Coins(coming) .. " on the way" end
  self.summary:SetText(table.concat(parts, "  ·  "))

  local seen = 0
  for _, t in pairs(d.seen) do seen = math.max(seen, t) end
  self.empty:SetShown(#rows == 0)
  if seen == 0 then
    self.empty:SetText("Open the Auction House once and Goonberg reads your auctions. After that they show here anywhere, and you get a chat message when one sells.")
  else
    self.empty:SetText("No auctions up right now.")
  end
  self.footer:SetText(seen > 0 and ("Read at the Auction House %s. An auction moves to Mail on the way the moment it sells."):format(FI.Ago(seen))
    or "Not read yet: open the Auction House.")
end

local function refreshIfShown()
  if T.frame and T.frame:IsVisible() then FI:Debounce("auctionsTab", 0.2, function() T:Refresh() end) end
end
FI:On("FI_AUCTIONS_CHANGED", refreshIfShown)
FI:On("FI_ITEM_LOADED", refreshIfShown)
