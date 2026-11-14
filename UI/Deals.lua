-- Goonberg Terminal: deals tab
local _, FI = ...
local D = { kind = "All", discount = "30%", liquid = false, search = "", sort = "Profit" }
FI.DealsTab = D
local W = FI.Widgets
local C = FI.colors

local ROWS, ROW_H = 40, 30
local COLS = {
  { key = "kind", label = "TYPE", r = -600 },
  { key = "price", label = "LOWEST", r = -510 },
  { key = "worth", label = "WORTH", r = -420 },
  { key = "discount", label = "DISCOUNT", r = -340 },
  { key = "units", label = "UNITS", r = -270 },
  { key = "profit", label = "PROFIT", r = -170 },
  { key = "sold", label = "SOLD/DAY", r = -90 },
  { key = "age", label = "SEEN", r = -14 },
}
local NAME_RIGHT = -660
local KIND_COLOR = { Flip = C.gold, Vendor = C.up, Disenchant = { 0.64, 0.53, 0.96 } }
local DISCOUNTS = { ["20%"] = 0.20, ["30%"] = 0.30, ["50%"] = 0.50 }

-- Type the item into the Auction House search, when the AH is open
function D:FindOnAH(itemID)
  local name = FI:ItemName(itemID)
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
  r.bg = W.Tex(r, C.raised, 0, "BACKGROUND")
  r.bg:SetAllPoints()
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
    local fs = W.Text(r, 12, C.text, col.key ~= "kind")
    fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
    fs:SetJustifyH("RIGHT")
    r.cells[col.key] = fs
  end
  r:SetScript("OnEnter", function(self)
    self.bg:SetAlpha(0.5)
    local d = self.deal
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetItemByID(d.id)
    GameTooltip:AddLine(" ")
    local why = d.kind == "Flip" and ("Fair value (7-day median) %s"):format(FI.Money(d.ref))
      or d.kind == "Vendor" and ("Vendors pay %s each"):format(FI.Money(d.ref))
      or ("Disenchants for about %s (estimate)"):format(FI.Money(d.ref))
    GameTooltip:AddLine("|cffe8b84a" .. why .. "|r")
    if not d.qtyKnown then GameTooltip:AddLine("|cff8b95a3From a guild scan: only the lowest price is known.|r") end
    GameTooltip:AddLine("|cff8b95a3Click: find it on the AH. Right-click: chart. Shift-click: link.|r")
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.bg:SetAlpha(0); GameTooltip_Hide() end)
  r:SetScript("OnClick", function(self, button)
    local d = self.deal
    if not d then return end
    if IsModifiedClick("CHATLINK") then
      local link = FI:ItemLink(d.id)
      if link then ChatEdit_InsertLink(link) end
    elseif button == "RightButton" then
      FI.UI:ShowItem(d.id)
    else
      D:FindOnAH(d.id)
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
  r.cells.kind:SetText(d.kind:upper())
  setColor(r.cells.kind, KIND_COLOR[d.kind] or C.soft)
  r.cells.price:SetText(FI.Money(d.price))
  setColor(r.cells.price, C.gold)
  r.cells.worth:SetText(FI.Money(d.ref))
  setColor(r.cells.worth, C.soft)
  r.cells.discount:SetText(("-%d%%"):format(math.floor(d.discount + 0.5)))
  setColor(r.cells.discount, C.up)
  r.cells.units:SetText(d.qtyKnown and FI.Number(d.units) or "1+")
  r.cells.profit:SetText("+" .. FI.Money(d.profit))
  setColor(r.cells.profit, C.up)
  r.cells.sold:SetText(d.soldPerDay and FI.Number(d.soldPerDay) or "-")
  r.cells.age:SetText((FI.Ago(d.seen):gsub(" ago", "")))
  setColor(r.cells.age, C.muted)
end

function D:Build(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab
  self.rows = {}

  local kinds = W.Choice(tab, { "All", "Flip", "Vendor", "Disenchant" }, "pill", function(v) D.kind = v; D:Refresh() end, 26)
  kinds:SetPoint("TOPLEFT", 16, -16)
  kinds:Select(self.kind)

  local sortBy = W.Choice(tab, { "Profit", "Discount", "Sold/day" }, "seg", function(v) D.sort = v; D:Refresh() end, 26)
  sortBy:SetPoint("TOPRIGHT", -16, -16)
  sortBy:Select(self.sort)
  local disc = W.Choice(tab, { "20%", "30%", "50%" }, "seg", function(v) D.discount = v; D:Refresh() end, 26)
  disc:SetPoint("RIGHT", sortBy, "LEFT", -12, 0)
  disc:Select(self.discount)
  local discLabel = W.Text(tab, 11, C.muted)
  discLabel:SetText("at least")
  discLabel:SetPoint("RIGHT", disc, "LEFT", -6, 0)
  local liquid = W.Button(tab, "Sells daily", nil, 26, "pill")
  liquid:SetPoint("RIGHT", discLabel, "LEFT", -12, 0)
  liquid:SetScript("OnClick", function(self) D.liquid = not D.liquid; self:SetSelected(D.liquid); D:Refresh() end)
  local search = W.EditBox(tab, 150, "Search")
  search:SetPoint("RIGHT", liquid, "LEFT", -12, 0)
  search:SetScript("OnTextChanged", function(self)
    if self.ph then self.ph:SetShown(self:GetText() == "") end
    D.search = self:GetText():lower()
    FI:Debounce("dealsearch", 0.2, function() D:Refresh() end)
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -56)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)
  local head = W.TableHeader(tbl, 30)
  local it = W.Heading(head, "ITEM")
  it:SetPoint("LEFT", 12, 0)
  for _, col in ipairs(COLS) do
    local fs = W.Heading(head, col.label)
    fs:SetPoint("RIGHT", head, "RIGHT", col.r, 0)
    fs:SetJustifyH("RIGHT")
  end
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
  local all = FI.Deals:Filter(raw, DISCOUNTS[self.discount] or 0.30)
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
  local key = self.sort
  table.sort(rows, function(a, b)
    if key == "Discount" then return a.discount > b.discount end
    if key == "Sold/day" then return (a.soldPerDay or -1) > (b.soldPerDay or -1) end
    return a.profit > b.profit
  end)
  self.rows = rows
  local fkey = self.kind .. self.discount .. tostring(self.liquid) .. self.search .. self.sort
  if fkey ~= self.lastFilter then self.list.offset = 0; self.lastFilter = fkey end
  self.list:SetCount(#rows)

  local realm = FI:Realm()
  if not realm.lastScan or realm.lastScan == 0 or time() - realm.lastScan > FI.Deals.maxAge then
    self.empty:SetText("Deals come from the latest scan, and listings change fast.\nOpen the Auction House (or wait for a guildmate's scan) to find deals.")
    self.empty:Show()
  elseif #rows == 0 then
    self.empty:SetText(#all == 0 and "No deals in the latest scan. Try a smaller discount, or check back after the next scan." or "No deals match these filters.")
    self.empty:Show()
  else
    self.empty:Hide()
  end
  self.footer:SetText(("%d deal%s worth |cff3fb68b+%s|r if you bought every unit  -  from the scan %s  -  click a deal to find it on the AH")
    :format(#rows, #rows == 1 and "" or "s", FI.Money(total), FI.Ago(realm.lastScan)))
end

FI:On("FI_DEALS_READY", function() if D.frame and D.frame:IsShown() then D:Refresh() end end)
