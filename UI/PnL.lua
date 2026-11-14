-- Goonberg Terminal: P&L tab with a shareable card (goblin included)
local _, FI = ...
local P = { period = "7D", show = "All", tradeSort = { sort = "t", dir = -1 } }
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
  glow:SetSize(170, 170) -- stays inside the card
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

-- one half of the card: Flipping or Farming
local function panel(card, title, sub)
  local f = W.Box(card, C.panel, C.border)
  f.title = W.Text(f, 12, C.gold)
  f.title:SetText(title)
  f.title:SetPoint("TOPLEFT", 14, -12)
  f.sub = W.Text(f, 11, C.muted)
  f.sub:SetText(sub)
  f.sub:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
  f.value = W.Text(f, 24, C.up, true)
  f.value:SetPoint("TOPLEFT", 14, -34)
  f.badge = W.Box(f, C.up, C.up)
  f.badge:SetHeight(20)
  f.badge:SetPoint("LEFT", f.value, "RIGHT", 10, 0)
  f.badge.text = W.Text(f.badge, 11, C.bg, true)
  f.badge.text:SetPoint("CENTER")
  f.stats = {}
  for i = 1, 3 do
    local st = CreateFrame("Frame", nil, f)
    st:SetSize(10, 34)
    st.label = W.Heading(st, "")
    st.label:SetPoint("TOPLEFT")
    st.value = W.Text(st, 13, C.text, true)
    st.value:SetPoint("BOTTOMLEFT")
    f.stats[i] = st
  end
  f.stats[1]:SetPoint("TOPLEFT", 14, -72)
  f.line1 = W.Text(f, 11, C.soft)
  f.line1:SetPoint("TOPLEFT", 14, -116)
  f.line1:SetPoint("RIGHT", -12, 0)
  f.line2 = W.Text(f, 11, C.soft)
  f.line2:SetPoint("TOPLEFT", 14, -134)
  f.line2:SetPoint("RIGHT", -12, 0)
  f.line3 = W.Text(f, 11, C.soft)
  f.line3:SetPoint("TOPLEFT", 14, -152)
  f.line3:SetPoint("RIGHT", -12, 0)
  -- the three small numbers share the panel's width
  f:SetScript("OnSizeChanged", function(self, w)
    local each = math.floor(((w or 300) - 28) / 3)
    for i, st in ipairs(self.stats) do
      st:SetWidth(each)
      if i > 1 then st:ClearAllPoints(); st:SetPoint("LEFT", self.stats[i - 1], "RIGHT", 0, 0) end
    end
  end)
  return f
end

local function setBadge(b, text, col)
  if not text then b:Hide(); return end
  b:Show()
  b.text:SetText(text)
  b:SetWidth(b.text:GetStringWidth() + 18)
  b:SetBackdropColor(col[1], col[2], col[3], 1)
  b:SetBackdropBorderColor(col[1], col[2], col[3], 1)
end

local function buildCard(tab)
  local card = W.Box(tab, C.side, C.gold)
  card:SetSize(660, 420)
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
  card.who:SetPoint("TOPLEFT", 26, -50)

  local totalLabel = W.Heading(card, "TOTAL MADE ON THE AH")
  totalLabel:SetPoint("TOPLEFT", 26, -88)
  card.total = W.Text(card, 40, C.up, true)
  card.total:SetPoint("TOPLEFT", 24, -104)
  card.split = W.Text(card, 12, C.soft)
  card.split:SetPoint("TOPLEFT", 26, -156)

  card.goblin = buildGoblin(card)
  card.goblin:ClearAllPoints()
  card.goblin:SetPoint("TOPRIGHT", -8, -8)
  card.goblin:SetSize(220, 186)
  card.split:SetPoint("RIGHT", card.goblin, "LEFT", -10, 0)

  card.flip = panel(card, "FLIPPING", "bought and sold on the AH")
  card.flip:SetPoint("TOPLEFT", 16, -196)
  card.flip:SetPoint("BOTTOMRIGHT", card, "BOTTOM", -6, 46)
  card.farm = panel(card, "FARMING", "found, looted or crafted, then sold")
  card.farm:SetPoint("TOPLEFT", card, "TOP", 6, -196)
  card.farm:SetPoint("BOTTOMRIGHT", -16, 46)

  local foot = W.Tex(card, C.border, 1)
  foot:SetPoint("BOTTOMLEFT", 1, 34); foot:SetPoint("BOTTOMRIGHT", -1, 34); foot:SetHeight(1)
  card.stamp = W.Text(card, 11, C.muted)
  card.stamp:SetPoint("BOTTOMLEFT", 26, 12)
  local mark = W.Text(card, 11, C.gold)
  mark:SetText("Goonberg Terminal  ·  /goon")
  mark:SetPoint("BOTTOMRIGHT", -16, 12)
  mark:SetJustifyH("RIGHT")
end

local function buildSide(tab)
  local side = W.Box(tab, C.panel, C.border)
  side:SetPoint("TOPLEFT", P.card, "TOPRIGHT", 24, 0)
  side:SetPoint("BOTTOMRIGHT", -24, 24)

  local periods = W.Choice(side, { "Today", "7D", "30D", "All" }, "seg", function(v) P.period = v; P:Refresh() end, 26)
  periods:SetPoint("TOPLEFT", 14, -14)
  periods:Select(P.period)

  local share = W.Button(side, "Share in chat", nil, 28, "gold")
  share:SetPoint("TOPLEFT", 14, -52)
  share:SetScript("OnClick", function() P:Share() end)
  local shot = W.Button(side, "Screenshot", nil, 28, "pill")
  shot:SetPoint("LEFT", share, "RIGHT", 8, 0)
  shot:SetScript("OnClick", function() if Screenshot then Screenshot() end end)

  -- materials you gathered yourself, when you craft with them
  local ownLabel = W.Text(side, 11, C.soft)
  ownLabel:SetText("Own mats in crafts")
  ownLabel:SetPoint("TOPLEFT", 14, -98)
  local own = W.Choice(side, { "Market price", "Free" }, "seg", function(v)
    FI.settings.ownMats = (v == "Free") and "free" or "market"
    P:Refresh()
  end, 22)
  own:SetPoint("LEFT", ownLabel, "RIGHT", 8, 0)
  own:Select(FI.settings and FI.settings.ownMats == "free" and "Free" or "Market price")
  for v, b in pairs(own.buttons) do
    b:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(v == "Free" and "Your own materials cost nothing" or "Your own materials at market price")
      GameTooltip:AddLine(v == "Free" and "A crafted item's profit is everything above what you actually spent on materials."
        or "Counts what you'd have got selling your gathered materials instead, so the profit shows whether crafting beat selling the mats.", 0.76, 0.79, 0.83, true)
      GameTooltip:AddLine("Bought materials always count at what you paid; vendor materials at the vendor price.", 0.55, 0.58, 0.64, true)
      GameTooltip:Show()
    end)
    b:HookScript("OnLeave", GameTooltip_Hide)
  end
  P.ownChoice = own

  local head = W.Heading(side, "RECENT TRADES")
  head:SetPoint("TOPLEFT", 14, -132)
  local show = W.Choice(side, { "All", "Flips", "Farmed", "Bought" }, "pill", function(v) P.show = v; P:Refresh() end, 22)
  show:SetPoint("TOPLEFT", 14, -148)
  show:Select(P.show)

  -- click a header to sort the trades
  local hf = CreateFrame("Frame", nil, side)
  hf:SetPoint("TOPLEFT", 0, -178)
  hf:SetPoint("TOPRIGHT", 0, -178)
  hf:SetHeight(22)
  P.tradeHeaders = W.SortHeaders(hf, {
    { key = "t", label = "DATE", x = 14 }, { key = "k", label = "TYPE", x = 62, dir = 1 },
    { key = "i", label = "ITEM", x = 110, dir = 1 }, { key = "amount", label = "AMOUNT", r = -14 },
  }, P.tradeSort, function() P:Refresh() end)

  local holder = CreateFrame("Frame", nil, side)
  holder:SetPoint("TOPLEFT", 0, -202)
  holder:SetPoint("BOTTOMRIGHT", 0, 54)
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
    local kind = P:Kind(e)
    local sale = e.k == "sale"
    local KINDS = {
      flip = { "Flip", C.up }, farmed = { "Farmed", C.soft }, part = { "Flip+", C.up }, crafted = { "Crafted", C.up },
      buy = { "Bought", C.down }, deal = { "Deal", C.gold }, made = { "Made", C.gold },
    }
    local c = KINDS[kind][2]
    r.kind:SetText(KINDS[kind][1])
    r.kind:SetTextColor(c[1], c[2], c[3])
    r.item:SetText((e.q and e.q > 1) and (e.i .. " x" .. e.q) or e.i)
    r.item:SetTextColor(C.text[1], C.text[2], C.text[3])
    if kind == "made" then
      -- a craft moves no gold: show what its materials cost (muted)
      local cost = P.summary and P.summary.craftCostOf[e]
      r.amt:SetText(cost and FI.Coins(cost) or "")
      r.amt:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    else
      r.amt:SetText((sale and "+" or "-") .. FI.Coins(sale and (e.g - e.f) or e.g))
      local ac = sale and C.up or C.down
      r.amt:SetTextColor(ac[1], ac[2], ac[3])
    end
  end)
  P.list:SetAllPoints(holder)

  P.empty = W.Text(side, 11, C.muted)
  P.empty:SetPoint("TOPLEFT", 14, -210)
  P.empty:SetPoint("RIGHT", -14, 0)
  P.empty:SetWordWrap(true)
  P.empty:SetText("No trades yet. Open your mailbox after selling or buying on the AH: Goonberg Terminal reads the AH invoices there.")

  local note = W.Text(side, 10, C.muted)
  note:SetPoint("BOTTOMLEFT", 14, 14)
  note:SetPoint("RIGHT", -14, 0)
  note:SetWordWrap(true)
  note:SetText("Flip: bought on the AH first. Made: a craft (its materials' cost). Crafted: sold after crafting. Deal: from the Deals tab.")
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
    P.card:SetWidth(math.max(600, math.min(700, w - 48 - 24 - 320)))
  end)
  tab.Refresh = function() P:Refresh() end
  return tab
end

-- what a trade was: flip (bought on the AH first), part (partly), crafted (made
-- from your materials), farmed, buy, deal, made (a craft)
function P:Kind(e)
  if e.k == "craft" then return "made" end
  if e.k ~= "sale" then return e.deal and "deal" or "buy" end
  local s = self.summary
  local got = s and s.flipOf[e] or 0
  local q = math.max(1, e.q or 1)
  if got <= 0 then return "farmed" end
  if s and (s.craftOf[e] or 0) >= got and got >= q then return "crafted" end
  return got < q and "part" or "flip"
end

local function signed(v) return (v >= 0 and "+" or "-") .. FI.Coins(math.abs(v)) end
local function colorOf(v) return v >= 0 and C.up or C.down end

function P:Refresh()
  if not self.frame then return end
  local card = self.card
  card.goblin.Load()
  local from = since(self.period)
  local s = FI.Ledger:Summary(from, "flips")
  self.summary = s

  card.period:SetText("P&L  ·  " .. PERIODS[self.period].label)
  card.who:SetText(("%s  ·  %s"):format(UnitName("player") or "", GetRealmName() or ""))
  local col = colorOf(s.total)
  card.total:SetText((s.total >= 0 and "+" or "-") .. FI.Money(math.abs(s.total)))
  card.total:SetTextColor(col[1], col[2], col[3])
  card.split:SetText(("Flipping %s  ·  Farming %s"):format(signed(s.net), signed(s.farmed)))

  -- Flipping
  local f = card.flip
  col = colorOf(s.net)
  f.value:SetText((s.net >= 0 and "+" or "-") .. FI.Coins(math.abs(s.net)))
  f.value:SetTextColor(col[1], col[2], col[3])
  setBadge(f.badge, s.roi and (FI.Percent(s.roi) .. " ROI"), col)
  local labels = { "SOLD FOR", "COST", "AH CUT" }
  local values = { s.income, s.spent, s.fees }
  for i, st in ipairs(f.stats) do st.label:SetText(labels[i]); st.value:SetText(FI.Coins(values[i])) end
  if s.sales > 0 then
    local best = s.best and s.best.net > 0 and ("  ·  best: |cffe6e9ee%s|r |cff3fb68b+%s|r"):format(s.best.name, FI.Money(s.best.net)) or ""
    f.line1:SetText(("%d flip%s sold%s"):format(s.sales, s.sales == 1 and "" or "s", best))
  else
    f.line1:SetText("No flips sold yet: buy low on the AH, sell it again.")
  end
  local lines = {}
  if s.craftSales > 0 then
    lines[#lines + 1] = ("Crafted: %d sale%s |cff%s%s|r%s"):format(s.craftSales, s.craftSales == 1 and "" or "s",
      s.craftNet >= 0 and "3fb68b" or "f0603a", (s.craftNet >= 0 and "+" or "-") .. FI.Money(math.abs(s.craftNet)),
      s.craftRoi and ("  (" .. FI.Percent(s.craftRoi) .. ")") or "")
  end
  local parts = {}
  if s.dealSales > 0 then
    parts[#parts + 1] = ("Deals tab: %d flip%s |cff%s%s|r%s"):format(s.dealSales, s.dealSales == 1 and "" or "s",
      s.dealNet >= 0 and "3fb68b" or "f0603a", (s.dealNet >= 0 and "+" or "-") .. FI.Money(math.abs(s.dealNet)),
      s.dealRoi and ("  (" .. FI.Percent(s.dealRoi) .. ")") or "")
  end
  if s.holdingUnits > 0 then parts[#parts + 1] = ("holding |cffe8b84a%s|r unsold"):format(FI.Money(s.holding)) end
  if #parts > 0 then lines[#lines + 1] = table.concat(parts, "  ·  ") end
  if #lines == 0 then lines[1] = "Profit = what you sold for, minus the AH cut and what those units cost." end
  f.line2:SetText(lines[1])
  f.line3:SetText(lines[2] or "")

  -- Farming
  local m = card.farm
  m.value:SetText("+" .. FI.Coins(s.farmed))
  m.value:SetTextColor(C.up[1], C.up[2], C.up[3])
  setBadge(m.badge, nil)
  labels = { "SOLD FOR", "AH CUT", "SALES" }
  for i, st in ipairs(m.stats) do st.label:SetText(labels[i]) end
  m.stats[1].value:SetText(FI.Coins(s.farmGross))
  m.stats[2].value:SetText(FI.Coins(s.farmFees))
  m.stats[3].value:SetText(FI.Number(s.farmedSales))
  m.line1:SetText(s.farmTop and ("Top seller: |cffe6e9ee%s|r |cff3fb68b+%s|r"):format(s.farmTop.name, FI.Money(s.farmTop.net))
    or "Nothing farmed and sold yet.")
  m.line2:SetText(("Bags worth |cffe8b84a%s|r at market right now"):format(FI.Money(FI.Ledger:BagValue())))
  card.stamp:SetText(date("%B %d, %Y"))

  local recent = {}
  local want = ({ Flips = { flip = true, part = true, crafted = true, made = true }, Farmed = { farmed = true, part = true },
    Bought = { buy = true, deal = true } })[self.show]
  for _, e in ipairs(FI.Ledger:Data().entries) do
    if e.t >= from and (not want or want[self:Kind(e)]) then recent[#recent + 1] = e end
  end
  -- in the order picked by the headers (amount: what it added or cost you)
  local st = self.tradeSort
  local get = ({
    amount = function(e) return e.k == "sale" and (e.g - e.f) or -e.g end,
    k = function(e) return P:Kind(e) end,
  })[st.sort]
  W.SortRows(recent, st.sort, st.dir, get)
  self.recent = recent
  -- back to the top only when what's listed changes, not when new mail arrives
  local key = self.period .. "|" .. self.show .. "|" .. st.sort .. st.dir
  if key ~= self.listKey then self.listKey = key; self.list.offset = 0 end
  self.list:SetCount(#recent)
  self.empty:SetShown(#recent == 0)
  self.empty:SetText(#FI.Ledger:Data().entries == 0
    and "No trades yet. Open your mailbox after selling or buying on the AH: Goonberg Terminal reads the AH invoices there."
    or "No trades of this kind in this period.")
end

function P:Share()
  local s = self.summary or FI.Ledger:Summary(since(self.period), "flips")
  local function m(v) return (v >= 0 and "+" or "-") .. FI.Money(math.abs(v)) end
  local parts = { ("[Goonberg] %s on the AH: %s"):format(PERIODS[self.period].label, m(s.total)) }
  parts[#parts + 1] = ("flipping %s%s"):format(m(s.net), s.roi and (" (" .. FI.Percent(s.roi) .. " ROI)") or "")
  parts[#parts + 1] = ("farming %s"):format(m(s.farmed))
  if s.best and s.best.net > 0 then parts[#parts + 1] = ("best flip %s"):format(s.best.name) end
  SendChatMessage(table.concat(parts, " - "), IsInGuild() and "GUILD" or "SAY")
end

FI:On("FI_LEDGER_CHANGED", function()
  if P.frame and P.frame:IsShown() then P:Refresh() end
end)
