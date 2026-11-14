-- Goonberg Terminal: Loot tab. Dungeon drops you can sell on the AH: where they
-- drop, how often, and what they're worth.
local _, FI = ...
local T = { view = "Items", filter = "All", sort = "Value", search = "" }
FI.LootTab = T
local W = FI.Widgets
local C = FI.colors

local ITEM_COLS = {
  { key = "req", label = "REQ", r = -322 },
  { key = "chance", label = "CHANCE", r = -258 },
  { key = "value", label = "AH VALUE", r = -162 },
  { key = "perKill", label = "PER KILL", r = -72 },
  { key = "kills", label = "KILLS", r = -16 },
}
local FROM_LEFT, FROM_RIGHT = -620, -372 -- "drops from" column (offsets from the right)
local DUNGEON_COLS = {
  { key = "bosses", label = "BOSSES", r = -470 },
  { key = "kills", label = "RUNS", r = -400 },
  { key = "items", label = "ITEMS TO SELL", r = -300 },
  { key = "perClear", label = "GOLD PER CLEAR", r = -16 },
}
local TAG = { twink = "|cffe8b84aTwink %d|r", rare = "|cff66adffRare drop|r" }

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
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
  r.name:SetPoint("RIGHT", r, "RIGHT", FROM_LEFT - 12, 0)
  r.from = W.Text(r, 12, C.soft)
  r.from:SetPoint("LEFT", r, "RIGHT", FROM_LEFT, 0)
  r.from:SetPoint("RIGHT", r, "RIGHT", FROM_RIGHT, 0)
  r.cells = {}
  for _, col in ipairs(ITEM_COLS) do
    local fs = W.Text(r, 12, C.text, true)
    fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
    fs:SetJustifyH("RIGHT")
    r.cells[col.key] = fs
  end
  -- the dungeon view reuses the row with its own cells
  r.dcells = {}
  for _, col in ipairs(DUNGEON_COLS) do
    local fs = W.Text(r, 12, C.text, true)
    fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
    fs:SetJustifyH("RIGHT")
    r.dcells[col.key] = fs
  end
  r.best = W.Text(r, 12, C.soft)
  r.best:SetPoint("LEFT", r, "RIGHT", -280, 0)
  r.best:SetPoint("RIGHT", r, "RIGHT", -140, 0)

  r:SetScript("OnEnter", function(self)
    self.bg:SetAlpha(0.5)
    local row = self.row
    if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    local soft = C.soft
    if self.dungeon then
      GameTooltip:AddLine(row.name)
      GameTooltip:AddDoubleLine("Sellable drops worth, per clear", FI.Money(row.perClear), soft[1], soft[2], soft[3], 1, 1, 1)
      if row.best then GameTooltip:AddDoubleLine("Most valuable drop", row.best.name, soft[1], soft[2], soft[3], 1, 1, 1) end
      GameTooltip:AddLine("|cff8b95a3Average gold from Bind on Equip and unbound boss drops, at AH prices. Click to see them.|r", nil, nil, nil, true)
    else
      GameTooltip:SetItemByID(row.id)
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Drops from", row.trash and ("Trash in " .. row.instance) or (row.boss .. ", " .. row.instance), soft[1], soft[2], soft[3], 1, 1, 1)
      if row.trash then
        GameTooltip:AddDoubleLine("Seen", ("%d times in %d looted mobs"):format(row.drops, row.kills), soft[1], soft[2], soft[3], 1, 1, 1)
      elseif row.chance and row.drops == 0 then
        GameTooltip:AddDoubleLine("Drop chance", ("not seen in %d kills"):format(row.kills), soft[1], soft[2], soft[3], 0.55, 0.58, 0.64)
      elseif row.chance then
        GameTooltip:AddDoubleLine("Drop chance", ("%.1f%%  (%d of %d kills)"):format(row.chance * 100, row.drops, row.kills), soft[1], soft[2], soft[3], 1, 1, 1)
      else
        GameTooltip:AddDoubleLine("Drop chance", "not seen drop yet", soft[1], soft[2], soft[3], 0.55, 0.58, 0.64)
      end
      if row.price then
        GameTooltip:AddDoubleLine("AH value", FI.Money(row.price), soft[1], soft[2], soft[3], 1, 1, 1)
        if row.perKill then GameTooltip:AddDoubleLine("Worth per kill, on average", FI.Money(row.perKill), soft[1], soft[2], soft[3], 0.25, 0.71, 0.55) end
      else
        GameTooltip:AddDoubleLine("AH value", "not seen on the AH", soft[1], soft[2], soft[3], 0.55, 0.58, 0.64)
      end
      if row.twink then GameTooltip:AddLine(("|cffe8b84aTwink gear:|r one of the priciest items for the %d bracket."):format(row.bracket), 1, 1, 1, true) end
      if row.rare then GameTooltip:AddLine("|cff66adffRare drop|r worth real gold.", 1, 1, 1, true) end
      GameTooltip:AddLine("|cff8b95a3Click: find it on the AH. Right-click: chart. Shift-click: link.|r")
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function(self) self.bg:SetAlpha(0); GameTooltip_Hide() end)
  r:SetScript("OnClick", function(self, button)
    local row = self.row
    if not row then return end
    if self.dungeon then
      T.dungeon = row.name
      T.view = "Items"
      T.viewChoice:Select("Items")
      T:Refresh()
      return
    end
    if IsModifiedClick("CHATLINK") then
      local link = FI:ItemLink(row.id)
      if link then ChatEdit_InsertLink(link) end
    elseif button == "RightButton" then
      FI.UI:ShowItem(row.id)
    else
      FI.DealsTab:FindOnAH(row.id)
    end
  end)
  return r
end

local function showItemCells(r, on)
  r.icon:SetShown(on)
  r.from:SetShown(on)
  for _, fs in pairs(r.cells) do fs:SetShown(on) end
  for _, fs in pairs(r.dcells) do fs:SetShown(not on) end
  r.best:SetShown(not on)
  r.name:ClearAllPoints()
  if on then
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", FROM_LEFT - 12, 0)
  else
    r.name:SetPoint("LEFT", r, "LEFT", 14, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", -500, 0)
  end
end

local function updateItemRow(r, row)
  r.dungeon = false
  showItemCells(r, true)
  r.icon:SetTexture(FI:ItemIcon(row.id))
  local tags = {}
  if row.twink then tags[#tags + 1] = TAG.twink:format(row.bracket) end
  if row.rare then tags[#tags + 1] = TAG.rare end
  r.name:SetText(row.name .. (#tags > 0 and ("   " .. table.concat(tags, "  ")) or ""))
  r.name:SetTextColor(FI:ItemQualityColor(row.id))
  r.from:SetText(row.trash and ("Trash  ·  " .. row.instance) or (row.boss .. "  ·  " .. row.instance))
  local c = r.cells
  c.req:SetText(row.req > 1 and row.req or "-")
  setColor(c.req, C.soft)
  if row.trash then
    c.chance:SetText(("seen %dx"):format(row.drops))
    setColor(c.chance, C.soft)
  elseif row.chance and row.drops == 0 then
    c.chance:SetText("none yet")
    setColor(c.chance, C.muted)
  elseif row.chance then
    c.chance:SetText(row.chance >= 0.1 and ("%d%%"):format(math.floor(row.chance * 100 + 0.5)) or ("%.1f%%"):format(row.chance * 100))
    setColor(c.chance, C.text)
  else
    c.chance:SetText("not yet")
    setColor(c.chance, C.muted)
  end
  c.value:SetText(row.price and FI.Coins(row.price) or "-")
  setColor(c.value, row.price and C.text or C.muted)
  c.perKill:SetText(row.perKill and FI.Coins(row.perKill) or "-")
  setColor(c.perKill, row.perKill and C.up or C.muted)
  c.kills:SetText(row.kills > 0 and FI.Number(row.kills) or "-")
  setColor(c.kills, C.soft)
end

local function updateDungeonRow(r, dg)
  r.dungeon = true
  showItemCells(r, false)
  r.name:SetText(dg.name)
  setColor(r.name, C.text)
  local c = r.dcells
  c.bosses:SetText(dg.bossCount)
  c.kills:SetText(FI.Number(dg.kills))
  setColor(c.kills, C.soft)
  c.items:SetText(dg.items)
  c.perClear:SetText(dg.perClear > 0 and FI.Coins(dg.perClear) or "-")
  setColor(c.perClear, dg.perClear > 0 and C.up or C.muted)
  r.best:SetText(dg.best and dg.best.name or "")
  if dg.best then r.best:SetTextColor(FI:ItemQualityColor(dg.best.id)) end
end

local function updateRow(r, i)
  local row = T.rows[i]
  r.row = row
  if T.view == "Dungeons" then updateDungeonRow(r, row) else updateItemRow(r, row) end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function header(tbl)
  local head = W.TableHeader(tbl, 30)
  T.itemHead = CreateFrame("Frame", nil, head)
  T.itemHead:SetAllPoints()
  local h = W.Heading(T.itemHead, "ITEM")
  h:SetPoint("LEFT", 14, 0)
  h = W.Heading(T.itemHead, "DROPS FROM")
  h:SetPoint("LEFT", T.itemHead, "RIGHT", FROM_LEFT, 0)
  for _, col in ipairs(ITEM_COLS) do
    h = W.Heading(T.itemHead, col.label)
    h:SetPoint("RIGHT", T.itemHead, "RIGHT", col.r, 0)
  end
  T.dungeonHead = CreateFrame("Frame", nil, head)
  T.dungeonHead:SetAllPoints()
  h = W.Heading(T.dungeonHead, "DUNGEON")
  h:SetPoint("LEFT", 14, 0)
  h = W.Heading(T.dungeonHead, "MOST VALUABLE DROP")
  h:SetPoint("LEFT", T.dungeonHead, "RIGHT", -280, 0)
  for _, col in ipairs(DUNGEON_COLS) do
    h = W.Heading(T.dungeonHead, col.label)
    h:SetPoint("RIGHT", T.dungeonHead, "RIGHT", col.r, 0)
  end
end

function T:Build(parent)
  local tab = CreateFrame("Frame", nil, parent)
  tab:SetAllPoints()
  self.frame = tab

  local view = W.Choice(tab, { "Items", "Dungeons" }, "seg", function(v) T.view = v; T:Refresh() end, 26)
  view:SetPoint("TOPLEFT", 16, -16)
  view:Select(self.view)
  self.viewChoice = view

  local search = W.EditBox(tab, 220, "Search items, bosses, dungeons")
  search:SetPoint("TOPRIGHT", -16, -16)
  search:HookScript("OnTextChanged", function(self)
    T.search = (self:GetText() or ""):lower()
    T:Refresh()
  end)

  -- the dungeon picked in the Dungeons view, shown as a removable chip
  local chip = W.Button(tab, "", nil, 26, "pill")
  chip:SetPoint("LEFT", view, "RIGHT", 12, 0)
  chip:SetScript("OnClick", function() T.dungeon = nil; T:Refresh() end)
  chip:Hide()
  self.dungeonChip = chip

  local filters = W.Choice(tab, { "All", "Twink gear", "Rare drops", "Recipes & mats" }, "pill", function(v) T.filter = v; T:Refresh() end, 26)
  filters:SetPoint("TOPLEFT", 16, -52)
  filters:Select(self.filter)
  self.filterChoice = filters

  local sortBy = W.Choice(tab, { "Value", "Per kill", "Chance" }, "seg", function(v) T.sort = v; T:Refresh() end, 26)
  sortBy:SetPoint("TOPRIGHT", -16, -52)
  sortBy:Select(self.sort)
  self.sortChoice = sortBy
  local sortLabel = W.Text(tab, 12, C.soft)
  sortLabel:SetText("Sort by")
  sortLabel:SetPoint("RIGHT", sortBy, "LEFT", -10, 0)
  self.sortLabel = sortLabel

  local tbl = W.Box(tab, C.panel, C.border)
  tbl:SetPoint("TOPLEFT", 16, -90)
  tbl:SetPoint("BOTTOMRIGHT", -16, 16)
  header(tbl)
  local holder = CreateFrame("Frame", nil, tbl)
  holder:SetPoint("TOPLEFT", 1, -31)
  holder:SetPoint("BOTTOMRIGHT", -1, 30)
  self.list = W.List(holder, 30, 30, makeRow, updateRow)
  self.list:SetAllPoints(holder)
  holder:SetScript("OnSizeChanged", function() T.list:SetCount(#(T.rows or {})) end)

  self.empty = W.Text(tbl, 12, C.soft)
  self.empty:SetPoint("TOPLEFT", 24, -56)
  self.empty:SetPoint("RIGHT", -24, 0)
  self.empty:SetJustifyH("LEFT")
  self.empty:SetWordWrap(true)

  self.footer = W.Text(tbl, 11, C.muted)
  self.footer:SetPoint("BOTTOMLEFT", 14, 10)
  self.footer:SetPoint("RIGHT", -14, 0)
  self.footer:SetJustifyH("LEFT")

  tab.Refresh = function() T:Refresh() end
  self.rows = {}
  return tab
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
local function matches(text, q)
  return q == "" or (text and text:lower():find(q, 1, true))
end

function T:Refresh()
  if not self.frame then return end
  local L = FI.Loot
  local q = self.search or ""
  local dungeons = self.view == "Dungeons"
  self.itemHead:SetShown(not dungeons)
  self.dungeonHead:SetShown(dungeons)
  self.filterChoice:SetShown(not dungeons)
  self.sortChoice:SetShown(not dungeons)
  self.sortLabel:SetShown(not dungeons)
  self.dungeonChip:SetShown(not dungeons and self.dungeon ~= nil)
  if self.dungeon then
    self.dungeonChip:SetLabel(self.dungeon .. "   x")
    self.dungeonChip:SetWidth(self.dungeonChip.label:GetStringWidth() + 24)
  end

  local all = L:Rows()
  local rows = {}
  local kills, bosses = 0, {}
  for _, r in ipairs(all) do
    if not r.trash and r.boss and r.kills > 0 then
      local key = r.instance .. "/" .. r.boss
      if not bosses[key] then bosses[key] = true; kills = kills + r.kills end
    end
  end

  if dungeons then
    for _, dg in ipairs(L:Dungeons()) do
      if matches(dg.name, q) then rows[#rows + 1] = dg end
    end
    table.sort(rows, function(a, b)
      if a.perClear ~= b.perClear then return a.perClear > b.perClear end
      return a.name < b.name
    end)
  else
    for _, r in ipairs(all) do
      local ok = true
      if self.dungeon and r.instance ~= self.dungeon then ok = false end
      if self.filter == "Twink gear" and not r.twink then ok = false end
      if self.filter == "Rare drops" and not r.rare then ok = false end
      if self.filter == "Recipes & mats" and r.gear then ok = false end
      if ok and q ~= "" and not (matches(r.name, q) or matches(r.boss, q) or matches(r.instance, q)) then ok = false end
      if ok then rows[#rows + 1] = r end
    end
    local key = ({ Value = "price", ["Per kill"] = "perKill", Chance = "chance" })[self.sort]
    table.sort(rows, function(a, b)
      local va, vb = a[key], b[key]
      if va == nil and vb == nil then return a.name < b.name end
      if va == nil then return false end
      if vb == nil then return true end
      if va ~= vb then return va > vb end
      return a.name < b.name
    end)
  end
  self.rows = rows
  self.list.offset = 0
  self.list:SetCount(#rows)

  local none = #all == 0
  self.empty:SetShown(#rows == 0)
  if none then
    self.empty:SetText("No dungeon loot recorded yet.\n\nGoonberg learns what drops where by watching boss kills: loot a boss in any dungeon and its drops are counted. Guildmates running Goonberg share their kills too, so drop chances fill in quickly.\n\nOnly items you can sell on the AH are listed: Bind on Equip gear, recipes and materials.")
  else
    self.empty:SetText("Nothing matches these filters.")
  end
  if dungeons then
    self.footer:SetText(("%d dungeon%s  ·  gold per clear = average value of sellable boss drops at AH prices"):format(#rows, #rows == 1 and "" or "s"))
  else
    self.footer:SetText(("%d item%s  ·  Bind on Equip and unbound drops only  ·  chances from %s boss kills (yours and your guild's)%s")
      :format(#rows, #rows == 1 and "" or "s", FI.Number(kills), (L.pendingItems or 0) > 0 and "  ·  loading item info..." or ""))
  end
end

FI:On("FI_LOOT_CHANGED", function()
  if T.frame and T.frame:IsVisible() then T:Refresh() end
end)
