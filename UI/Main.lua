-- Goonberg Terminal: main window (header, tabs, scan button, docking beside the AH)
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.UI
local UI = { tabs = {} }
FI.UI = UI
local W = FI.Widgets
local C = FI.colors

UI.WIDTH, UI.HEIGHT = 1060, 654
UI.MIN_W, UI.MIN_H = 900, 614
UI.TITLE = 22 -- the title bar
UI.TOP = 60   -- title bar and tab row: the body starts below this (where the game's own panels start theirs)

local function savePosition(f)
  if f.docked then return end
  local point, _, relPoint, x, y = f:GetPoint(1)
  FI.db.window = { point = point, relPoint = relPoint, x = x, y = y }
end

local function restorePosition(f)
  f:ClearAllPoints()
  local p = FI.db.window
  if p and p.point then
    f:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
  else
    f:SetPoint("CENTER")
  end
  f.docked = false
end

-- The round portrait: the goblin's face, drawn the way the game draws an NPC's in the
-- quest window. A gold coin shows until then, and stays if the goblin can't be drawn.
local function goblinPortrait(f)
  if f.SetPortraitToAsset then f:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Coin_02") end
  local tex = (f.GetPortrait and f:GetPortrait()) or (f.PortraitContainer and f.PortraitContainer.portrait)
  if not tex or not SetPortraitTextureFromCreatureDisplayID then return end
  -- an invisible model loads the goblin, just to learn which look (display ID) it has
  local m = W.Goblin(f, true, nil, function(model)
    local id = model.GetDisplayInfo and model:GetDisplayInfo()
    if type(id) == "number" and id > 0 then SetPortraitTextureFromCreatureDisplayID(tex, id) end
    model:Hide()
  end)
  m:SetSize(32, 32)
  m:SetPoint("TOPLEFT")
  m:SetAlpha(0)
  m.Load()
end

local function draggable(region, f)
  region:EnableMouse(true)
  region:RegisterForDrag("LeftButton")
  region:SetScript("OnDragStart", function() f.docked = false; f:StartMoving() end)
  region:SetScript("OnDragStop", function() f:StopMovingOrSizing(); savePosition(f) end)
end

-- The window itself: the game's portrait frame (title bar, round portrait, close
-- button), or a flat box with a title on a client without it.
local function window()
  if W.HasTemplate("PortraitFrameTemplate") then
    local f = CreateFrame("Frame", "GoonbergTerminalFrame", UIParent, "PortraitFrameTemplate")
    if f.SetTitle then f:SetTitle("Goonberg Terminal") end
    goblinPortrait(f)
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    f.native = true
    return f
  end
  local f = W.Box(UIParent, { 0.06, 0.06, 0.06 }, C.border, nil, true)
  _G.GoonbergTerminalFrame = f
  W.Shadow(f)
  local title = W.Text(f, 13, C.gold)
  title:SetText("Goonberg Terminal")
  title:SetPoint("TOP", 0, -5)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  close:SetScript("OnClick", function() f:Hide() end)
  return f
end

function UI:Build()
  if self.frame then return self.frame end
  local f = window()
  f.isPanel = true
  self.frame = f
  -- saved size, never bigger than the screen
  local size = FI.db.size or {}
  local maxW, maxH = UIParent:GetWidth() or self.WIDTH, UIParent:GetHeight() or self.HEIGHT
  local w = math.max(self.MIN_W, math.min(size.w or self.WIDTH, maxW - 20))
  local h = math.max(self.MIN_H, math.min(size.h or self.HEIGHT, maxH - 20))
  f:SetSize(w, h)
  f:SetScale(FI.db.scale or 1)
  f:SetResizable(true)
  if f.SetResizeBounds then
    f:SetResizeBounds(self.MIN_W, self.MIN_H, 2400, 1500)
  elseif f.SetMinResize then
    f:SetMinResize(self.MIN_W, self.MIN_H)
  end
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()
  tinsert(UISpecialFrames, "GoonbergTerminalFrame") -- Escape closes it

  -- Drag by the title bar (left of the close button) or any empty part of the tab row
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetPoint("TOPLEFT", f.native and 56 or 0, 0)
  titleBar:SetPoint("TOPRIGHT", -28, 0)
  titleBar:SetHeight(self.TITLE)
  draggable(titleBar, f)

  -- "Update available" in the title bar, left of the close button, when a guildmate
  -- runs a newer Goonberg (Sync.lua); hover for how to update
  local upd = CreateFrame("Frame", nil, f)
  upd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -3)
  upd:SetSize(170, 16)
  upd:SetFrameLevel(titleBar:GetFrameLevel() + 2)
  local updText = W.Text(upd, 11, C.up)
  updText:SetPoint("RIGHT")
  updText:SetJustifyH("RIGHT")
  upd.text = updText
  upd:EnableMouse(true)
  upd:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(self.text:GetText() or "")
    GameTooltip:AddLine(("A guildmate runs a newer Goonberg Terminal (you have %s)."):format(FI.version or "?"), 1, 1, 1, true)
    GameTooltip:AddLine("Update it with your addon manager (WowUp, CurseForge app) or from github.com/gusnino123/goonberg/releases, then /reload.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  upd:SetScript("OnLeave", GameTooltip_Hide)
  upd:Hide()
  self.updateNote = upd

  -- The body: the game's dark inset panel; every screen fills it
  local body
  if f.native and W.HasTemplate("InsetFrameTemplate") then
    body = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    body:SetPoint("TOPLEFT", 4, -self.TOP)
    body:SetPoint("BOTTOMRIGHT", -6, 4)
  else
    body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 1, -self.TOP)
    body:SetPoint("BOTTOMRIGHT", -1, 1)
  end
  body.isPanel = true
  self.body = body

  -- Tab row: tabs on the left, standing on the body; scan status and button on the right
  local head = CreateFrame("Frame", nil, f)
  head:SetPoint("TOPLEFT", f.native and 58 or 8, -self.TITLE)
  head:SetPoint("TOPRIGHT", -8, -self.TITLE)
  head:SetHeight(self.TOP - self.TITLE)
  head:SetFrameLevel(body:GetFrameLevel() + 5) -- the tabs overlap the body's top edge
  draggable(head, f)

  local order = { "Overview", "Deals", "Loot", "Chart", "Crafting", "P&L" }
  local keys = { Overview = "overview", Deals = "deals", Loot = "loot", Chart = "chart", Crafting = "craft", ["P&L"] = "pnl" }
  self.tabLabels = { overview = "Overview", deals = "Deals", loot = "Loot", chart = "Chart", craft = "Crafting", pnl = "P&L" }
  local tabs = W.Choice(head, order, "tab", function(v) UI:Show(keys[v]) end, self.TOP - self.TITLE)
  tabs:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
  if not tabs.native then
    -- flat tabs: a little wider, then re-spaced
    for _, b in pairs(tabs.buttons) do b:SetWidth(b:GetWidth() + 12) end
    local x = 0
    for _, name in ipairs(order) do
      local b = tabs.buttons[name]
      b:ClearAllPoints(); b:SetPoint("LEFT", tabs, "LEFT", x, 0)
      x = x + b:GetWidth()
    end
    tabs:SetWidth(x)
  end
  self.tabBar = tabs

  local scan = W.Button(head, "Scan AH", 104, 30, "gold")
  scan:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 6)
  scan:SetScript("OnClick", function() FI.Scanner:Start(true) end)
  self.scanButton = scan

  local status = W.Text(head, 11, C.muted)
  status:SetPoint("RIGHT", scan, "LEFT", -12, 0)
  status:SetPoint("LEFT", tabs, "RIGHT", 34, 0) -- never runs into the tabs: cut short instead
  status:SetJustifyH("RIGHT")
  status:SetWordWrap(false)
  self.status = status
  local dot = W.Tex(head, C.up)
  dot:SetSize(7, 7)
  dot:SetPoint("RIGHT", status, "LEFT", -6, 0)
  self.statusDot = dot

  self.tabs.overview = FI.OverviewTab:Build(body)
  self.tabs.chart = FI.ChartTab:Build(body)
  self.tabs.deals = FI.DealsTab:Build(body)
  self.tabs.loot = FI.LootTab:Build(body)
  self.tabs.pnl = FI.PnLTab:Build(body)
  self.tabs.craft = FI.CraftTab:Build(body)

  -- The game's open and close sounds. f.quiet skips them when the window opens and
  -- closes along with the Auction House, which plays its own.
  f:HookScript("OnShow", function()
    if not f.quiet then W.Sound("IG_CHARACTER_INFO_OPEN") end
    f.quiet = nil
    UI:UpdateStatus()
  end)
  f:HookScript("OnHide", function()
    if not f.quiet then W.Sound("IG_CHARACTER_INFO_CLOSE") end
    f.quiet = nil
  end)
  -- refresh the status line every few seconds (cooldown countdown)
  f.elapsed = 0
  f:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed > 1 then self.elapsed = 0; UI:UpdateStatus() end
  end)

  -- resize grip, bottom-right corner
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(f:GetFrameLevel() + 20)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    FI.db.size = { w = math.floor(f:GetWidth() + 0.5), h = math.floor(f:GetHeight() + 0.5) }
    savePosition(f)
    UI:Relayout()
  end)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Drag to resize")
    GameTooltip:AddLine("|cff9e998f/goon scale 0.9 makes everything smaller|r", 1, 1, 1)
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", GameTooltip_Hide)
  -- redraw while resizing (charts and columns depend on the size)
  f:SetScript("OnSizeChanged", function() FI:Debounce("relayout", 0.1, function() UI:Relayout() end) end)

  restorePosition(f)
  self:Show("overview", true)
  return f
end

function UI:UpdateStatus()
  if not self.frame then return end
  local S = FI.Scanner
  local realm = FI:Realm()
  local text, color
  if S.state == "waiting" then
    text, color = "Waiting for the Auction House...", C.gold
  elseif S.state == "processing" then
    text, color = ("Scanning %d%%"):format(math.floor((S:Progress() or 0) * 100)), C.gold
  else
    local scans = realm.scans or 0
    local shared = realm.lastShared
    if shared and shared.t == realm.lastScan then
      text = ("Scanned %s by %s"):format(FI.Ago(realm.lastScan), shared.from)
    else
      text = ("Scanned %s  ·  %d scans"):format(FI.Ago(realm.lastScan), scans)
    end
    local q = FI.Sync and FI.Sync:QueueLength() or 0
    if q > 0 then text = text .. "  ·  sharing" end
    color = (realm.lastScan > 0 and time() - realm.lastScan < 3600) and C.up or C.muted
  end
  self.status:SetText(text)
  self.statusDot:SetColorTexture(color[1], color[2], color[3], 1)
  local newer = FI.Sync and FI.Sync:UpdateAvailable()
  if newer then self.updateNote.text:SetText(("Update available: %s"):format(newer)) end
  self.updateNote:SetShown(newer ~= nil)
  -- the dot sits just left of the text, however long it is
  local w = math.min(self.status:GetStringWidth() or 0, self.status:GetWidth() or 0)
  self.statusDot:ClearAllPoints()
  self.statusDot:SetPoint("RIGHT", self.status, "RIGHT", -(w + 6), 0)

  local b = self.scanButton
  if S.state ~= "idle" then
    b:SetLabel("Scanning")
    b:Disable()
  elseif not FI.ahOpen then
    b:SetLabel("Scan AH")
    b:Disable()
  else
    local left = S:CooldownLeft()
    if left > 0 then
      b:SetLabel(("Scan in %d:%02d"):format(math.floor(left / 60), left % 60))
      b:Disable()
    else
      b:SetLabel("Scan AH")
      b:Enable()
    end
  end
end

-- Redraw the current tab at the window's new size
function UI:Relayout()
  if not self.frame or not self.frame:IsShown() then return end
  local t = self.current and self.tabs[self.current]
  if t and t.Refresh then t:Refresh() end
end

function UI:SetScale(scale)
  FI.db.scale = scale
  if self.frame then self.frame:SetScale(scale) end
end

function UI:ResetSize()
  FI.db.size, FI.db.scale, FI.db.window = nil, nil, nil
  if self.frame then
    self.frame:SetScale(1)
    self.frame:SetSize(math.min(self.WIDTH, (UIParent:GetWidth() or self.WIDTH) - 20), math.min(self.HEIGHT, (UIParent:GetHeight() or self.HEIGHT) - 20))
    restorePosition(self.frame)
  end
end

function UI:Show(tab, noOpen)
  self:Build()
  tab = tab or self.current or "overview"
  self.current = tab
  for name, t in pairs(self.tabs) do t:SetShown(name == tab) end
  self.tabBar:Select(self.tabLabels[tab])
  if not noOpen then self.frame:Show() end
  if self.tabs[tab].Refresh then self.tabs[tab]:Refresh() end
end

function UI:Toggle()
  self:Build()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function UI:ShowItem(itemID)
  self:Build()
  if itemID then FI.ChartTab:SetItem(itemID) end
  self:Show("chart")
end

-- Open beside the Auction House when it opens; go back to the saved spot when it closes
local function ahFrame()
  return _G.AuctionHouseFrame or _G.AuctionFrame
end

FI:On("FI_AH_OPEN", function()
  if not FI.settings.dock then return end
  local f = UI:Build()
  local ah = ahFrame()
  if ah and ah:GetRight() then
    local room = (UIParent:GetRight() or 0) - ah:GetRight()
    f:ClearAllPoints()
    if room >= f:GetWidth() * f:GetEffectiveScale() / UIParent:GetEffectiveScale() then
      f:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
    else
      f:SetPoint("TOP", UIParent, "TOP", 0, -60)
    end
    f.docked = true
  end
  if not f:IsShown() then f.quiet = true end -- the AH plays its own sound
  UI:Show()
end)

FI:On("FI_AH_CLOSED", function()
  if UI.frame and UI.frame.docked then
    if UI.frame:IsShown() then UI.frame.quiet = true end
    UI.frame:Hide()
    restorePosition(UI.frame)
  end
  UI:UpdateStatus()
end)

for _, e in ipairs({ "FI_SCAN_STATE", "FI_SCAN_PROGRESS" }) do
  FI:On(e, function() UI:UpdateStatus() end)
end

for _, e in ipairs({ "FI_SCAN_DONE", "FI_DATA_MERGED" }) do
  FI:On(e, function()
    if UI.frame and UI.frame:IsShown() and UI.current and UI.tabs[UI.current].Refresh then
      UI.tabs[UI.current]:Refresh()
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Layout check (/goon layout): opens every tab and view at the smallest window size
-- and lists anything that sticks out of the panel it sits in (a row of buttons that
-- grew too wide, text running off an edge) or lies on top of something else.

-- the game's own parts of the window and inset: not ours to check
local SKIP = { NineSlice = true, PortraitContainer = true, CloseButton = true, TitleContainer = true, Bg = true, TopTileStreaks = true }
local CONTROL = { Button = true, CheckButton = true, EditBox = true, DropdownButton = true }
local TOL = 2 -- pixels of slack before something counts

local function plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("\n", " "))
end

local function textOf(o)
  local t = o.GetText and o:GetText()
  if type(t) == "string" and t:find("%S") then
    t = plain(t)
    return #t > 30 and (t:sub(1, 28) .. "...") or t
  end
end

-- a readable name: its own text, else the first few texts inside it
local function describe(o)
  local t = textOf(o)
  if t then return '"' .. t .. '"' end
  local parts = {}
  local function look(x, depth)
    if #parts >= 3 or not x:IsVisible() then return end
    local xt = x ~= o and textOf(x)
    if xt then parts[#parts + 1] = '"' .. xt .. '"'; return end
    if depth > 3 or not x.GetChildren then return end
    for _, r in ipairs({ x:GetRegions() }) do
      local rt = r:GetObjectType() == "FontString" and textOf(r)
      if rt and #parts < 3 then parts[#parts + 1] = '"' .. rt .. '"' end
    end
    for _, c in ipairs({ x:GetChildren() }) do look(c, depth + 1) end
  end
  look(o, 0)
  if #parts > 0 then return "the group with " .. table.concat(parts, ", ") end
  return "a " .. o:GetObjectType():lower()
end

-- where it draws on screen; for text, just the text itself (not its whole box)
local function rectOf(o)
  local l, b, w, h = o:GetRect()
  if not l or not w or w < 1 or not h or h < 1 then return nil end
  if o:GetObjectType() == "FontString" then
    local sw = math.min(o:GetStringWidth() or w, w)
    local sh = math.min(o:GetStringHeight() or h, h)
    local jh, jv = o:GetJustifyH(), o:GetJustifyV()
    if jh == "RIGHT" then l = l + w - sw elseif jh == "CENTER" then l = l + (w - sw) / 2 end
    if jv == "TOP" then b = b + h - sh elseif jv ~= "BOTTOM" then b = b + (h - sh) / 2 end
    w, h = sw, sh
  end
  return { l = l, r = l + w, b = b, t = b + h }
end

local function isAncestor(a, b)
  local p = b:GetParent()
  while p do
    if p == a then return true end
    p = p:GetParent()
  end
  return false
end

-- everything to check: controls and text (and panels, which must sit in their own panel)
local function collect(o, panel, items)
  if not o:IsVisible() then return end
  if o.GetEffectiveAlpha and o:GetEffectiveAlpha() < 0.05 then return end
  local kind = o:GetObjectType()
  local isText = kind == "FontString"
  if CONTROL[kind] or (isText and textOf(o)) or (o.isPanel and panel) then
    local r = rectOf(o)
    if r then items[#items + 1] = { o = o, r = r, panel = panel, text = isText, box = o.isPanel and not CONTROL[kind] } end
  end
  if isText or not o.GetChildren then return end
  if o.native and not o.isPanel then return end -- the game's widgets look after their own insides
  local inner = (o.isPanel or (o.DoesClipChildren and o:DoesClipChildren())) and o or panel
  for _, r in ipairs({ o:GetRegions() }) do
    if r:GetObjectType() == "FontString" then collect(r, inner, items) end
  end
  for _, c in ipairs({ o:GetChildren() }) do
    local skip = false
    for k in pairs(SKIP) do if o[k] == c then skip = true end end
    if not skip then collect(c, inner, items) end
  end
end

local function overlaps(a, b)
  return math.min(a.r, b.r) - math.max(a.l, b.l) > TOL and math.min(a.t, b.t) - math.max(a.b, b.b) > TOL
end

-- What's wrong in the window as it is now: a list of sentences
function UI:FindLayoutProblems(root)
  root = root or self.frame
  local items, out, seen = {}, {}, {}
  collect(root, nil, items)
  local function add(msg)
    if not seen[msg] then seen[msg] = true; out[#out + 1] = msg end
  end
  for _, it in ipairs(items) do
    local pr = it.panel and rectOf(it.panel)
    if pr then
      local r, sides = it.r, {}
      if r.l < pr.l - TOL then sides[#sides + 1] = ("%dpx on the left"):format(pr.l - r.l) end
      if r.r > pr.r + TOL then sides[#sides + 1] = ("%dpx on the right"):format(r.r - pr.r) end
      if r.t > pr.t + TOL then sides[#sides + 1] = ("%dpx at the top"):format(r.t - pr.t) end
      if r.b < pr.b - TOL then sides[#sides + 1] = ("%dpx at the bottom"):format(pr.b - r.b) end
      if #sides > 0 then add(describe(it.o) .. " sticks out of its panel by " .. table.concat(sides, " and ")) end
    end
  end
  for i = 1, #items do
    local a = items[i]
    for j = i + 1, #items do
      local b = items[j]
      -- text only clashes with text in the same row or group; controls with anything
      if not a.box and not b.box and (not (a.text and b.text) or a.o:GetParent() == b.o:GetParent())
        and overlaps(a.r, b.r) and not isAncestor(a.o, b.o) and not isAncestor(b.o, a.o) then
        add(describe(a.o) .. " overlaps " .. describe(b.o))
      end
    end
  end
  return out
end

local CHECKS = {
  { "overview" }, { "deals" },
  { "loot", "Items", function(v) FI.LootTab.view = v end }, { "loot", "Dungeons", function(v) FI.LootTab.view = v end },
  { "chart" },
  { "craft", "Overview", function(v) FI.CraftTab.view = v end }, { "craft", "Recipes", function(v) FI.CraftTab.view = v end },
  { "pnl", "Summary", function(v) FI.PnLTab.view = v end }, { "pnl", "Positions", function(v) FI.PnLTab.view = v end },
}

function UI:CheckLayout()
  if self.checking then return end
  self.checking = true
  self:Build()
  local f = self.frame
  local w, h, tab = f:GetWidth(), f:GetHeight(), self.current
  local views = { loot = FI.LootTab.view, craft = FI.CraftTab.view, pnl = FI.PnLTab.view }
  FI:Print("Checking the layout of every tab at the smallest window size...")
  self:Show(tab)
  f:SetSize(self.MIN_W, self.MIN_H)
  local found, n, i = {}, 0, 0
  local function finish()
    FI.LootTab.view, FI.CraftTab.view, FI.PnLTab.view = views.loot, views.craft, views.pnl
    f:SetSize(w, h)
    self:Show(tab)
    self.checking = nil
    if n == 0 then
      FI:Print("Layout check: everything fits on all %d views.", #CHECKS)
      return
    end
    FI:Print("Layout check: %d problem%s.", n, n == 1 and "" or "s")
    for _, line in ipairs(found) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
  end
  local function step()
    i = i + 1
    local c = CHECKS[i]
    if not c then return finish() end
    if c[3] then c[3](c[2]) end
    self:Show(c[1])
    -- give resizes and redraws a moment to settle before measuring
    C_Timer.After(0.3, function()
      local where = self.tabLabels[c[1]] .. (c[2] and (" (" .. c[2] .. ")") or "")
      local problems = self:FindLayoutProblems()
      for k, p in ipairs(problems) do
        n = n + 1
        if k <= 8 then found[#found + 1] = "|cffffd100" .. where .. ":|r " .. p end
      end
      if #problems > 8 then found[#found + 1] = ("|cffffd100%s:|r and %d more"):format(where, #problems - 8) end
      step()
    end)
  end
  C_Timer.After(0.3, step)
end
