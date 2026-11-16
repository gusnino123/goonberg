-- Goonberg Terminal: Leaderboard (inside the P&L tab)
-- Who in the guild makes the most on the AH. Only guildmates who chose to share
-- their totals are on it (Sync.lua: P / T messages). Your own row is always shown
-- to you, marked private until you share.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.LeaderboardView
local B = { period = "week", sort = { sort = "total", dir = -1 } }
FI.LeaderboardView = B
local W = FI.Widgets
local C = FI.colors

local ROW_H = 30
local PERIODS = { { "Today", "today" }, { "Last 7 days", "week" }, { "Last 30 days", "month" } }
local COLS = {
  { key = "total", label = "Total made", r = -470, dir = -1 },
  { key = "flip", label = "Flipping", r = -350, dir = -1 },
  { key = "farm", label = "Farming", r = -230, dir = -1 },
  { key = "sales", label = "Sales", r = -130, dir = -1 },
  { key = "t", label = "Updated", r = -16, dir = -1 },
}
local MONEY = { total = W.MoneyColumn(), flip = W.MoneyColumn(), farm = W.MoneyColumn() }
local MEDALS = { { 1, 0.82, 0.25 }, { 0.80, 0.82, 0.86 }, { 0.80, 0.52, 0.30 } } -- gold, silver, bronze

local function ago(t)
  if not t then return "-" end
  local a = time() - t
  if a < 120 then return "just now" end
  if a < 3600 then return math.floor(a / 60) .. " min ago" end
  if a < 86400 then return math.floor(a / 3600) .. " h ago" end
  return math.floor(a / 86400) .. " d ago"
end

local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.RowBg(r)
  local rule = W.Tex(r, C.border, 0.6, "BORDER")
  rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
  r.mine = W.Tex(r, C.gold, 0.10, "BACKGROUND")
  r.mine:SetAllPoints()
  r.rank = W.Text(r, 16, C.soft, true)
  r.rank:SetPoint("CENTER", r, "LEFT", 26, 0)
  r.name = W.Text(r, 13, C.text)
  r.name:SetPoint("LEFT", 52, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", -570, 0)
  r.cells = {}
  for _, c in ipairs(COLS) do
    if MONEY[c.key] then
      r.cells[c.key] = W.MoneyCell(r, c.r, MONEY[c.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.soft, true)
      fs:SetPoint("RIGHT", r, "RIGHT", c.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[c.key] = fs
    end
  end
  r:SetScript("OnEnter", function(self)
    local row = self.row
    if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(row.who .. (row.me and " (you)" or ""))
    local soft = C.soft
    local function line(l, v) GameTooltip:AddDoubleLine(l, v, soft[1], soft[2], soft[3], 1, 1, 1) end
    if row.v then
      line("Total made on the AH", FI.Money(row.v.total))
      line("  flipping (bought, then sold)", FI.Money(row.v.flip))
      line("  farming (found, then sold)", FI.Money(row.v.farm))
      line("Sales", FI.Number(row.v.sales))
    end
    line("Updated", ago(row.t))
    if row.version then line("Goonberg", row.version) end
    if row.me and not FI.Sync:Sharing() then
      GameTooltip:AddLine("Only you see this row: your totals are private until you share them.", 0.55, 0.58, 0.64, true)
    elseif row.stale then
      GameTooltip:AddLine("Nothing from them today yet: they show up once they've been online today.", 0.55, 0.58, 0.64, true)
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  return r
end

local function updateRow(r, i)
  local row = B.rows[i]
  r.row = row
  if r.bg.SetStripe then r.bg:SetStripe(i) end
  r.mine:SetShown(row.me)
  local medal = row.rank and MEDALS[row.rank]
  r.rank:SetText(row.rank and tostring(row.rank) or "-")
  if medal then r.rank:SetTextColor(medal[1], medal[2], medal[3]) else r.rank:SetTextColor(C.soft[1], C.soft[2], C.soft[3]) end
  local tag = ""
  if row.me then tag = FI.Sync:Sharing() and "  |cffe8b84ayou|r" or "  |cff8b95a3you · private|r" end
  r.name:SetText(row.who .. tag)
  if row.v and not row.stale then
    r.cells.total:SetMoney(row.v.total, true)
    r.cells.flip:SetMoney(row.v.flip, true)
    r.cells.farm:SetMoney(row.v.farm, true)
    r.cells.sales:SetText(FI.Number(row.v.sales))
  else
    r.cells.total:SetText("|cff8b95a3not today yet|r")
    r.cells.flip:SetText("-"); r.cells.farm:SetText("-"); r.cells.sales:SetText("-")
  end
  r.cells.t:SetText(row.me and "live" or ago(row.t))
end

function B:Build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local periods = W.Dropdown(f, PERIODS, function(v) B.period = v; B:Refresh() end, 140)
  periods:SetPoint("TOPRIGHT", -16, -14)
  periods:Select(self.period)
  self.periodChoice = periods

  self.ask = W.Button(f, "Ask the guild", 120, 24)
  self.ask:SetPoint("RIGHT", periods, "LEFT", -10, 0)
  self.ask:SetScript("OnClick", function()
    if FI.Sync:RequestTotals() then
      FI:Print("Asked your guild for their totals: sharers answer within a few seconds.")
    else
      FI:Print("Already asked a moment ago (or guild sync is off).")
    end
  end)

  -- sharing: the choice is yours, and it says so
  local share = W.Box(f, C.raised, C.border)
  share:SetPoint("TOPLEFT", 16, -52)
  share:SetPoint("TOPRIGHT", -16, -52)
  share:SetHeight(46)
  share.text = W.Text(share, 12, C.text)
  share.text:SetPoint("LEFT", 14, 0)
  share.text:SetPoint("RIGHT", -170, 0)
  share.text:SetJustifyH("LEFT")
  share.text:SetWordWrap(true)
  share.button = W.Button(share, "Share my totals", 150, 26)
  share.button:SetPoint("RIGHT", -10, 0)
  share.button:SetScript("OnClick", function() FI.Sync:SetSharing(not FI.Sync:Sharing()); B:Refresh() end)
  share.button:HookScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("What your guild sees")
    GameTooltip:AddLine("Your P&L totals for today, 7 and 30 days: total made, flipping, farming and number of sales. Nothing else: not your trades, your gold or your bags.", 0.76, 0.79, 0.83, true)
    GameTooltip:AddLine("Stop any time: your row disappears from everyone's board.", 0.55, 0.58, 0.64, true)
    GameTooltip:Show()
  end)
  share.button:HookScript("OnLeave", GameTooltip_Hide)
  self.share = share

  local tbl = W.Box(f, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -108)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)
  local head = W.TableHeader(tbl, 30)
  local cols = { { key = "rank", label = "#", x = 18, nosort = true }, { key = "who", label = "Player", x = 52, dir = 1 } }
  for _, c in ipairs(COLS) do cols[#cols + 1] = c end
  self.headers = W.SortHeaders(head, cols, self.sort, function() B:Refresh() end)
  local holder = CreateFrame("Frame", nil, tbl)
  holder:SetPoint("TOPLEFT", 1, -31)
  holder:SetPoint("BOTTOMRIGHT", -1, 30)
  self.list = W.List(holder, 20, ROW_H, makeRow, updateRow)
  self.list:SetAllPoints(holder)
  holder:SetScript("OnSizeChanged", function() B.list:SetCount(#(B.rows or {})) end)

  self.empty = W.Text(tbl, 12, C.soft)
  self.empty:SetPoint("TOPLEFT", 24, -100)
  self.empty:SetPoint("RIGHT", -24, 0)
  self.empty:SetJustifyH("LEFT")
  self.empty:SetWordWrap(true)

  self.footer = W.Text(tbl, 11, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 14, 10)
  self.footer:SetPoint("RIGHT", -14, 0)
  self.footer:SetJustifyH("LEFT")
  self.footer:SetText("Only guildmates who share are on the board. Totals come from each player's own P&L (since they installed Goonberg); \"today\" is their own day.")
  self.rows = {}
  return f
end

function B:Refresh()
  if not self.frame then return end
  local Y = FI.Sync
  local sharing = Y:Sharing()
  self.periodChoice:Select(self.period)
  local s = self.share
  if sharing then
    s.text:SetText("|cff66c761You're on the board.|r Your guild sees your totals (today, 7 and 30 days), nothing else.")
    s.button:SetLabel("Stop sharing")
  else
    s.text:SetText("Your totals are private: only you see your row. Share them to join your guild's board (just totals, never your trades or gold).")
    s.button:SetLabel("Share my totals")
  end
  if FI.settings.guildSync == false then
    s.text:SetText("Guild sync is off (/goon sync on), so the board can't be shared or updated.")
  end

  local p = self.period
  local todayStart = Y.PeriodStart("today")
  local rows = {}
  local myName = UnitName("player")
  for who, e in pairs(Y:Board()) do
    if who ~= myName and e[p] then
      -- "today" only counts if they updated today
      local stale = p == "today" and (e.t or 0) < todayStart
      rows[#rows + 1] = { who = who, v = e[p], t = e.t, version = e.v, stale = stale }
    end
  end
  local mine = Y:MyTotals()[p]
  rows[#rows + 1] = { who = myName or "You", v = mine, t = time(), me = true, version = FI.version }

  local key, dir = self.sort.sort, self.sort.dir
  local function val(r)
    if key == "who" then return r.who:lower() end
    if key == "t" then return r.t or 0 end
    if r.stale or not r.v then return -math.huge end
    return r.v[key] or 0
  end
  table.sort(rows, function(a, b)
    local x, y = val(a), val(b)
    if x == y then return a.who < b.who end
    if dir > 0 then return x < y end
    return x > y
  end)
  -- ranks always by total made (the board is about who makes the most)
  local ranked = {}
  for _, r in ipairs(rows) do if r.v and not r.stale then ranked[#ranked + 1] = r end end
  table.sort(ranked, function(a, b)
    if a.v.total ~= b.v.total then return a.v.total > b.v.total end
    return a.who < b.who
  end)
  for i, r in ipairs(ranked) do r.rank = i end
  self.rows = rows
  for k, col in pairs(MONEY) do col:Fit(rows, function(r) return r.v and r.v[k] end) end
  self.list:SetCount(#rows)
  local others = #rows - 1
  self.empty:SetShown(others == 0)
  self.empty:SetText(others == 0 and "Nobody else in your guild is sharing yet. Guildmates need Goonberg 0.31 or newer and turn on \"Share my totals\" (or /goon share on). Ask them, then press \"Ask the guild\"." or "")
end

FI:On("FI_BOARD_CHANGED", function()
  if B.frame and B.frame:IsVisible() then B:Refresh() end
end)
FI:On("FI_LEDGER_CHANGED", function()
  if B.frame and B.frame:IsVisible() then B:Refresh() end
end)
