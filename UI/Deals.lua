-- Goonberg Terminal: deals tab
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.DealsTab
local D = { kind = "All", margin = "5%", liquid = false, search = "", sortState = { sort = "profit", dir = -1 } }
FI.DealsTab = D
local W = FI.Widgets
local C = FI.colors

local ROWS, ROW_H = 40, 30
-- BUY AT: the cheapest listing. SELL FOR: what you get per item (after the AH cut
-- when reselling on the AH). PER ITEM / MARGIN: profit on that cheapest one.
-- UNITS / TOTAL: every unit listed under the deal price, and the profit on all of them.
-- right edges, evenly spaced by each column's width (money columns get the most room)
local COLS = {
  { key = "kind", label = "Type", r = -594 },
  { key = "price", label = "Buy at", r = -498 },
  { key = "worth", label = "Sell for", r = -402 },
  { key = "perItem", label = "Profit Each", r = -310 },
  { key = "margin", label = "Margin", r = -246 },
  { key = "units", label = "Units", r = -186 },
  { key = "profit", label = "Total Profit", r = -86 },
  { key = "sold", label = "Sold/Day", r = -16 },
}
local NAME_RIGHT = -690
-- what each column sorts by (columns not listed sort by the field of the same name)
local SORT_GET = {
  worth = function(d) return d.worth end,
  sold = function(d) return d.soldPerDay end,
  kind = function(d) return d.kind end,
}
-- money columns (each lines its amounts up across the rows)
local MONEY = { price = W.MoneyColumn(), worth = W.MoneyColumn(), perItem = W.MoneyColumn(), profit = W.MoneyColumn() }
local MARGINS = { ["5%"] = 0.05, ["10%"] = 0.10, ["20%"] = 0.20, ["50%"] = 0.50 }

-- Type the item into the Auction House search, when the AH is open
function D:FindOnAH(itemID, fromDeal)
  local name, loading = FI:ItemName(itemID)
  if loading then
    FI:Print("Still loading that item's name. Try again in a moment.")
    return false
  end
  -- buying it next counts as a Deals-tab flip in the P&L
  if fromDeal then FI.Ledger:MarkDeal(name) end
  local ok = false
  local AHF = _G.AuctionHouseFrame
  if AHF and AHF:IsShown() and AHF.SearchBar and AHF.SearchBar.SearchBox then
    ok = pcall(function()
      if AHF.SetDisplayMode and AuctionHouseFrameDisplayMode then AHF:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
      AHF.SearchBar.SearchBox:SetText(name)
      AHF.SearchBar:StartSearch()
    end)
  elseif _G.AuctionFrame and _G.AuctionFrame:IsShown() and _G.BrowseName then
    ok = pcall(function()
      BrowseName:SetText(name)
      AuctionFrameBrowse_Search()
    end)
  end
  if not ok then FI:Print("Open the Auction House to jump to %s.", name) end
  return ok
end

local function makeRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
    if MONEY[col.key] then
      r.cells[col.key] = W.MoneyCell(r, col.r, MONEY[col.key])
    else
      local fs = W.Text(r, col.key == "kind" and 12 or W.SIZE.cell, C.text, col.key ~= "kind")
      fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[col.key] = fs
    end
  end
  r:SetScript("OnEnter", function(self)
    local d = self.deal
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetItemByID(d.id)
    GameTooltip:AddLine(" ")
    local muted = FI.colors.soft
    GameTooltip:AddDoubleLine("Buy at", FI.Coins(d.price), muted[1], muted[2], muted[3], 1, 1, 1)
    if d.kind == "Rare" then
      GameTooltip:AddDoubleLine("Usual price (60-day median)", FI.Coins(d.ref), muted[1], muted[2], muted[3], 1, 1, 1)
      GameTooltip:AddDoubleLine("Cheapest it typically goes for", FI.Coins(d.typicalLow), muted[1], muted[2], muted[3], 1, 1, 1)
      GameTooltip:AddDoubleLine("Under its usual price", ("%d%%"):format(math.floor(d.under)), muted[1], muted[2], muted[3], C.up[1], C.up[2], C.up[3])
      GameTooltip:AddDoubleLine("Seen on", ("%d days (%s)"):format(d.days, d.confidence), muted[1], muted[2], muted[3], 1, 1, 1)
      if d.relist and d.relist < d.ref then
        GameTooltip:AddDoubleLine("Relist at (others list below usual)", FI.Coins(d.relist), muted[1], muted[2], muted[3], 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("After 5% AH cut", FI.Coins(d.worth), muted[1], muted[2], muted[3], 1, 1, 1)
      if d.trendDown then GameTooltip:AddLine("|cffff7366Trending down: its 14-day price is well under its 60-day one.|r") end
    elseif d.kind == "Flip" then
      GameTooltip:AddDoubleLine("Market value (14-day)", FI.Coins(d.ref), muted[1], muted[2], muted[3], 1, 1, 1)
      if d.relist and d.relist < d.ref then
        GameTooltip:AddDoubleLine("Relist at (others list below fair)", FI.Coins(d.relist), muted[1], muted[2], muted[3], 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("After 5% AH cut", FI.Coins(d.worth), muted[1], muted[2], muted[3], 1, 1, 1)
    elseif d.kind == "Vendor" then
      GameTooltip:AddDoubleLine("Vendors pay (no cut)", FI.Coins(d.worth), muted[1], muted[2], muted[3], 1, 1, 1)
    else
      GameTooltip:AddDoubleLine("Disenchants for (estimate)", FI.Coins(d.ref), muted[1], muted[2], muted[3], 1, 1, 1)
      GameTooltip:AddDoubleLine("After 5% AH cut on the mats", FI.Coins(d.worth), muted[1], muted[2], muted[3], 1, 1, 1)
      if d.pace then
        GameTooltip:AddDoubleLine("Mats the AH takes a day", ("%s items' worth"):format(FI.Number(d.pace)), muted[1], muted[2], muted[3], 1, 1, 1)
      else
        GameTooltip:AddLine("|cffff7366How fast the mats sell isn't known yet, so every unit is counted.|r", 1, 1, 1, true)
      end
    end
    GameTooltip:AddDoubleLine("Profit per item", ("+%s (%d%%)"):format(FI.Coins(d.perItem), math.floor(d.margin)), muted[1], muted[2], muted[3], C.up[1], C.up[2], C.up[3])
    local capped = d.qtyKnown and d.listed and d.listed > d.units
    local allLabel = capped and ("Profit on the %d counted"):format(d.units) or ("Profit on all %s"):format(d.qtyKnown and d.units or "1+")
    GameTooltip:AddDoubleLine(allLabel, "+" .. FI.Coins(d.profit), muted[1], muted[2], muted[3], C.up[1], C.up[2], C.up[3])
    if d.kind == "Disenchant" then
      -- disenchanting is luck: the range you'd land in 8 times out of 10
      if d.sdEach and d.qtyKnown and d.units >= 5 then
        local spread = 1.28 * d.sdEach * math.sqrt(d.units)
        local lo, hi = d.profit - spread, d.profit + spread
        local function signed(v) return (v >= 0 and "+" or "") .. FI.Coins(v) end
        local c = lo < 0 and FI.colors.down or FI.colors.up
        GameTooltip:AddDoubleLine("Likely (8 times in 10)", signed(lo) .. " to " .. signed(hi), muted[1], muted[2], muted[3], c[1], c[2], c[3])
      end
      if capped then
        GameTooltip:AddLine(("|cffff7366Only %d of the %d listed are counted: mats from more would take over %d days to sell.|r")
          :format(d.units, d.listed, FI.Deals.DE_SELL_DAYS), 1, 1, 1, true)
      end
      local n = FI.Disenchant:Samples(d.id)
      GameTooltip:AddLine(n > 0 and ("|cff9e998fOdds: the disenchanting table plus %d of your own disenchants of this kind of gear.|r"):format(n)
        or "|cff9e998fOdds: the disenchanting table. Your own disenchants refine them.|r", 1, 1, 1, true)
      GameTooltip:AddLine(("|cff9e998fDisenchant deals need a %d%%+ margin and mats priced in the last day.|r")
        :format(FI.Deals.DE_MIN_MARGIN * 100), 1, 1, 1, true)
    end
    GameTooltip:AddLine(("|cff9e998fSeen %s.|r"):format(FI.Ago(d.seen)))
    if not d.qtyKnown then GameTooltip:AddLine("|cff9e998fFrom a guild scan: only the lowest price is known.|r") end
    GameTooltip:AddLine("|cff9e998fClick: find it on the AH. Right-click: chart. Shift-click: link.|r")
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:SetScript("OnClick", function(self, button)
    local d = self.deal
    if not d then return end
    if IsModifiedClick("CHATLINK") then
      local link = FI:ItemLink(d.id)
      if link then ChatEdit_InsertLink(link) end
    elseif button == "RightButton" then
      FI.UI:ShowItem(d.id)
    else
      D:FindOnAH(d.id, true)
    end
  end)
  return r
end

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function updateRow(r, i)
  local d = D.rows[i]
  r.deal = d
  r.icon:SetTexture(FI:ItemIcon(d.id))
  r.name:SetText(d.name)
  r.name:SetTextColor(FI:ItemQualityColor(d.id))
  -- rare finds: "RARE?" when only a few days back the usual price; orange when the
  -- whole item is trending down (cheap because the market is falling)
  r.cells.kind:SetText(d.kind == "Rare" and ("Rare" .. (d.confidence == "Thin" and "?" or "")) or d.kind)
  -- the type is a plain label; only a rare find on a falling market is flagged
  setColor(r.cells.kind, (d.kind == "Rare" and d.trendDown) and C.down or C.soft)
  r.cells.price:SetMoney(d.price)
  setColor(r.cells.price, C.text)
  r.cells.worth:SetMoney(d.worth)
  setColor(r.cells.worth, C.soft)
  -- one green per row (the total): the eye goes straight to it
  r.cells.perItem:SetMoney(d.perItem, true)
  setColor(r.cells.perItem, C.text)
  r.cells.margin:SetText(("%d%%"):format(math.floor(d.margin + 0.5)))
  setColor(r.cells.margin, C.text)
  -- disenchant deals capped by how fast the mats sell: counted / listed, in orange
  if d.qtyKnown and d.listed and d.listed > d.units then
    r.cells.units:SetText(FI.Number(d.units) .. "/" .. FI.Number(d.listed))
    setColor(r.cells.units, C.down)
  else
    r.cells.units:SetText(d.qtyKnown and FI.Number(d.units) or "1+")
    setColor(r.cells.units, C.text)
  end
  r.cells.profit:SetMoney(d.profit, true)
  setColor(r.cells.profit, C.up)
  r.cells.sold:SetText(d.soldPerDay and FI.Number(d.soldPerDay) or "-")
end

function D:Build(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab
  self.rows = {}

  local kinds = W.Dropdown(tab, { { "All deals", "All" }, "Rare", "Flip", "Vendor", "Disenchant" }, function(v) D.kind = v; D:Refresh() end, 130, "Type")
  self.kindChoice = kinds
  kinds:SetPoint("TOPLEFT", 16, -16)
  kinds:Select(self.kind)

  local search = W.EditBox(tab, 220, "Search deals")
  search:SetPoint("TOPRIGHT", -16, -16)
  local liquid = W.Button(tab, "Sells daily", nil, 26, "pill")
  liquid:SetPoint("RIGHT", search, "LEFT", -10, 0)
  liquid:SetScript("OnClick", function(self) D.liquid = not D.liquid; self:SetSelected(D.liquid); D:Refresh() end)
  liquid:SetScript("OnEnter", function(self)
    self:Refresh()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Sells daily")
    GameTooltip:AddLine("Only items with at least 1 estimated sale a day, so you can sell them again.", 0.82, 0.82, 0.82, true)
    GameTooltip:AddLine("Disenchants: the AH takes the mats from at least 1 item a day.", 0.82, 0.82, 0.82, true)
    GameTooltip:Show()
  end)
  liquid:SetScript("OnLeave", function(self) self:Refresh(); GameTooltip_Hide() end)

  local disc = W.Dropdown(tab, { "5%", "10%", "20%", "50%" }, function(v) D.margin = v; D:Refresh() end, 80, "Minimum margin")
  disc:SetPoint("LEFT", kinds, "RIGHT", 24, 0)
  disc:Select(self.margin)
  search:HookScript("OnTextChanged", function(self)
    D.search = self:GetText():lower()
    FI:Debounce("dealsearch", 0.2, function() D:Refresh() end)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -54)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)
  local head = W.TableHeader(tbl, 30)
  local cols = { { key = "name", label = "Item", x = 12, dir = 1 } }
  for _, col in ipairs(COLS) do
    cols[#cols + 1] = { key = col.key, label = col.label, r = col.r, dir = col.key == "kind" and 1 or -1 }
  end
  self.headers = W.SortHeaders(head, cols, self.sortState, function() D:Refresh() end)
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

  tab.Refresh = function() D:Refresh() end
  return tab
end

function D:Refresh()
  if not self.frame then return end
  if self.kindChoice then self.kindChoice:Select(self.kind) end
  -- Deals are found once per scan (in the background); here we only filter them
  local raw = FI.Deals:Latest()
  if not raw then
    self.rows = {}
    self.list:SetCount(0)
    local realm = FI:Realm()
    if realm.lastScan and realm.lastScan > 0 and time() - realm.lastScan <= FI.Deals.maxAge then
      -- a search is already queued right after each scan; only start one if not
      if not FI.Deals:Running() and not FI:Pending("deals") then FI.Deals:Run() end
      self.empty:SetText("Finding deals in the latest scan...")
    else
      self.empty:SetText("Deals come from the latest scan, and listings change fast.\nOpen the Auction House (or wait for a guildmate's scan) to find deals.")
    end
    self.empty:Show()
    self.footer:SetText("")
    return
  end
  -- names the game hadn't loaded when the deals were found
  for _, d in ipairs(raw) do
    if d.loading then d.name, d.loading = FI:ItemName(d.id) end
  end
  local all = FI.Deals:Filter(raw, MARGINS[self.margin] or 0.05)
  local rows, total = {}, 0
  for _, d in ipairs(all) do
    local ok = self.kind == "All" or d.kind == self.kind
    if ok and self.liquid then ok = d.soldPerDay and d.soldPerDay >= 1 end
    if ok and self.search ~= "" then ok = d.name:lower():find(self.search, 1, true) ~= nil end
    if ok then
      rows[#rows + 1] = d
      total = total + d.profit
    end
  end
  local st = self.sortState
  W.SortRows(rows, st.sort, st.dir, SORT_GET[st.sort])
  self.rows = rows
  for k, col in pairs(MONEY) do col:Fit(rows, k) end
  local fkey = self.kind .. self.margin .. tostring(self.liquid) .. self.search .. st.sort .. st.dir
  if fkey ~= self.lastFilter then self.list.offset = 0; self.lastFilter = fkey end
  self.list:SetCount(#rows)

  local realm = FI:Realm()
  if not realm.lastScan or realm.lastScan == 0 or time() - realm.lastScan > FI.Deals.maxAge then
    self.empty:SetText("Deals come from the latest scan, and listings change fast.\nOpen the Auction House (or wait for a guildmate's scan) to find deals.")
    self.empty:Show()
  elseif #rows == 0 then
    self.empty:SetText(#all == 0 and "No deals in the latest scan. Try a lower margin, or check back after the next scan." or "No deals match these filters.")
    self.empty:Show()
  else
    self.empty:Hide()
  end
  self.footer:SetText(("%d deal%s  ·  |cff66c761+%s|r if you bought every unit  ·  profits are after the 5%% AH cut  ·  scanned %s  ·  click a row to find it on the AH, a header to sort")
    :format(#rows, #rows == 1 and "" or "s", FI.Coins(total), FI.Ago(realm.lastScan)))
end

FI:On("FI_DEALS_READY", function() if D.frame and D.frame:IsShown() then D:Refresh() end end)
FI:On("FI_ITEM_LOADED", function()
  FI:Debounce("dealNames", 0.5, function()
    if D.frame and D.frame:IsShown() then D:Refresh() end
  end)
end)
