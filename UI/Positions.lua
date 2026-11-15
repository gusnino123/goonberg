-- Goonberg Terminal: Positions (inside the P&L tab)
-- Every chain from buying to selling, like a broker's trade history: what you
-- bought and at what price, what you crafted or disenchanted it into, what you sold
-- it for, and what the whole thing made. Click a position to see each step.
local _, FI = ...
local V = { show = "All", sort = { sort = "last", dir = -1 }, expanded = {} }
FI.PositionsView = V
local W = FI.Widgets
local C = FI.colors

local ROW_H = 28
local EMPTY = "No positions yet. Buy something on the AH and sell it again, or craft or disenchant it first: each chain from buy to sale shows up here with its P&L. (Open your mailbox after trading so the AH invoices get read.)"
local COLS = {
  { key = "last", label = "DATE", at = -636, dir = -1 },
  { key = "status", label = "STATUS", at = -566, dir = 1 },
  { key = "cost", label = "COST", r = -426 },
  { key = "proceeds", label = "SOLD FOR", r = -326 },
  { key = "held", label = "HELD (WORTH)", r = -206 },
  { key = "realized", label = "P&L", r = -94 },
  { key = "roi", label = "ROI", r = -16 },
}
local CELL_R = { cost = -426, proceeds = -326, held = -206, realized = -94, roi = -16 }

local function hex(c) return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
local function signed(v)
  return ("|cff%s%s%s|r"):format(v >= 0 and "3fb68b" or "f0603a", v >= 0 and "+" or "-", FI.Money(math.abs(v)))
end
local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function each(total, n) return FI.Money(math.floor(total / math.max(1, n) + 0.5)) end
local function key(g) return g.opened .. "|" .. g.name end

-- what one step says
local ACTIONS = {
  buy = { "Bought", C.down }, craft = { "Crafted", C.gold }, de = { "Disenchanted", C.gold },
  use = { "Used", C.soft }, sale = { "Sold", C.up }, vendor = { "Vendored", C.soft },
}
local function describe(st)
  local e = st.e
  if st.kind == "buy" then
    return ("%d %s  @ %s each"):format(st.q, e.i, each(st.cost, st.q))
  elseif st.kind == "craft" then
    local mats = {}
    for _, m in ipairs(st.mats or {}) do
      local tag = m.vendor and " (vendor)" or ((m.bought < m.n) and (m.bought > 0 and " (part yours)" or " (yours)") or "")
      mats[#mats + 1] = ("%d %s%s"):format(m.n, m.name, tag)
    end
    return ("%d %s  from %s"):format(st.q, e.i, table.concat(mats, " + "))
  elseif st.kind == "de" then
    local outs = {}
    for _, o in ipairs(st.outs or {}) do outs[#outs + 1] = ("%d %s"):format(o[2], o[1]) end
    return ("%s  into %s"):format(e.i, #outs > 0 and table.concat(outs, " + ") or "?")
  elseif st.kind == "use" then
    return ("%d %s  yourself"):format(st.q, e.i)
  else
    local farmed = (st.of or st.q) - st.q
    if st.vendor then return ("%d %s  to a vendor @ %s each"):format(st.q, e.i, each(st.gross, st.q)) end
    return ("%d %s  @ %s each%s"):format(st.q, e.i, each(st.gross, st.q),
      farmed > 0 and ("  (+%d farmed, not counted)"):format(farmed) or "")
  end
end

-- ---------------------------------------------------------------------------
local function stat(parent, label)
  local f = W.Box(parent, C.panel, C.border)
  f.label = W.Heading(f, label)
  f.label:SetPoint("TOPLEFT", 14, -10)
  f.value = W.Text(f, 18, C.text, true)
  f.value:SetPoint("TOPLEFT", 14, -26)
  f.value:SetPoint("RIGHT", -10, 0)
  f.sub = W.Text(f, 11, C.muted)
  f.sub:SetPoint("TOPLEFT", 14, -48)
  f.sub:SetPoint("RIGHT", -10, 0)
  return f
end

local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
  r.bg:SetAllPoints()
  local line = W.Tex(r, C.border, 0.6, "BORDER")
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  r.bar = W.Tex(r, C.gold, 1, "BORDER")
  r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(3)
  r.arrow = W.Chevron(r)
  r.arrow:SetPoint("LEFT", 14, 0)
  r.name = W.Text(r, 12, C.text)
  r.name:SetPoint("LEFT", 32, 0)
  r.name:SetPoint("RIGHT", r, "RIGHT", -644, 0)
  r.date = W.Text(r, 11, C.soft)
  r.date:SetPoint("LEFT", r, "RIGHT", -636, 0)
  r.status = W.Text(r, 11, C.soft)
  r.status:SetPoint("LEFT", r, "RIGHT", -566, 0)
  r.cells = {}
  for k, x in pairs(CELL_R) do
    local fs = W.Text(r, 12, C.text, true)
    fs:SetPoint("RIGHT", r, "RIGHT", x, 0)
    fs:SetJustifyH("RIGHT")
    r.cells[k] = fs
  end
  -- a step inside an open position
  r.sDate = W.Text(r, 11, C.muted)
  r.sDate:SetPoint("LEFT", 40, 0)
  r.sAction = W.Text(r, 11, C.text)
  r.sAction:SetPoint("LEFT", 128, 0)
  r.sText = W.Text(r, 11, C.soft)
  r.sText:SetPoint("LEFT", 222, 0)
  r.sText:SetPoint("RIGHT", r, "RIGHT", -500, 0)

  r:SetScript("OnClick", function(self)
    local row = self.row
    if row and row.kind == "pos" then
      local k = key(row.g)
      V.expanded[k] = not V.expanded[k] or nil
      V:Refresh()
    end
  end)
  r:SetScript("OnEnter", function(self)
    local row = self.row
    if not row or row.kind ~= "pos" then return end
    self.bg:SetAlpha(0.6)
    local g, soft = row.g, C.soft
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:AddLine(g.name)
    local function line(l, v, c) c = c or C.text; GameTooltip:AddDoubleLine(l, v, soft[1], soft[2], soft[3], c[1], c[2], c[3]) end
    line("Status", g.status == "open" and "Open" or "Closed", g.status == "open" and C.gold or C.soft)
    line("Opened", date("%b %d %H:%M", g.opened))
    if g.closed then line("Closed", date("%b %d %H:%M", g.closed)) end
    line("Cost", FI.Money(g.cost))
    if g.own > 0 then line("  of which your own / vendor materials", FI.Money(g.own)) end
    if g.proceeds > 0 then line("Sold for (after the AH cut)", FI.Money(g.proceeds)); line("  AH cut paid", FI.Money(g.fees)) end
    line("Realized P&L", (g.realized >= 0 and "+" or "-") .. FI.Money(math.abs(g.realized)), g.realized >= 0 and C.up or C.down)
    if g.roi then line("ROI on what you sold", FI.Percent(g.roi), g.roi >= 0 and C.up or C.down) end
    if g.usedCost > 0 then line("Used yourself", FI.Money(g.usedCost)) end
    if g.openUnits > 0 then
      line("Still held", ("%d unit%s, cost %s"):format(g.openUnits, g.openUnits == 1 and "" or "s", FI.Money(g.openCost)))
      line("Worth now (after the AH cut)", FI.Money(g.openValue), C.gold)
      line("Unrealized", (g.unrealized >= 0 and "+" or "-") .. FI.Money(math.abs(g.unrealized)), g.unrealized >= 0 and C.up or C.down)
      if g.unpriced > 0 then GameTooltip:AddLine(("%d unit(s) have no market price yet: scan the AH."):format(g.unpriced), 0.55, 0.58, 0.64) end
    end
    GameTooltip:AddLine(V.expanded[key(g)] and "|cff8b95a3Click to hide the steps.|r" or "|cff8b95a3Click to see each step.|r")
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.bg:SetAlpha(self.row and self.row.kind == "pos" and 0.25 or 0); GameTooltip_Hide() end)
  return r
end

local function clear(r)
  for _, fs in pairs(r.cells) do fs:SetText("") end
  r.name:SetText(""); r.date:SetText(""); r.status:SetText("")
  r.sDate:SetText(""); r.sAction:SetText(""); r.sText:SetText("")
end

local function updateRow(r, i)
  local row = V.rows[i]
  r.row = row
  clear(r)
  local pos = row.kind == "pos"
  r.bar:SetShown(pos and V.expanded[key(row.g)] or false)
  r.arrow:SetShown(pos)
  r.bg:SetAlpha(pos and 0.25 or 0)
  local g = row.g
  if pos then
    if V.expanded[key(g)] then r.arrow:SetDown(true) else r.arrow:SetRight() end
    local tags = {}
    if g.crafted then tags[#tags + 1] = "crafted" end
    if g.disenchanted then tags[#tags + 1] = "DE'd" end
    if g.deal then tags[#tags + 1] = "|cffe8b84aDeals tab|r" end
    if g.legacy then tags[#tags + 1] = "|cfff0613aold data, quantity may be off|r" end
    r.name:SetText(g.name .. (#tags > 0 and ("  |cff8b95a3" .. table.concat(tags, " · ") .. "|r") or ""))
    r.date:SetText(date("%b %d", g.last))
    if g.status == "open" then
      r.status:SetText("Open"); setColor(r.status, C.gold)
    else
      r.status:SetText("Closed"); setColor(r.status, C.soft)
    end
    r.cells.cost:SetText(FI.Coins(g.cost)); setColor(r.cells.cost, C.text)
    r.cells.proceeds:SetText(g.proceeds > 0 and FI.Coins(g.proceeds) or "|cff8b95a3-|r"); setColor(r.cells.proceeds, C.text)
    if g.openUnits > 0 then
      r.cells.held:SetText(("%d · %s"):format(g.openUnits, g.unpriced >= g.openUnits and "?" or FI.Money(g.openValue)))
      setColor(r.cells.held, C.gold)
    else
      r.cells.held:SetText("|cff8b95a3-|r")
    end
    if g.soldCost > 0 or g.proceeds > 0 then
      r.cells.realized:SetText(signed(g.realized))
    else
      r.cells.realized:SetText("|cff8b95a3-|r")
    end
    if g.roi then
      r.cells.roi:SetText(FI.Percent(g.roi)); setColor(r.cells.roi, g.roi >= 0 and C.up or C.down)
    end
  elseif row.kind == "step" then
    local st, a = row.st, ACTIONS[row.st.vendor and "vendor" or row.st.kind]
    r.sDate:SetText(date("%b %d %H:%M", st.e.t))
    r.sAction:SetText(a[1]); setColor(r.sAction, a[2])
    r.sText:SetText(describe(st))
    r.sText:SetPoint("RIGHT", r, "RIGHT", (st.kind == "buy" or st.kind == "sale" or (st.kind == "craft" and st.own > 0)) and -500 or -340, 0)
    -- money lines up under the position's columns
    if st.kind == "buy" then
      r.cells.cost:SetText("-" .. FI.Coins(st.cost)); setColor(r.cells.cost, C.down)
    elseif st.kind == "craft" and st.own > 0 then
      r.cells.cost:SetText("-" .. FI.Coins(st.own)); setColor(r.cells.cost, C.muted)
    elseif st.kind == "use" then
      r.cells.held:SetText(FI.Money(st.cost) .. " used"); setColor(r.cells.held, C.muted)
    elseif st.kind == "sale" then
      r.cells.proceeds:SetText("+" .. FI.Coins(st.net)); setColor(r.cells.proceeds, C.up)
      r.cells.realized:SetText(signed(st.net - st.cost))
      if st.cost > 0 then
        local roi = (st.net - st.cost) / st.cost * 100
        r.cells.roi:SetText(FI.Percent(roi)); setColor(r.cells.roi, roi >= 0 and C.up or C.down)
      end
    end
  else -- what's left
    local held = {}
    for name, n in pairs(g.held or {}) do held[#held + 1] = ("%d %s"):format(n, name) end
    table.sort(held)
    r.sText:SetPoint("RIGHT", r, "RIGHT", -340, 0)
    r.sDate:SetText("now")
    r.sAction:SetText("Holding"); setColor(r.sAction, C.gold)
    r.sText:SetText(table.concat(held, " + ") .. ("  (cost %s)"):format(FI.Money(g.openCost)))
    r.cells.held:SetText(FI.Money(g.openValue)); setColor(r.cells.held, C.gold)
    r.cells.realized:SetText("|cff8b95a3" .. (g.unrealized >= 0 and "+" or "-") .. FI.Money(math.abs(g.unrealized)) .. " open|r")
  end
end

-- ---------------------------------------------------------------------------
function V:Build(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  self.frame = f

  local show = W.Choice(f, { "All", "Open", "Closed" }, "pill", function(v) V.show = v; V:Refresh() end, 26)
  show:SetPoint("TOPLEFT", 200, -14)
  show:Select(self.show)
  local periods = W.Choice(f, { "Today", "7D", "30D", "All" }, "seg", function(v)
    FI.PnLTab.period = v
    if FI.PnLTab.periodChoice then FI.PnLTab.periodChoice:Select(v) end
    V:Refresh()
  end, 26)
  periods:SetPoint("TOPRIGHT", -16, -14)
  self.periodChoice = periods

  -- the numbers a trader looks at first
  self.stats = {}
  local labels = { "REALIZED P&L", "WIN RATE", "RETURN", "OPEN POSITIONS", "BEST POSITION" }
  for i, l in ipairs(labels) do self.stats[i] = stat(f, l) end
  f:SetScript("OnSizeChanged", function(_, w)
    local gap, n = 10, #V.stats
    local wEach = math.floor(((w or 1060) - 32 - gap * (n - 1)) / n)
    for i, st in ipairs(V.stats) do
      st:ClearAllPoints()
      st:SetSize(wEach, 68)
      st:SetPoint("TOPLEFT", 16 + (i - 1) * (wEach + gap), -52)
    end
  end)

  local tbl = W.Box(f, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -132)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)
  local head = W.TableHeader(tbl, 30)
  local cols = { { key = "name", label = "POSITION", x = 32, dir = 1 } }
  for _, c in ipairs(COLS) do cols[#cols + 1] = c end
  self.headers = W.SortHeaders(head, cols, self.sort, function() V:Refresh() end)
  local holder = CreateFrame("Frame", nil, tbl)
  holder:SetPoint("TOPLEFT", 1, -31)
  holder:SetPoint("BOTTOMRIGHT", -1, 30)
  self.list = W.List(holder, 24, ROW_H, makeRow, updateRow)
  self.list:SetAllPoints(holder)
  holder:SetScript("OnSizeChanged", function() V.list:SetCount(#(V.rows or {})) end)

  self.empty = W.Text(tbl, 12, C.soft)
  self.empty:SetPoint("TOPLEFT", 24, -56)
  self.empty:SetPoint("RIGHT", -24, 0)
  self.empty:SetJustifyH("LEFT")
  self.empty:SetWordWrap(true)


  self.footer = W.Text(tbl, 11, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 14, 10)
  self.footer:SetPoint("RIGHT", -14, 0)
  self.footer:SetJustifyH("LEFT")
  self.footer:SetText("Click a position to see each step. Units are matched oldest first; a position closes once nothing is left. Worth = market price minus the 5% AH cut.")
  self.rows = {}
  return f
end

function V:Refresh()
  if not self.frame then return end
  local P = FI.PnLTab
  self.periodChoice:Select(P.period)
  -- (reused until trades, prices or the period change, so expanding and sorting are instant)
  local since = P.since and P.since(P.period) or 0
  local ck = math.floor(since / 60) .. "|" .. tostring(FI.settings and FI.settings.ownMats)
  if not self.cache or self.cache.key ~= ck then
    self.cache = { key = ck, list = (FI.Ledger:Positions(since)) }
  end
  local list = self.cache.list
  -- the numbers up top: closed positions for wins, everything for realized
  local realized, wins, losses, soldCost, closedNet, openN, openCost, openValue, best = 0, 0, 0, 0, 0, 0, 0, 0, nil
  for _, g in ipairs(list) do
    -- only sales in the period count (so this matches the Summary's Flipping number)
    realized = realized + g.realizedIn
    if g.status == "closed" and (g.soldCost > 0 or g.proceeds > 0) then
      if g.realized >= 0 then wins = wins + 1 else losses = losses + 1 end
    end
    if g.status == "closed" then
      soldCost = soldCost + g.soldCost
      closedNet = closedNet + g.realized
    end
    if g.status == "open" then
      openN, openCost, openValue = openN + 1, openCost + g.openCost, openValue + g.openValue
    end
    if g.proceeds > 0 and (not best or g.realized > best.realized) then best = g end
  end
  local s = self.stats
  s[1].value:SetText((realized >= 0 and "+" or "-") .. FI.Coins(math.abs(realized)))
  setColor(s[1].value, realized >= 0 and C.up or C.down)
  local sold = 0
  for _, g in ipairs(list) do sold = sold + g.salesIn end
  s[1].sub:SetText(("%d sale%s in %d position%s"):format(sold, sold == 1 and "" or "s", #list, #list == 1 and "" or "s"))
  local done = wins + losses
  s[2].value:SetText(done > 0 and (FI.Percent(wins / done * 100):gsub("^%+", "")) or "-")
  setColor(s[2].value, done > 0 and (wins >= losses and C.up or C.down) or C.muted)
  s[2].sub:SetText(("%d won · %d lost (closed)"):format(wins, losses))
  if soldCost > 0 then
    local roi = closedNet / soldCost * 100
    s[3].value:SetText(FI.Percent(roi)); setColor(s[3].value, roi >= 0 and C.up or C.down)
  else
    s[3].value:SetText("-"); setColor(s[3].value, C.muted)
  end
  s[3].sub:SetText("on closed positions")
  s[4].value:SetText(openN > 0 and FI.Coins(openValue) or "-"); setColor(s[4].value, openN > 0 and C.gold or C.muted)
  s[4].sub:SetText(openN > 0 and ("%d open · cost %s · %s"):format(openN, FI.Money(openCost), signed(openValue - openCost)) or "nothing held")
  s[5].value:SetText(best and signed(best.realized) or "-")
  if not best then setColor(s[5].value, C.muted) end
  s[5].sub:SetText(best and best.name or "no sales yet")

  -- the table
  local shown = {}
  for _, g in ipairs(list) do
    if self.show == "All" or (self.show == "Open") == (g.status == "open") then
      g.held_ = g.openValue
      shown[#shown + 1] = g
    end
  end
  local st = self.sort
  local get = ({
    held = function(g) return g.openUnits > 0 and g.openValue or false end,
    roi = function(g) return g.roi or false end,
    status = function(g) return g.status end,
  })[st.sort]
  W.SortRows(shown, st.sort, st.dir, get)
  local rows = {}
  for _, g in ipairs(shown) do
    rows[#rows + 1] = { kind = "pos", g = g }
    if self.expanded[key(g)] then
      for _, step in ipairs(g.steps) do rows[#rows + 1] = { kind = "step", st = step, g = g } end
      if g.openUnits > 0 then rows[#rows + 1] = { kind = "hold", g = g } end
    end
  end
  self.rows = rows
  local k = P.period .. "|" .. self.show .. "|" .. st.sort .. st.dir
  if k ~= self.listKey then self.listKey = k; self.list.offset = 0 end
  self.list:SetCount(#rows)
  self.empty:SetShown(#rows == 0)
  self.empty:SetText(#list > 0 and ("No " .. self.show:lower() .. " positions in this period.") or EMPTY)
end

for _, ev in ipairs({ "FI_LEDGER_CHANGED", "FI_SCAN_DONE", "FI_DATA_MERGED" }) do
  FI:On(ev, function()
    V.cache = nil
    if ev == "FI_LEDGER_CHANGED" and V.frame and V.frame:IsVisible() then V:Refresh() end
  end)
end
