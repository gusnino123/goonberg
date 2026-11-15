-- Goonberg Terminal: Loot tab. Dungeon drops you can sell on the AH: where they
-- drop, how often, and what they're worth.
---@type string, GoonbergTerminal
local _, FI = ...
-- dungeon sections start closed: `expanded` holds the ones you've opened
---@class GT.LootTab
local T = { view = "Items", filter = "All", search = "", expanded = {},
  itemSort = { sort = "price", dir = -1 }, dungeonSort = { sort = "level", dir = 1 } }
FI.LootTab = T
local W = FI.Widgets
local C = FI.colors

local ITEM_COLS = {
  { key = "req", label = "Req", r = -322 },
  { key = "chance", label = "Chance", r = -258 },
  { key = "value", label = "AH Value", r = -162 },
  { key = "perKill", label = "Per Kill", r = -72 },
  { key = "kills", label = "Kills", r = -16 },
}
local FROM_LEFT, FROM_RIGHT = -620, -372 -- "drops from" column (offsets from the right)
local LEVEL_AT = -610 -- dungeons view: level range (left-aligned, from the right)
local DUNGEON_COLS = {
  { key = "bosses", label = "Bosses", r = -470 },
  { key = "kills", label = "Runs", r = -400 },
  { key = "items", label = "Items to Sell", r = -300 },
  { key = "perClear", label = "Gold per Clear", r = -16 },
}
-- money columns (each lines its amounts up across the rows)
local MONEY = { value = W.MoneyColumn(), perKill = W.MoneyColumn(), perClear = W.MoneyColumn() }
local TAG = { twink = "|cffffd100Twink %d|r", rare = "|cff66adffRare drop|r" }

local function setColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- A dungeon's drops show once you click its header. While you search, or after
-- picking a dungeon in the Dungeons view, the matching sections open by themselves
-- (otherwise the results would be hidden).
function T:IsOpen(g)
  if self.expanded[g.name] then return true end
  return (self.search or "") ~= "" or self.dungeon ~= nil
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
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
  r.name:SetPoint("RIGHT", r, "RIGHT", FROM_LEFT - 12, 0)
  r.from = W.Text(r, 12, C.soft)
  r.from:SetPoint("LEFT", r, "RIGHT", FROM_LEFT, 0)
  r.from:SetPoint("RIGHT", r, "RIGHT", FROM_RIGHT, 0)
  r.cells = {}
  for _, col in ipairs(ITEM_COLS) do
    if MONEY[col.key] then
      r.cells[col.key] = W.MoneyCell(r, col.r, MONEY[col.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, true)
      fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
      fs:SetJustifyH("RIGHT")
      r.cells[col.key] = fs
    end
  end
  -- the dungeon view reuses the row with its own cells
  r.dcells = {}
  for _, col in ipairs(DUNGEON_COLS) do
    if MONEY[col.key] then
      r.dcells[col.key] = W.MoneyCell(r, col.r, MONEY[col.key])
    else
      local fs = W.Text(r, W.SIZE.cell, C.text, true)
      fs:SetPoint("RIGHT", r, "RIGHT", col.r, 0)
      fs:SetJustifyH("RIGHT")
      r.dcells[col.key] = fs
    end
  end
  r.best = W.Text(r, 12, C.soft)
  r.best:SetPoint("LEFT", r, "RIGHT", -280, 0)
  r.best:SetPoint("RIGHT", r, "RIGHT", -140, 0)
  r.level = W.Text(r, 12, C.soft, true)
  r.level:SetPoint("LEFT", r, "RIGHT", LEVEL_AT, 0)

  -- a dungeon's header row in the Items view
  r.gBg = W.Tex(r, C.raised, 1, "BACKGROUND")
  r.gBg:SetAllPoints()
  if not W.Native() then -- the game's look marks a group with +/- alone
    r.gBar = W.Tex(r, C.gold, 1, "BORDER")
    r.gBar:SetPoint("TOPLEFT"); r.gBar:SetPoint("BOTTOMLEFT"); r.gBar:SetWidth(3)
  end
  r.gArrow = W.Expander(r)
  r.gArrow:SetPoint("LEFT", W.Native() and 10 or 14, 0)
  r.gName = W.Text(r, 13, C.gold)
  r.gName:SetPoint("LEFT", 32, 0)
  r.gLevel = W.Text(r, 12, C.soft)
  r.gLevel:SetPoint("LEFT", r.gName, "RIGHT", 10, 0)
  r.gInfo = W.Text(r, 12, C.soft)
  r.gInfo:SetPoint("RIGHT", r, "RIGHT", -16, 0)
  r.gInfo:SetJustifyH("RIGHT")

  r:SetScript("OnEnter", function(self)
    local row = self.row
    if not row then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    local soft = C.soft
    if row.group then
      GameTooltip:AddLine(row.name)
      if row.minLevel then GameTooltip:AddDoubleLine("Levels", ("%d-%d"):format(row.minLevel, row.maxLevel or row.minLevel), soft[1], soft[2], soft[3], 1, 1, 1) end
      GameTooltip:AddDoubleLine("Drops you can sell", row.count, soft[1], soft[2], soft[3], 1, 1, 1)
      if row.perClear and row.perClear > 0 then GameTooltip:AddDoubleLine("Worth per run (bosses and chests)", FI.Coins(row.perClear), soft[1], soft[2], soft[3], C.up[1], C.up[2], C.up[3]) end
      GameTooltip:AddLine(T:IsOpen(row) and "|cff9e998fClick to hide its drops.|r" or "|cff9e998fClick to show its drops.|r")
      GameTooltip:Show()
      return
    end
    if self.dungeon then
      GameTooltip:AddLine(row.name)
      GameTooltip:AddDoubleLine("Sellable drops worth, per clear", FI.Coins(row.perClear), soft[1], soft[2], soft[3], 1, 1, 1)
      if row.best then GameTooltip:AddDoubleLine("Most valuable drop", row.best.name, soft[1], soft[2], soft[3], 1, 1, 1) end
      GameTooltip:AddLine("|cff9e998fAverage gold from Bind on Equip and unbound boss drops, at AH prices. Click to see them.|r", nil, nil, nil, true)
    else
      GameTooltip:SetItemByID(row.id)
      GameTooltip:AddLine(" ")
      GameTooltip:AddDoubleLine("Drops from", row.trash and ("Trash in " .. row.instance) or (row.boss .. ", " .. row.instance), soft[1], soft[2], soft[3], 1, 1, 1)
      if row.trash and row.listedChance then
        GameTooltip:AddDoubleLine("Drop chance, per trash mob", ("%.2f%%"):format(row.chance * 100), soft[1], soft[2], soft[3], 1, 1, 1)
        if row.drops > 0 then GameTooltip:AddDoubleLine("   Seen by you and your guild", ("%d times"):format(row.drops), soft[1], soft[2], soft[3], 0.82, 0.82, 0.82) end
      elseif row.trash then
        GameTooltip:AddDoubleLine("Seen", ("%d times in %d looted mobs"):format(row.drops, row.kills), soft[1], soft[2], soft[3], 1, 1, 1)
      elseif row.chance then
        GameTooltip:AddDoubleLine("Drop chance", ("%.1f%%"):format(row.chance * 100), soft[1], soft[2], soft[3], 1, 1, 1)
        if row.listedChance then
          GameTooltip:AddDoubleLine("   Listed (WoW Forever loot tables)", ("%.1f%%"):format(row.listedChance * 100), soft[1], soft[2], soft[3], 0.82, 0.82, 0.82)
        end
        if row.kills > 0 then
          GameTooltip:AddDoubleLine("   Your and your guild's kills", ("%d of %d"):format(row.drops, row.kills), soft[1], soft[2], soft[3], 0.82, 0.82, 0.82)
        elseif row.listedChance then
          GameTooltip:AddLine("|cff9e998fYour kills will sharpen this as you play.|r")
        end
      else
        GameTooltip:AddDoubleLine("Drop chance", "not seen drop yet", soft[1], soft[2], soft[3], 0.55, 0.58, 0.64)
      end
      if row.price then
        GameTooltip:AddDoubleLine("AH value", FI.Coins(row.price), soft[1], soft[2], soft[3], 1, 1, 1)
        if row.perKill then
          GameTooltip:AddDoubleLine(row.trash and "Worth per trash mob, on average" or (row.object and "Worth per chest, on average" or "Worth per kill, on average"),
            FI.Coins(row.perKill), soft[1], soft[2], soft[3], C.up[1], C.up[2], C.up[3])
        end
      else
        GameTooltip:AddDoubleLine("AH value", "not seen on the AH", soft[1], soft[2], soft[3], 0.55, 0.58, 0.64)
      end
      if row.twink then GameTooltip:AddLine(("|cffffd100Twink gear:|r one of the priciest items for the %d bracket."):format(row.bracket), 1, 1, 1, true) end
      if row.rare then GameTooltip:AddLine("|cff66adffRare drop|r worth real gold.", 1, 1, 1, true) end
      GameTooltip:AddLine("|cff9e998fClick: find it on the AH. Right-click: chart. Shift-click: link.|r")
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  r:SetScript("OnClick", function(self, button)
    local row = self.row
    if not row then return end
    if row.group then
      T.expanded[row.name] = not T:IsOpen(row) or nil
      T:Refresh()
      return
    end
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

local function showGroup(r, on)
  r.gBg:SetShown(on); r.gArrow:SetShown(on)
  if r.gBar then r.gBar:SetShown(on) end
  r.gName:SetShown(on); r.gLevel:SetShown(on); r.gInfo:SetShown(on)
  r.name:SetShown(not on)
end

local function showItemCells(r, on)
  showGroup(r, false)
  r.icon:SetShown(on)
  r.from:SetShown(on)
  for _, fs in pairs(r.cells) do fs:SetShown(on) end
  for _, fs in pairs(r.dcells) do fs:SetShown(not on) end
  r.best:SetShown(not on)
  r.level:SetShown(not on)
  r.name:ClearAllPoints()
  if on then
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", FROM_LEFT - 12, 0)
  else
    r.name:SetPoint("LEFT", r, "LEFT", 14, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", LEVEL_AT - 12, 0)
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
  local where = row.trash and "Trash (any mob)" or (row.boss .. (row.rareSpawn and " (rare spawn)" or "") .. (row.object and " (chest)" or ""))
  r.from:SetText(T.grouped and where or (where .. "  ·  " .. row.instance))
  local c = r.cells
  c.req:SetText(row.req > 1 and row.req or "-")
  setColor(c.req, C.soft)
  if row.trash and not row.listedChance then
    c.chance:SetText(("seen %dx"):format(row.drops))
    setColor(c.chance, C.soft)
  elseif row.chance and row.drops == 0 and not row.listedChance then
    c.chance:SetText("none yet")
    setColor(c.chance, C.muted)
  elseif row.chance then
    local pct = row.chance * 100
    c.chance:SetText(pct >= 10 and ("%d%%"):format(math.floor(pct + 0.5)) or (pct >= 1 and ("%.1f%%"):format(pct) or ("%.2f%%"):format(pct)))
    setColor(c.chance, C.text)
  else
    c.chance:SetText("not yet")
    setColor(c.chance, C.muted)
  end
  c.value:SetMoney(row.price)
  setColor(c.value, row.price and C.text or C.muted)
  c.perKill:SetMoney(row.perKill)
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
  if dg.perClear > 0 then c.perClear:SetMoney(dg.perClear) else c.perClear:SetText("-") end
  setColor(c.perClear, dg.perClear > 0 and C.up or C.muted)
  r.best:SetText(dg.best and dg.best.name or "")
  if dg.best then r.best:SetTextColor(FI:ItemQualityColor(dg.best.id)) end
  r.level:SetText(dg.minLevel and ("%d-%d"):format(dg.minLevel, dg.maxLevel or dg.minLevel) or "-")
end

local function updateGroupRow(r, g)
  r.dungeon = false
  r.icon:Hide(); r.from:Hide(); r.best:Hide(); r.level:Hide()
  for _, fs in pairs(r.cells) do fs:Hide() end
  for _, fs in pairs(r.dcells) do fs:Hide() end
  showGroup(r, true)
  r.zebra:Hide()
  if T:IsOpen(g) then r.gArrow:SetDown(true) else r.gArrow:SetRight() end
  r.gName:SetText(g.name)
  r.gLevel:SetText(g.minLevel and ("Level %d-%d"):format(g.minLevel, g.maxLevel or g.minLevel) or "")
  local parts = { ("%d item%s"):format(g.count, g.count == 1 and "" or "s") }
  if g.best and g.best.price then parts[#parts + 1] = "best " .. FI.Coins(g.best.price) end
  if g.perClear and g.perClear > 0 then parts[#parts + 1] = "|cff66c761~" .. FI.Coins(g.perClear) .. "|r a run" end
  r.gInfo:SetText(table.concat(parts, "   ·   "))
end

local function updateRow(r, i)
  local row = T.rows[i]
  r.row = row
  if row.group then updateGroupRow(r, row)
  elseif T.view == "Dungeons" then updateDungeonRow(r, row)
  else updateItemRow(r, row) end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
-- what each column sorts by
local ITEM_SORT = {
  from = function(r) return (r.instance or "") .. "/" .. (r.trash and "~" or (r.boss or "")) end,
  value = function(r) return r.price end,
}
local DUNGEON_SORT = {
  best = function(dg) return dg.best and dg.best.price end,
  bosses = function(dg) return dg.bossCount end,
  -- by level; dungeons without one go last, then in list order
  level = function(dg) return dg.minLevel and (dg.minLevel * 1000 + (dg.order or 999)) or nil end,
}

local function header(tbl)
  local head = W.TableHeader(tbl, 30)
  T.itemHead = CreateFrame("Frame", nil, head)
  T.itemHead:SetAllPoints()
  local cols = { { key = "name", label = "Item", x = 14, dir = 1 }, { key = "from", label = "Drops from", at = FROM_LEFT, dir = 1 } }
  for _, col in ipairs(ITEM_COLS) do cols[#cols + 1] = { key = col.key, label = col.label, r = col.r, dir = col.key == "req" and 1 or -1 } end
  T.itemHeaders = W.SortHeaders(T.itemHead, cols, T.itemSort, function() T:Refresh() end)
  T.dungeonHead = CreateFrame("Frame", nil, head)
  T.dungeonHead:SetAllPoints()
  cols = { { key = "name", label = "Dungeon", x = 14, dir = 1 }, { key = "level", label = "Level", at = LEVEL_AT, dir = 1 },
    { key = "best", label = "Most Valuable Drop", at = -280 } }
  for _, col in ipairs(DUNGEON_COLS) do cols[#cols + 1] = { key = col.key, label = col.label, r = col.r } end
  T.dungeonHeaders = W.SortHeaders(T.dungeonHead, cols, T.dungeonSort, function() T:Refresh() end)
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

  local filters = W.Dropdown(tab, { { "All items", "All" }, "Twink gear", "Rare drops", "Recipes & mats" }, function(v) T.filter = v; T:Refresh() end, 140, "Show")
  filters:SetPoint("TOPLEFT", 16, -52)
  filters:Select(self.filter)
  self.filterChoice = filters

  local hint = W.Text(tab, 11, C.muted)
  hint:SetText("Click a column header to sort")
  hint:SetPoint("TOPRIGHT", -18, -59)
  -- fold every dungeon section at once (or open them all again)
  local fold = W.Button(tab, "Collapse all", nil, 24, "pill")
  fold:SetPoint("RIGHT", hint, "LEFT", -12, 0)
  fold:SetScript("OnClick", function()
    local anyOpen = false
    for _, g in ipairs(T.groups or {}) do if T:IsOpen(g) then anyOpen = true end end
    for _, g in ipairs(T.groups or {}) do T.expanded[g.name] = (not anyOpen) or nil end
    T:Refresh()
  end)
  self.collapseAll = fold

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
  self.footer:SetWordWrap(false)
  -- what the counts mean, on hover (the line itself stays short so it fits)
  local why = CreateFrame("Frame", nil, tbl)
  why:SetPoint("BOTTOMLEFT", 1, 1)
  why:SetPoint("BOTTOMRIGHT", -1, 1)
  why:SetHeight(28)
  why:EnableMouse(true)
  why:SetScript("OnEnter", function(f)
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    if T.view == "Dungeons" then
      GameTooltip:AddLine("Gold per clear")
      GameTooltip:AddLine("The average value of a run's sellable boss drops, at AH prices.", 0.82, 0.82, 0.82, true)
    else
      GameTooltip:AddLine("Where the drop chances come from")
      GameTooltip:AddLine("WoW Forever's loot tables, plus boss kills seen by you and guildmates running Goonberg.", 0.82, 0.82, 0.82, true)
      GameTooltip:AddLine("Only Bind on Equip and unbound drops are listed: what you can sell on the AH.", 0.55, 0.58, 0.64, true)
    end
    GameTooltip:Show()
  end)
  why:SetScript("OnLeave", GameTooltip_Hide)

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
    W.SortRows(rows, self.dungeonSort.sort, self.dungeonSort.dir, DUNGEON_SORT[self.dungeonSort.sort])
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
    -- one section per dungeon, lowest level first; the column headers sort the
    -- drops inside each section
    local byDungeon, groups = {}, {}
    for _, r in ipairs(rows) do
      local key = r.instance or "?"
      local g = byDungeon[key]
      if not g then
        local info = L.dungeonInfo[key] or {}
        g = { group = true, name = key, minLevel = info.min, maxLevel = info.max, order = info.order, items = {}, perClear = 0 }
        byDungeon[key] = g
        groups[#groups + 1] = g
      end
      table.insert(g.items, r)
      if r.perKill and not r.trash then g.perClear = g.perClear + r.perKill end
      if r.price and (not g.best or r.price > g.best.price) then g.best = r end
    end
    table.sort(groups, function(a, b)
      local la, lb = a.minLevel or 999, b.minLevel or 999
      if la ~= lb then return la < lb end
      if (a.order or 999) ~= (b.order or 999) then return (a.order or 999) < (b.order or 999) end
      return a.name < b.name
    end)
    rows = {}
    for _, g in ipairs(groups) do
      g.count = #g.items
      rows[#rows + 1] = g
      if self:IsOpen(g) then
        W.SortRows(g.items, self.itemSort.sort, self.itemSort.dir, ITEM_SORT[self.itemSort.sort])
        for _, r in ipairs(g.items) do rows[#rows + 1] = r end
      end
    end
    self.groups = groups
  end
  self.grouped = not dungeons
  self.rows = rows
  MONEY.value:Fit(rows, function(row) return not row.group and row.price end)
  MONEY.perKill:Fit(rows, function(row) return not row.group and row.perKill end)
  MONEY.perClear:Fit(rows, function(row) return not row.group and row.perClear end)
  -- Back to the top only when what's listed changed (view, filter, sort, search,
  -- dungeon). Background refreshes (item info loading, new kills, a scan) keep your
  -- place in the list.
  local st = dungeons and self.dungeonSort or self.itemSort
  local listKey = table.concat({ self.view, self.filter, st.sort, st.dir, q, self.dungeon or "" }, "|")
  if listKey ~= self.listKey then
    self.listKey = listKey
    self.list.offset = 0
  end
  self.list:SetCount(#rows)

  local none = #all == 0
  self.empty:SetShown(#rows == 0)
  if none then
    self.empty:SetText("No dungeon loot recorded yet.\n\nGoonberg learns what drops where by watching boss kills: loot a boss in any dungeon and its drops are counted. Guildmates running Goonberg share their kills too, so drop chances fill in quickly.\n\nOnly items you can sell on the AH are listed: Bind on Equip gear, recipes and materials.")
  else
    self.empty:SetText("Nothing matches these filters.")
  end
  if dungeons then
    self.footer:SetText(("%d dungeon%s  ·  gold per clear: the average value of a run's sellable boss drops"):format(#rows, #rows == 1 and "" or "s"))
  else
    local items = 0
    for _, g in ipairs(self.groups or {}) do items = items + g.count end
    local pending = L.pendingItems or 0
    self.footer:SetText(("%s%d item%s in %d dungeon%s, lowest level first  ·  BoE and unbound drops  ·  %s boss kills counted")
      :format(pending > 0 and ("Loading %d item%s  ·  "):format(pending, pending == 1 and "" or "s") or "",
        items, items == 1 and "" or "s", #(self.groups or {}), #(self.groups or {}) == 1 and "" or "s", FI.Number(kills)))
    local anyOpen = false
    for _, g in ipairs(self.groups or {}) do if self:IsOpen(g) then anyOpen = true end end
    self.collapseAll:SetLabel(anyOpen and "Collapse all" or "Expand all")
  end
  if self.collapseAll then self.collapseAll:SetShown(not dungeons) end
end

FI:On("FI_LOOT_CHANGED", function()
  if T.frame and T.frame:IsVisible() then T:Refresh() end
end)
