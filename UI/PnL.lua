-- Goonberg Terminal: P&L tab with a shareable card (goblin included)
local _, FI = ...
local P = { period = "7D" }
FI.PnLTab = P
local W = FI.Widgets
local C = FI.colors
local DAY = 86400

local PERIODS = {
  ["Today"] = { label = "today" },
  ["7D"] = { span = 7 * DAY, label = "7 days" },
  ["30D"] = { span = 30 * DAY, label = "30 days" },
  ["All"] = { span = nil, label = "all time" },
}

local COINS = { "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Coin_02", "Interface\\Icons\\INV_Misc_Coin_03" }

local function since(period)
  local now = time()
  if period == "Today" then
    local d = date("*t", now)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
  end
  local p = PERIODS[period]
  return p.span and (now - p.span) or 0
end

local function stat(parent, label)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(118, 40)
  f.label = W.Heading(f, label)
  f.label:SetPoint("TOPLEFT")
  f.value = W.Text(f, 15, C.text, true)
  f.value:SetPoint("BOTTOMLEFT")
  return f
end

local function buildGoblin(card)
  local holder = CreateFrame("Frame", nil, card)
  holder:SetPoint("TOPRIGHT", -8, -8)
  holder:SetPoint("BOTTOMRIGHT", -8, 34)
  holder:SetWidth(210)

  -- gold glow behind the goblin
  local glow = holder:CreateTexture(nil, "BACKGROUND")
  glow:SetPoint("BOTTOM", 0, 10)
  glow:SetSize(220, 220)
  glow:SetTexture("Interface\\Cooldown\\star4")
  glow:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.35)
  glow:SetBlendMode("ADD")

  -- coin pile at his feet (also the fallback if no goblin model loads)
  local coins = {}
  local spots = { { -70, 4, 34 }, { -38, 0, 40 }, { -2, 2, 36 }, { 34, 0, 40 }, { 68, 4, 32 }, { -52, 26, 30 }, { 14, 28, 34 }, { 50, 24, 28 } }
  for i, s in ipairs(spots) do
    local t = holder:CreateTexture(nil, "ARTWORK")
    t:SetTexture(COINS[(i % #COINS) + 1])
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t:SetSize(s[3], s[3])
    t:SetPoint("BOTTOM", holder, "BOTTOM", s[1], s[2])
    coins[i] = t
  end

  local m = W.Goblin(holder, false, function()
    -- no model: make the coin pile the picture
    for _, t in ipairs(coins) do t:SetSize(t:GetWidth() * 1.4, t:GetHeight() * 1.4) end
  end)
  m:SetPoint("TOPLEFT", 0, 0)
  m:SetPoint("BOTTOMRIGHT", 0, 22)
  m:SetFrameLevel(holder:GetFrameLevel() + 1)
  holder.model = m
  holder.Load = m.Load
  return holder
end

local function buildCard(tab)
  local card = W.Box(tab, C.side, C.gold)
  card:SetSize(660, 380)
  card:SetPoint("TOPLEFT", 24, -24)
  P.card = card

  local band = W.Tex(card, C.gold, 1, "BORDER")
  band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(4)

  local brand = W.Text(card, 13, C.gold)
  brand:SetText("GOONBERG TERMINAL")
  brand:SetPoint("TOPLEFT", 26, -24)
  card.period = W.Text(card, 13, C.muted)
  card.period:SetPoint("LEFT", brand, "RIGHT", 10, 0)

  card.who = W.Text(card, 15, C.text)
  card.who:SetPoint("TOPLEFT", 26, -52)

  local netLabel = W.Heading(card, "NET PROFIT")
  netLabel:SetPoint("TOPLEFT", 26, -96)
  card.net = W.Text(card, 44, C.up, true)
  card.net:SetPoint("TOPLEFT", 24, -114)

  card.roi = W.Box(card, C.up, C.up)
  card.roi:SetHeight(24)
  card.roi:SetPoint("TOPLEFT", 26, -170)
  card.roi.text = W.Text(card.roi, 13, C.bg, true)
  card.roi.text:SetPoint("CENTER")

  card.sold = stat(card, "SOLD")
  card.sold:SetPoint("TOPLEFT", 26, -214)
  card.bought = stat(card, "BOUGHT")
  card.bought:SetPoint("LEFT", card.sold, "RIGHT", 12, 0)
  card.fees = stat(card, "AH CUT")
  card.fees:SetPoint("LEFT", card.bought, "RIGHT", 12, 0)

  card.best = W.Text(card, 12, C.soft)
  card.best:SetPoint("TOPLEFT", 26, -272)
  card.bags = W.Text(card, 12, C.soft)
  card.bags:SetPoint("TOPLEFT", 26, -294)

  local foot = W.Tex(card, C.border, 1)
  foot:SetPoint("BOTTOMLEFT", 1, 34); foot:SetPoint("BOTTOMRIGHT", -1, 34); foot:SetHeight(1)
  card.stamp = W.Text(card, 11, C.muted)
  card.stamp:SetPoint("BOTTOMLEFT", 26, 12)
  local mark = W.Text(card, 11, C.gold)
  mark:SetText("Goonberg Terminal  ·  /goon")
  mark:SetPoint("BOTTOMRIGHT", -16, 12)
  mark:SetJustifyH("RIGHT")

  card.goblin = buildGoblin(card)
  -- text stops before the goblin, whatever the card's width
  card.best:SetPoint("RIGHT", card.goblin, "LEFT", -10, 0)
  card.bags:SetPoint("RIGHT", card.goblin, "LEFT", -10, 0)
end

local function buildSide(tab)
  local side = W.Box(tab, C.panel, C.border)
  side:SetPoint("TOPLEFT", P.card, "TOPRIGHT", 24, 0)
  side:SetPoint("BOTTOMRIGHT", -24, 24)

  local periods = W.Choice(side, { "Today", "7D", "30D", "All" }, "seg", function(v) P.period = v; P:Refresh() end, 26)
  periods:SetPoint("TOPLEFT", 14, -14)
  periods:Select(P.period)

  -- flips only (bought on the AH, then sold) or every sale and purchase
  local mode = W.Choice(side, { "Flips only", "All sales" }, "seg", function(v)
    FI.settings.pnlMode = (v == "All sales") and "all" or "flips"
    P:Refresh()
  end, 26)
  mode:SetPoint("TOPLEFT", 14, -50)
  mode:Select((FI.settings.pnlMode == "all") and "All sales" or "Flips only")
  for v, b in pairs(mode.buttons) do
    b:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      if v == "Flips only" then
        GameTooltip:AddLine("Flips only")
        GameTooltip:AddLine("Counts only items you bought on the AH and sold again: each sale against what those units cost you. Farmed or crafted items you sell aren't counted.", 0.76, 0.79, 0.83, true)
      else
        GameTooltip:AddLine("All sales")
        GameTooltip:AddLine("Every AH sale and purchase, whatever you sold.", 0.76, 0.79, 0.83, true)
      end
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
  end
  P.modeChoice = mode

  local share = W.Button(side, "Share in chat", nil, 28, "gold")
  share:SetPoint("TOPLEFT", 14, -88)
  share:SetScript("OnClick", function() P:Share() end)
  local shot = W.Button(side, "Screenshot", nil, 28, "pill")
  shot:SetPoint("LEFT", share, "RIGHT", 8, 0)
  shot:SetScript("OnClick", function() if Screenshot then Screenshot() end end)

  local head = W.Heading(side, "RECENT TRADES")
  head:SetPoint("TOPLEFT", 14, -134)

  local holder = CreateFrame("Frame", nil, side)
  holder:SetPoint("TOPLEFT", 0, -152)
  holder:SetPoint("BOTTOMRIGHT", 0, 40)
  P.list = W.List(holder, 30, 28, function(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.when = W.Text(r, 10, C.muted)
    r.when:SetPoint("LEFT", 14, 0)
    r.kind = W.Text(r, 11, C.up)
    r.kind:SetPoint("LEFT", 62, 0)
    r.item = W.Text(r, 11, C.text)
    r.item:SetPoint("LEFT", 110, 0)
    r.item:SetWidth(110)
    r.amt = W.Text(r, 11, C.text, true)
    r.amt:SetPoint("RIGHT", -14, 0)
    r.amt:SetJustifyH("RIGHT")
    return r
  end, function(r, i)
    local e = P.recent[i]
    r.when:SetText(date("%b %d", e.t))
    local sale = e.k == "sale"
    local s = P.summary
    -- in flips mode, a sale with nothing bought before it was farmed: not counted
    local flipped = s and s.flipOf[e]
    local farmed = sale and s and s.mode == "flips" and flipped == 0
    r.kind:SetText(farmed and "Farmed" or (sale and "Sold" or "Bought"))
    local c = farmed and C.muted or (sale and C.up or C.down)
    r.kind:SetTextColor(c[1], c[2], c[3])
    r.item:SetText((e.q and e.q > 1) and (e.i .. " x" .. e.q) or e.i)
    local ic = farmed and C.muted or C.text
    r.item:SetTextColor(ic[1], ic[2], ic[3])
    r.amt:SetText((sale and "+" or "-") .. FI.Coins(sale and (e.g - e.f) or e.g))
    r.amt:SetTextColor(c[1], c[2], c[3])
  end)
  P.list:SetAllPoints(holder)

  P.empty = W.Text(side, 11, C.muted)
  P.empty:SetPoint("TOPLEFT", 14, -158)
  P.empty:SetPoint("RIGHT", -14, 0)
  P.empty:SetWordWrap(true)
  P.empty:SetText("No trades yet. Open your mailbox after selling or buying on the AH: Goonberg Terminal reads the AH invoices there.")

  local note = W.Text(side, 10, C.muted)
  note:SetPoint("BOTTOMLEFT", 14, 14)
  note:SetPoint("RIGHT", -14, 0)
  note:SetWordWrap(true)
  note:SetText("From AH mail invoices, per character. Open the mailbox to update.")
end

function P:Build(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab
  self.recent = {}
  buildCard(tab)
  buildSide(tab)
  -- the card shrinks a little on narrow windows; the trade list takes the rest
  tab:SetScript("OnSizeChanged", function(_, w)
    P.card:SetWidth(math.max(520, math.min(660, w - 48 - 24 - 320)))
  end)
  tab.Refresh = function() P:Refresh() end
  return tab
end

function P:Refresh()
  if not self.frame then return end
  local card = self.card
  card.goblin.Load()
  local from = since(self.period)
  local s = FI.Ledger:Summary(from)
  self.summary = s
  local flips = s.mode == "flips"

  card.period:SetText((flips and "Flips P&L  ·  " or "P&L  ·  ") .. PERIODS[self.period].label)
  card.bought.label:SetText(flips and "COST" or "BOUGHT")
  card.who:SetText(("%s  ·  %s"):format(UnitName("player") or "", GetRealmName() or ""))
  local col = s.net >= 0 and C.up or C.down
  card.net:SetText((s.net >= 0 and "+" or "") .. FI.Money(s.net))
  card.net:SetTextColor(col[1], col[2], col[3])
  if s.roi then
    card.roi:Show()
    card.roi.text:SetText(("%s ROI"):format(FI.Percent(s.roi)))
    card.roi:SetWidth(card.roi.text:GetStringWidth() + 22)
    card.roi:SetBackdropColor(col[1], col[2], col[3], 1)
    card.roi:SetBackdropBorderColor(col[1], col[2], col[3], 1)
  else
    card.roi:Hide()
  end
  card.sold.value:SetText(FI.Coins(s.income))
  card.bought.value:SetText(FI.Coins(s.spent))
  card.fees.value:SetText(FI.Coins(s.fees))
  if s.best and s.best.net > 0 then
    card.best:SetText(("Best flip: |cffe6e9ee%s|r  |cff3fb68b+%s|r"):format(s.best.name, FI.Money(s.best.net)))
  elseif flips then
    card.best:SetText(s.sales > 0 and ("%d flip%s sold"):format(s.sales, s.sales == 1 and "" or "s") or "No flips sold yet: buy on the AH, sell it again.")
  else
    card.best:SetText(("%d sales, %d purchases"):format(s.sales, s.buys))
  end
  if flips then
    local parts = {}
    if s.holdingUnits > 0 then parts[#parts + 1] = ("Holding |cffe8b84a%s|r of flips not sold yet"):format(FI.Money(s.holding)) end
    if s.farmedSales > 0 then parts[#parts + 1] = ("%d farmed sale%s not counted"):format(s.farmedSales, s.farmedSales == 1 and "" or "s") end
    card.bags:SetText(#parts > 0 and table.concat(parts, "  ·  ") or "Only items you bought on the AH and sold again count.")
  else
    card.bags:SetText(("Bags worth |cffe8b84a%s|r at market (not sold yet)"):format(FI.Money(FI.Ledger:BagValue())))
  end
  card.stamp:SetText(date("%B %d, %Y"))

  local recent = {}
  for _, e in ipairs(FI.Ledger:Data().entries) do
    if e.t >= from then recent[#recent + 1] = e end
  end
  table.sort(recent, function(a, b) return a.t > b.t end)
  self.recent = recent
  self.list.offset = 0
  self.list:SetCount(#recent)
  self.empty:SetShown(#recent == 0)
end

function P:Share()
  local s = self.summary or FI.Ledger:Summary(since(self.period))
  local parts = { ("[Goonberg] My AH %s, %s: %s%s"):format(s.mode == "flips" and "flips" or "P&L", PERIODS[self.period].label, s.net >= 0 and "+" or "", FI.Money(s.net)) }
  if s.roi then parts[#parts + 1] = FI.Percent(s.roi) .. " ROI" end
  if s.best and s.best.net > 0 then parts[#parts + 1] = ("best flip %s"):format(s.best.name) end
  SendChatMessage(table.concat(parts, " - "), IsInGuild() and "GUILD" or "SAY")
end

FI:On("FI_LEDGER_CHANGED", function()
  if P.frame and P.frame:IsShown() then P:Refresh() end
end)
