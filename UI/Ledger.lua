-- Goonberg Terminal: Ledger tab
-- You and one linked guildmate (Partner.lua): each other's Auction House purchases and
-- sales in one list, what each of you paid and got, the sum, and who owes whom.
-- Not linked yet, it shows your own trades and where to link up.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.LedgerTab
local T = { view = "Trades", period = "All", who = "both", sort = { sort = "t", dir = -1 }, itemSort = { sort = "paid", dir = -1 } }
FI.LedgerTab = T
local W = FI.Widgets
local C = FI.colors

local ROW_H = 28
local SUM_H = 86
local PERIODS = { { "Today", "Today" }, { "Last 7 days", "7D" }, { "Last 30 days", "30D" }, { "Since you linked", "Link" }, { "All time", "All" } }
local WHO = { { "Both of you", "both" }, { "Only you", "me" }, { "Only your partner", "them" } }
local CARDS = { "me", "them", "both", "settle" }

local TRADE_NAME_RIGHT = -620
local TRADE_COLS = {
  { key = "who", label = "Who", r = -490, dir = 1 },
  { key = "kind", label = "Type", r = -420, dir = 1 },
  { key = "q", label = "Qty", r = -360, dir = -1 },
  { key = "each", label = "Each", r = -250, dir = -1 },
  { key = "total", label = "Total", r = -140, dir = -1 },
  { key = "t", label = "When", r = -16, dir = -1 },
}
local ITEM_NAME_RIGHT = -640
local ITEM_COLS = {
  { key = "mine", label = "You paid", r = -540, dir = -1 },
  { key = "theirs", label = "Partner paid", r = -410, dir = -1 },
  { key = "paid", label = "Paid together", r = -280, dir = -1 },
  { key = "sold", label = "Sold for", r = -150, dir = -1 },
  { key = "net", label = "Net", r = -16, dir = -1 },
}
local TRADE_MONEY = { each = W.MoneyColumn(), total = W.MoneyColumn() }
local ITEM_MONEY = { mine = W.MoneyColumn(), theirs = W.MoneyColumn(), paid = W.MoneyColumn(), sold = W.MoneyColumn(), net = W.MoneyColumn() }

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function signed(v) return (v >= 0 and "+" or "-") .. FI.Coins(math.abs(v)) end

-- when a period starts ("Since you linked" needs the link)
local function since(period, link)
  local now = time()
  if period == "Today" then
    local d = date("*t", now)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
  end
  if period == "7D" then return now - 7 * 86400 end
  if period == "30D" then return now - 30 * 86400 end
  if period == "Link" then return link and link.at or 0 end
  return 0
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function itemCells(r, right)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("LEFT", 12, 0)
  r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.name = W.Text(r, 12, C.text)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", right, 0)
  r.name:SetJustifyH("LEFT")
end

-- the ledger knows items by name: the icon and color come from the price data, when
-- the item has been seen on the AH
local function showItem(r, name)
  local _, id = FI.Ledger:PriceByName(name)
  r.icon:SetTexture(id and FI:ItemIcon(id) or 134400)
  r.name:SetText(name or "?")
  if id then r.name:SetTextColor(FI:ItemQualityColor(id)) else setColor(r.name, C.text) end
end

local function cells(r, cols, money)
  r.cells = {}
  for _, c in ipairs(cols) do
    if money[c.key] then
      r.cells[c.key] = W.MoneyCell(r, c.r, money[c.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, c.key == "q")
      fs:SetPoint("RIGHT", r, "RIGHT", c.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[c.key] = fs
    end
  end
end

local function newRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.RowBg(r)
  local rule = W.Tex(r, C.border, 0.6, "BORDER")
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  r:SetScript("OnLeave", GameTooltip_Hide)
  return r
end

local function tipLine(l, v) GameTooltip:AddDoubleLine(l, v, C.soft[1], C.soft[2], C.soft[3], 1, 1, 1) end

-- a row whose item the totals leave out is drawn faded
local function fade(r, name) r:SetAlpha(FI.Partner:Counted(name) and 1 or 0.4) end
local function countedTip(name)
  if not FI.Partner:Only() then return end
  if FI.Partner:Counted(name) then
    GameTooltip:AddLine("Counted in the totals above.", 0.4, 0.78, 0.38, true)
  else
    GameTooltip:AddLine("Not counted in the totals above: you picked other items.", 0.55, 0.58, 0.64, true)
  end
end

local function makeTradeRow(parent)
  local r = newRow(parent)
  itemCells(r, TRADE_NAME_RIGHT)
  cells(r, TRADE_COLS, TRADE_MONEY)
  -- a long name is cut short instead of running into the item's
  r.cells.who:SetWidth(110)
  r:SetScript("OnEnter", function(self)
    local row = self.row
    if not row then return end
    local sale = row.kind == "sale"
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(row.name or "?")
    tipLine(row.mine and "You" or row.who, (sale and "sold " or "bought ") .. FI.Number(row.q))
    tipLine("When", date("%b %d, %H:%M", row.t))
    if sale then
      tipLine("Sold for", FI.Coins(row.gross))
      tipLine("AH cut", FI.Coins(row.fee))
      tipLine("Got", FI.Coins(row.gross - row.fee))
    else
      tipLine("Paid", FI.Coins(row.gross))
    end
    if row.q > 1 then tipLine("Each", FI.Coins(row.each)) end
    countedTip(row.name)
    GameTooltip:AddLine("Read from the AH mail, so the time is when the mail was sent.", 0.55, 0.58, 0.64, true)
    GameTooltip:Show()
  end)
  return r
end

local function updateTradeRow(r, i)
  local row = T.rows[i]
  r.row = row
  showItem(r, row.name)
  fade(r, row.name)
  local sale = row.kind == "sale"
  r.cells.who:SetText(row.who)
  setColor(r.cells.who, row.mine and C.gold or C.text)
  r.cells.kind:SetText(sale and "Sold" or "Bought")
  setColor(r.cells.kind, sale and C.up or C.soft)
  r.cells.q:SetText(FI.Number(row.q))
  r.cells.each:SetMoney(row.each)
  r.cells.total:SetMoney(row.total, true)
  setColor(r.cells.total, sale and C.up or C.down)
  r.cells.t:SetText(date("%b %d %H:%M", row.t))
  setColor(r.cells.t, C.soft)
end

local function makeItemRow(parent)
  local r = newRow(parent)
  itemCells(r, ITEM_NAME_RIGHT)
  cells(r, ITEM_COLS, ITEM_MONEY)
  r:SetScript("OnEnter", function(self)
    local it = self.row
    if not it then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(it.name or "?")
    local function person(who, qty, paid, soldQty, sold)
      if qty > 0 then tipLine(who .. " bought " .. FI.Number(qty), FI.Coins(paid) .. "  (" .. FI.Coins(paid / qty) .. " each)") end
      if soldQty > 0 then tipLine(who .. " sold " .. FI.Number(soldQty), FI.Coins(sold) .. "  (" .. FI.Coins(sold / soldQty) .. " each)") end
    end
    person("You", it.myQty, it.mine, it.mySoldQty, it.mySold)
    person(T.partnerName or "Partner", it.theirQty, it.theirs, it.theirSoldQty, it.theirSold)
    local left = it.myQty + it.theirQty - it.mySoldQty - it.theirSoldQty
    if left > 0 then tipLine("Bought but not sold yet", FI.Number(left)) end
    countedTip(it.name)
    GameTooltip:AddLine("Sold amounts are after the AH cut.", 0.55, 0.58, 0.64, true)
    local P = FI.Partner
    local hint
    if not P:Only() then hint = "Click to count only this item in the totals."
    elseif not P:Counted(it.name) then hint = "Click to count this item in the totals too."
    elseif #P:OnlyList() == 1 then hint = "Click to count every item again."
    else hint = "Click to leave this item out of the totals." end
    GameTooltip:AddLine(hint, 1, 0.82, 0, true)
    GameTooltip:Show()
  end)
  r:SetScript("OnClick", function(self)
    if not self.row then return end
    local ok, msg = FI.Partner:ToggleOnly(self.row.name)
    if msg then FI:Print(msg) end
    if ok and self:IsMouseOver() then self:GetScript("OnEnter")(self) end
  end)
  return r
end

local function updateItemRow(r, i)
  local it = T.items[i]
  r.row = it
  showItem(r, it.name)
  fade(r, it.name)
  for _, key in ipairs({ "mine", "theirs", "paid", "sold" }) do
    local cell = r.cells[key]
    if it[key] > 0 then cell:SetMoney(it[key]) else cell:SetText("-") end
    setColor(cell, it[key] > 0 and C.text or C.muted)
  end
  r.cells.net:SetMoney(it.net, true)
  setColor(r.cells.net, it.net >= 0 and C.up or C.down)
end

-- ---------------------------------------------------------------------------
-- Building
-- ---------------------------------------------------------------------------
-- one of the four cards in the summary strip: a heading and three label / amount lines
local function card(parent, labels)
  local c = CreateFrame("Frame", nil, parent)
  c.title = W.Heading(c, "")
  c.title:SetPoint("TOPLEFT", 14, -10)
  c.title:SetPoint("RIGHT", -10, 0)
  c.lines = {}
  for j, label in ipairs(labels or {}) do
    local l = W.Text(c, W.SIZE.hint, C.soft)
    l:SetPoint("TOPLEFT", 14, -13 - j * 17)
    l:SetText(label)
    local v = W.Text(c, W.SIZE.cell, C.text, true)
    v:SetPoint("TOPRIGHT", -14, -12 - j * 17)
    v:SetJustifyH("RIGHT")
    c.lines[j] = v
  end
  return c
end

local function layoutCards()
  local w = T.sum and T.sum:GetWidth() or 0
  if w < 100 then return end
  local cw = math.floor(w / #CARDS)
  for i, key in ipairs(CARDS) do
    local c = T.cards[key]
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", T.sum, "TOPLEFT", (i - 1) * cw, 0)
    c:SetSize(cw, SUM_H)
  end
end

-- says the result where the player is looking (and in chat), for a few seconds
local function say(ok, msg)
  if msg then FI:Print(msg) end
  T.flash = (not ok and msg) and { text = msg, till = GetTime() + 8 } or nil
  T:Refresh()
  if T.flash then C_Timer.After(8.2, function() if T.frame and T.frame:IsVisible() then T:Refresh() end end) end
end

function T:Build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local views = W.Choice(f, { "Trades", "By item" }, "seg", function(v) T.view = v; T:Refresh() end, 26)
  views:SetPoint("TOPLEFT", 16, -14)
  views:Select(self.view)
  self.viewChoice = views

  local periods = W.Dropdown(f, PERIODS, function(v) T.period = v; T:Refresh() end, 150)
  periods:SetPoint("TOPRIGHT", -16, -14)
  periods:Select(self.period)
  self.periodChoice = periods
  local who = W.Dropdown(f, WHO, function(v) T.who = v; T:Refresh() end, 160)
  who:SetPoint("RIGHT", periods, "LEFT", -10, 0)
  who:Select(self.who)
  self.whoChoice = who

  -- the link: who you're linked with, or how to link up
  local box = W.Box(f, C.raised, C.border)
  box:SetPoint("TOPLEFT", 16, -52)
  box:SetPoint("TOPRIGHT", -16, -52)
  box:SetHeight(46)
  box.b2 = W.Button(box, "Unlink", 120, 26)
  box.b2:SetPoint("RIGHT", -10, 0)
  box.b1 = W.Button(box, "Sync now", 120, 26)
  box.b1:SetPoint("RIGHT", box.b2, "LEFT", -8, 0)
  box.b0 = W.Button(box, "Pause", 120, 26)
  box.b0:SetPoint("RIGHT", box.b1, "LEFT", -8, 0)
  for _, b in ipairs({ box.b0, box.b1, box.b2 }) do
    b:SetScript("OnClick", function(self) if self.action then self.action() end end)
    b:HookScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
      GameTooltip:AddLine(self.tip[1])
      GameTooltip:AddLine(self.tip[2], 0.76, 0.79, 0.83, true)
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
  end
  box.edit = W.EditBox(box, 160, "Guildmate's name", true)
  box.edit:SetPoint("RIGHT", box.b2, "LEFT", -12, 0)
  box.edit:SetMaxLetters(48)
  box.edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if box.b2.action then box.b2.action() end
  end)
  box.text = W.Text(box, 12, C.text)
  box.text:SetJustifyH("LEFT")
  box.text:SetWordWrap(true)
  self.box = box

  -- you, your partner, together, and who owes whom
  local sum = W.Box(f, C.panel, C.border)
  sum:SetPoint("TOPLEFT", 16, -106)
  sum:SetPoint("TOPRIGHT", -16, -106)
  sum:SetHeight(SUM_H)
  self.sum = sum
  self.cards = {}
  local labels = { "Bought", "Sold (after AH cut)", "Net" }
  for i, key in ipairs(CARDS) do
    local c = card(sum, key ~= "settle" and labels or nil)
    if i > 1 then
      local rule = W.Tex(c, C.border, 0.6, "BORDER")
      rule:SetPoint("TOPLEFT", 0, -8); rule:SetPoint("BOTTOMLEFT", 0, 8); rule:SetWidth(1)
    end
    self.cards[key] = c
  end
  local settle = self.cards.settle
  settle.title:SetText("Settling Up")
  settle.text = W.Text(settle, 12, C.text)
  settle.text:SetPoint("TOPLEFT", 14, -30)
  settle.text:SetPoint("RIGHT", -12, 0)
  settle.text:SetJustifyH("LEFT")
  settle.text:SetWordWrap(true)
  settle:EnableMouse(true)
  settle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Settling up")
    GameTooltip:AddLine("What the two of you made together in this period (sold after the AH cut, minus bought), split by your shares. Whoever holds more than their share owes the difference.", 0.76, 0.79, 0.83, true)
    GameTooltip:AddLine("Your share is 50% unless you change it: /goon partner split 60", 0.55, 0.58, 0.64, true)
    GameTooltip:AddLine("Gold you trade or mail each other is taken off what's owed. One the addon didn't see: /goon partner paid 500g (or got 500g). /goon partner payments lists them.", 0.76, 0.79, 0.83, true)
    if (T.paidOut or 0) > 0 or (T.paidIn or 0) > 0 then
      tipLine("You paid", FI.Coins(T.paidOut or 0))
      tipLine("You got", FI.Coins(T.paidIn or 0))
    end
    GameTooltip:AddLine("Click items on the By item view to count only those (here and in the cards). /goon partner only clear counts every item again.", 0.55, 0.58, 0.64, true)
    GameTooltip:Show()
  end)
  settle:SetScript("OnLeave", GameTooltip_Hide)
  sum:SetScript("OnSizeChanged", layoutCards)

  -- the two tables share one panel: one is shown
  local tbl = W.Box(f, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -200)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)
  local function tableIn(first, cols, sort, make, update, count)
    local holder = CreateFrame("Frame", nil, tbl)
    holder:SetAllPoints()
    local head = W.TableHeader(holder, 30)
    local all = { { key = "name", label = first, x = 44, dir = 1 } }
    for _, c in ipairs(cols) do all[#all + 1] = c end
    local headers = W.SortHeaders(head, all, sort, function() T:Refresh() end)
    local body = CreateFrame("Frame", nil, holder)
    body:SetPoint("TOPLEFT", 1, -31)
    body:SetPoint("BOTTOMRIGHT", -1, 26)
    local list = W.List(body, 24, ROW_H, make, update)
    list:SetAllPoints(body)
    body:SetScript("OnSizeChanged", function() list:SetCount(count()) end)
    return { holder = holder, list = list, headers = headers }
  end
  self.rows, self.items = {}, {}
  self.tables = {
    Trades = tableIn("Item", TRADE_COLS, self.sort, makeTradeRow, updateTradeRow, function() return #T.rows end),
    ["By item"] = tableIn("Item", ITEM_COLS, self.itemSort, makeItemRow, updateItemRow, function() return #T.items end),
  }
  self.empty = W.Text(tbl, 12, C.soft)
  self.empty:SetPoint("TOPLEFT", 24, -50)
  self.empty:SetPoint("RIGHT", -24, 0)
  self.empty:SetJustifyH("LEFT")
  self.empty:SetWordWrap(true)
  self.footer = W.Text(tbl, 11, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 14, 8)
  self.footer:SetPoint("RIGHT", -14, 0)
  self.footer:SetJustifyH("LEFT")

  f.Refresh = function() T:Refresh() end
  return f
end

-- ---------------------------------------------------------------------------
-- Refreshing
-- ---------------------------------------------------------------------------
-- The link box, by where the link stands. Returns the link when it's on.
local function showLink()
  local P = FI.Partner
  local box = T.box
  local link = P:Link()
  local linked = link ~= nil and link.state == "linked"
  local asker = P:Asker()
  local b0, b1, b2, edit = box.b0, box.b1, box.b2, box.edit
  b0.action, b1.action, b2.action, b0.tip, b1.tip, b2.tip = nil, nil, nil, nil, nil, nil
  local text, buttons, typing = "", 0, false

  if not IsInGuild() then
    text = "Linking ledgers needs a guild: your partner has to be a guildmate."
  elseif linked then
    local got = #(link.entries or {})
    local fresh
    if P.session then fresh = "Their trades are arriving..."
    elseif link.synced then fresh = ("%s of their trades, updated %s."):format(FI.Number(got), FI.Ago(link.synced))
    else fresh = "Their trades arrive when you're both online." end
    text = ("|cff66c761Linked with %s|r since %s. %s"):format(link.name, date("%b %d", link.at or time()), fresh)
    local open = P:Paused()
    if open and time() < open.a then
      text = ("|cffffd100Pausing at %s|r with %s: later trades won't count. %s"):format(date("%H:%M", open.a), link.name, fresh)
    elseif open then
      text = ("|cffffd100Paused since %s|r with %s: trades don't count until you resume. %s"):format(date("%b %d %H:%M", open.a), link.name, fresh)
    end
    buttons = 3
    local surePause = not open and T.confirmPause and GetTime() < T.confirmPause
    b0:SetLabel(open and "Resume" or (surePause and "Really pause?" or "Pause"))
    if open then
      b0.tip = { "Count trades again", ("Trades from now on count again on both Ledger tabs, yours and %s's."):format(link.name) }
      b0.action = function() say(FI.Partner:Resume()) end
    else
      b0.tip = { "Stop counting for now", ("For when you aren't working together. Trades from the moment you pause are left out on both Ledger tabs, yours and %s's, until either of you resumes. %s needs Goonberg 0.43 or newer to see the pause."):format(link.name, link.name) }
      -- two presses, so a stray click doesn't stop the counting for both of you
      b0.action = function()
        if T.confirmPause and GetTime() < T.confirmPause then
          T.confirmPause = nil
          return say(FI.Partner:Pause())
        end
        T.confirmPause = GetTime() + 5
        T:Refresh()
        C_Timer.After(5.2, function() if T.frame and T.frame:IsVisible() then T:Refresh() end end)
      end
    end
    b1:SetLabel("Sync now")
    b1.tip = { "Catch up now", "Asks your partner for their newest trades and sends yours. It happens by itself at login and after each mailbox visit; this is for when you don't want to wait. You both have to be online." }
    b1.action = function() say(FI.Partner:SyncNow()) end
    local sure = T.confirmUnlink and GetTime() < T.confirmUnlink
    b2:SetLabel(sure and "Really unlink?" or "Unlink")
    b2.tip = { "End the link", "Their trades are removed from your Ledger tab and yours from theirs, and nothing more is sent. You can link up again any time." }
    b2.action = function()
      if T.confirmUnlink and GetTime() < T.confirmUnlink then
        T.confirmUnlink = nil
        return say(FI.Partner:Unlink())
      end
      T.confirmUnlink = GetTime() + 5
      T:Refresh()
      C_Timer.After(5.2, function() if T.frame and T.frame:IsVisible() then T:Refresh() end end)
    end
  elseif asker then
    text = ("|cffffd100%s wants to link ledgers with you.|r You'd both see each other's AH purchases and sales here, nothing else."):format(asker)
    buttons = 2
    b1:SetLabel("Accept")
    b1.action = function() say(FI.Partner:Accept(asker)) end
    b2:SetLabel("Decline")
    b2.action = function() say(FI.Partner:Decline(asker)) end
  elseif link then
    text = ("Waiting for %s to accept. They need Goonberg %s or newer: the question shows on their Ledger tab."):format(link.name, P.MIN_VERSION)
    buttons = 1
    b2:SetLabel("Take it back")
    b2.action = function() say(FI.Partner:Unlink()) end
  else
    text = "Link ledgers with one guildmate you trade with. You both see each other's AH purchases and sales here, summed. They have to accept."
    buttons, typing = 1, true
    b2:SetLabel("Link up")
    b2.action = function()
      local ok, msg = FI.Partner:Invite(edit:GetText())
      if ok then edit:SetText("") end
      edit:ClearFocus()
      say(ok, msg)
    end
  end
  if T.flash and GetTime() < T.flash.till then text = "|cffff7366" .. T.flash.text .. "|r" end

  b0:SetShown(buttons == 3)
  b1:SetShown(buttons >= 2)
  b2:SetShown(buttons >= 1)
  edit:SetShown(typing)
  -- the text ends where the controls begin
  local inset = 14
  if typing then inset = 10 + 120 + 12 + 160 + 16
  elseif buttons == 3 then inset = 10 + 3 * 120 + 2 * 8 + 14
  elseif buttons == 2 then inset = 10 + 120 + 8 + 120 + 14
  elseif buttons == 1 then inset = 10 + 120 + 14 end
  box.text:ClearAllPoints()
  box.text:SetPoint("LEFT", 14, 0)
  box.text:SetPoint("RIGHT", box, "RIGHT", -inset, 0)
  box.text:SetText(text)
  return linked and link or nil
end

local function fillCard(c, title, v)
  c.title:SetText(title)
  if not v then
    for _, line in ipairs(c.lines) do line:SetText("-"); setColor(line, C.muted) end
    return
  end
  c.lines[1]:SetText(FI.Coins(v.spent)); setColor(c.lines[1], C.text)
  c.lines[2]:SetText(FI.Coins(v.sold - v.fees)); setColor(c.lines[2], C.text)
  c.lines[3]:SetText(signed(v.net)); setColor(c.lines[3], v.net >= 0 and C.up or C.down)
end

function T:Refresh()
  if not self.frame then return end
  local P = FI.Partner
  local link = showLink()
  self.partnerName = link and link.name or nil
  -- "Since you linked" means nothing without a link
  if not link and self.period == "Link" then self.period = "All" end
  self.viewChoice:Select(self.view)
  self.periodChoice:Select(self.period)
  self.whoChoice:Select(self.who)

  local all, paused = P:Trades(since(self.period, link))
  local totals = P:Totals(all)
  layoutCards()
  fillCard(self.cards.me, "You", totals.me)
  fillCard(self.cards.them, link and link.name or "Partner", link and totals.them or nil)
  fillCard(self.cards.both, "Together", link and totals.both or nil)
  local settle = self.cards.settle
  if link then
    local pct = P:Split()
    local from = since(self.period, link)
    local owe = P:Settle(totals, pct, from)
    local _, out, inn = P:Payments(from)
    T.paidOut, T.paidIn = out, inn
    local line
    if math.abs(owe) < 1 then line = "|cff66c761You're even.|r"
    elseif owe > 0 then line = ("You owe %s |cffffd100%s|r."):format(link.name, FI.Coins(owe))
    else line = ("%s owes you |cffffd100%s|r."):format(link.name, FI.Coins(-owe)) end
    local n = #P:OnlyList()
    local scope = n > 0 and (" on %d picked item%s"):format(n, n == 1 and "" or "s") or ""
    local paid = ""
    if out ~= inn then paid = (", after %s you %s"):format(FI.Coins(math.abs(out - inn)), out > inn and "paid" or "got") end
    settle.text:SetText(("%s\n|cff9e998fSplit %d / %d of %s made together%s%s.|r"):format(line, pct, 100 - pct, signed(totals.both.net), scope, paid))
  else
    settle.text:SetText("|cff9e998fLink up with a guildmate to see both sides and who owes whom.|r")
  end

  -- the tables show who you picked; the cards above always show both
  local rows = {}
  for _, r in ipairs(all) do
    if self.who == "both" or (self.who == "me") == r.mine then rows[#rows + 1] = r end
  end
  local items = P:Items(rows)
  W.SortRows(rows, self.sort.sort, self.sort.dir)
  W.SortRows(items, self.itemSort.sort, self.itemSort.dir)
  self.rows, self.items = rows, items
  for k, col in pairs(TRADE_MONEY) do col:Fit(rows, k) end
  for k, col in pairs(ITEM_MONEY) do col:Fit(items, k) end
  for name, t in pairs(self.tables) do
    t.holder:SetShown(name == self.view)
    t.headers:Update()
  end
  self.tables.Trades.list:SetCount(#rows)
  self.tables["By item"].list:SetCount(#items)

  self.empty:SetShown(#rows == 0)
  if #all == 0 and self.period == "All" then
    self.empty:SetText("No Auction House trades yet. Goonberg reads your purchases and sales from the AH mail: open a mailbox and they show up here.")
  else
    self.empty:SetText("Nothing here for this period.")
  end
  local only = P:OnlyList()
  if #only > 0 then
    self.footer:SetText(("|cffffd100The totals count only %s.|r Faded rows are left out. Click an item on By item to change it; /goon partner only clear counts every item."):format(
      #only <= 3 and table.concat(only, ", ") or (#only .. " picked items")))
  else
    self.footer:SetText(link and "Trades come from each player's AH mail, read when they open a mailbox. Net is sold (after the AH cut) minus bought, so stock not sold yet counts as spent. Click an item on By item to count only it."
      or "Your AH purchases and sales, from your AH mail. Net is sold (after the AH cut) minus bought, so stock not sold yet counts as spent. Click an item on By item to count only it.")
  end
  if paused > 0 then
    self.footer:SetText(("|cffffd100%s trade%s made while paused %s left out.|r "):format(FI.Number(paused), paused == 1 and "" or "s", paused == 1 and "is" or "are") .. self.footer:GetText())
  end
end

local function refreshIfShown()
  if T.frame and T.frame:IsVisible() then FI:Debounce("ledgerTab", 0.3, function() T:Refresh() end) end
end
FI:On("FI_PARTNER_CHANGED", refreshIfShown)
FI:On("FI_LEDGER_CHANGED", refreshIfShown)
FI:On("FI_ITEM_LOADED", refreshIfShown)
