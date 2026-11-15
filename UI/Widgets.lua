-- Goonberg Terminal: small UI building blocks. Where the game has its own piece (red
-- buttons, tabs, search boxes) we use it, so the addon looks like part of the game.
-- The flat look is the fallback for a client without those templates.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Widgets
local W = {}
FI.Widgets = W
local C = FI.colors

W.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
W.NUMFONT = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"
W.WHITE = WHITE
local NATIVE_BUTTON = "UIPanelButtonTemplate"
local NATIVE_TAB = "PanelTopTabButtonTemplate"
local NATIVE_DROPDOWN = "WowStyle1DropdownTemplate"

-- Does the client have this Blizzard template? (making a frame from a missing one is an error)
local templates = {}
---@param name string
---@return boolean
function W.HasTemplate(name)
  if templates[name] == nil then
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
      templates[name] = C_XMLUtil.GetTemplateInfo(name) ~= nil
    else
      templates[name] = DoesTemplateExist and DoesTemplateExist(name) and true or false
    end
  end
  return templates[name]
end

-- One of the game's interface sounds, by its SOUNDKIT name (skipped if the client lacks it)
---@param name string
function W.Sound(name)
  local id = SOUNDKIT and SOUNDKIT[name]
  if id then PlaySound(id) end
end

-- Does the client have the game's own UI pieces? (The flat look is for one without.)
function W.Native() return W.HasTemplate(NATIVE_BUTTON) end

-- Panels and cards get the game's tooltip edge (rounded, bevelled); the flat look, and
-- small tags (flat = true), get a 1px line. Colors can carry a 4th value, their alpha
-- (the see-through panel colors do). The plain border color means the tooltip's grey.
local PANEL_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local PANEL_GREY = { 0.62, 0.62, 0.62 }
function W.Box(parent, bg, border, alpha, flat)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  bg = bg or C.panel
  border = border or C.border
  f.isPanel = true -- the layout check (/goon layout) keeps content inside it
  if flat or not W.Native() then
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
    return f
  end
  f:SetBackdrop({ bgFile = WHITE, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or bg[4] or 1)
  -- the edge is its own frame above the panel's content, so a table header or a row
  -- running to the panel's side can't cover it
  local edge = CreateFrame("Frame", nil, f, "BackdropTemplate")
  edge:SetAllPoints()
  edge:SetFrameLevel(f:GetFrameLevel() + 20)
  edge:SetBackdrop({ edgeFile = PANEL_EDGE, edgeSize = 14 })
  local c = border == C.border and PANEL_GREY or border
  edge:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
  f.edge = edge
  function f:SetBackdropBorderColor(r, g, b, a) self.edge:SetBackdropBorderColor(r, g, b, a) end
  return f
end

function W.Tex(parent, color, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(color[1], color[2], color[3], alpha or color[4] or 1)
  return t
end

-- Nothing smaller than 11: below that the game's fonts get hard to read
W.MIN_SIZE = 11
-- The sizes the tabs use, so the same kind of text is the same size everywhere
W.SIZE = {
  cell = 13,    -- numbers and names in a table row
  label = 12,   -- headings, column headers, a dropdown's label
  hint = 11,    -- notes and explanations, in grey
}

-- Named font objects ("GoonbergNum14", "GoonbergText12"...), one per typeface, size and
-- outline. Every piece of text of a kind shares one, with the game's small drop shadow.
local fonts = {}
---@param size number
---@param num boolean?  the number font (Arial Narrow, whose digits all have one width)
---@param flags string?  "OUTLINE" and the like
function W.Font(size, num, flags)
  flags = flags or ""
  local name = ("Goonberg%s%d%s"):format(num and "Num" or "Text", size, (flags:gsub("%W", "")))
  local f = fonts[name]
  if f == nil then
    f = CreateFont and CreateFont(name) or false
    if f then
      f:SetFont(num and W.NUMFONT or W.FONT, size, flags)
      f:SetShadowOffset(1, -1)
      f:SetShadowColor(0, 0, 0, 1)
    end
    fonts[name] = f
  end
  return f or nil
end

function W.Text(parent, size, color, num, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  size = math.max(size or 12, W.MIN_SIZE)
  -- Arial Narrow runs small next to the game font: one point up keeps numbers level with words
  if num then size = size + 1 end
  local font = W.Font(size, num, flags)
  if font then
    fs:SetFontObject(font)
  else
    fs:SetFont(num and W.NUMFONT or W.FONT, size, flags or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
  end
  color = color or C.text
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- The game's red button, a little shorter than asked so it sits centered in the same row.
-- A selected one (in a group of choices) is lit up with white text.
-- Only PreClick and On* scripts the template doesn't use are set here: the template
-- swaps its own textures in OnMouseDown/OnDisable and friends.
local function nativeButton(parent, label, width, height)
  local b = CreateFrame("Button", nil, parent, NATIVE_BUTTON)
  b.native = true
  b:SetHeight(math.max(20, (height or 26) - 4))
  b:SetText(label or "")
  b.label = b:GetFontString() or b.Text
  b:SetWidth(width or math.max(40, b:GetTextWidth() + 24))
  function b:SetSelected(on)
    self.selected = on
    self:Refresh()
  end
  function b:SetLabel(text)
    self:SetText(text)
  end
  function b:Refresh()
    if self.selected then
      self:LockHighlight()
      self:SetNormalFontObject(GameFontHighlight)
    else
      self:UnlockHighlight()
      self:SetNormalFontObject(GameFontNormal)
    end
  end
  b:SetScript("PreClick", function() W.Sound("IG_MAINMENU_OPTION") end)
  return b
end

-- A button. Uses the game's red button when the client has it; otherwise flat, with
-- style: "gold" (filled), "pill" (outlined, gold when selected), "seg" (segment), "ghost"
function W.Button(parent, label, width, height, style)
  if style ~= "tab" and W.HasTemplate(NATIVE_BUTTON) then
    local nb = nativeButton(parent, label, width, height)
    nb.style = style or "ghost"
    return nb
  end
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 80, height or 26)
  b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  b.style = style or "ghost"
  b.label = W.Text(b, (style == "tab") and 13 or 12, C.soft)
  b.label:SetPoint("CENTER")
  if style == "tab" then
    -- header tab: plain text with a gold underline when active
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    b.line:SetPoint("BOTTOMLEFT", 6, 0)
    b.line:SetPoint("BOTTOMRIGHT", -6, 0)
    b.line:SetHeight(2)
  end
  b.label:SetJustifyH("CENTER")
  b.label:SetText(label or "")
  if not width then b:SetWidth(math.max(40, b.label:GetStringWidth() + 22)) end

  function b:SetSelected(on)
    self.selected = on
    self:Refresh()
  end
  function b:SetLabel(text)
    self.label:SetText(text)
  end
  function b:Refresh()
    local s, hover, on = self.style, self:IsMouseOver(), self.selected
    local bg, bd, tx, ba = C.panel, C.border, C.soft, 0 -- luacheck: ignore 311 (fallback if a style misses one)
    if s == "gold" then
      bg, bd, tx, ba = C.gold, C.gold, { 0.08, 0.07, 0.04 }, hover and 0.85 or 1
      if not self:IsEnabled() then bg, bd, tx, ba = C.raised, C.border, C.muted, 1 end
    elseif s == "pill" then
      if on then bg, bd, tx, ba = C.gold, C.gold, { 0.08, 0.07, 0.04 }, 1
      else bg, bd, tx, ba = C.raised, hover and C.muted or C.border, C.soft, hover and 1 or 0 end
    elseif s == "tab" then
      bg, bd, ba = C.side, C.side, 0
      tx = on and C.text or (hover and C.soft or C.muted)
      self.line:SetShown(on)
    elseif s == "seg" then
      bd = on and C.raised or C.panel
      bg, tx, ba = C.raised, on and C.text or C.muted, on and 1 or (hover and 0.5 or 0)
      if not on then bd = C.panel end
    else
      bg, bd, tx, ba = C.raised, hover and C.muted or C.border, hover and C.text or C.soft, hover and 1 or 0
    end
    self:SetBackdropColor(bg[1], bg[2], bg[3], ba)
    self:SetBackdropBorderColor(bd[1], bd[2], bd[3], (s == "seg" or s == "tab") and 0 or 1)
    self.label:SetTextColor(tx[1], tx[2], tx[3])
  end
  b:SetScript("OnEnter", b.Refresh)
  b:SetScript("OnLeave", b.Refresh)
  b:SetScript("OnEnable", b.Refresh)
  b:SetScript("OnDisable", b.Refresh)
  b:Refresh()
  return b
end

-- The game's tabs (the kind that sit on top of a panel), bottoms on the group's bottom
-- edge. Same interface as W.Choice. A selected tab is disabled, so it can't be re-clicked.
local NATIVE_SUBTAB = "TabButtonTemplate"
local function nativeTabs(parent, values, onPick, height, template)
  local g = CreateFrame("Frame", nil, parent)
  g.buttons, g.native = {}, true
  local sub = template == NATIVE_SUBTAB
  local x, prev = 0, nil
  for _, v in ipairs(values) do
    local t = CreateFrame("Button", nil, g, template or NATIVE_TAB)
    t.native = true
    t:SetText(v)
    t:SetScript("OnShow", function(self)
      PanelTemplates_TabResize(self, sub and 10 or 15, nil, sub and 60 or 70)
      if self.selected then PanelTemplates_SelectTab(self) else PanelTemplates_DeselectTab(self) end
    end)
    t:GetScript("OnShow")(t)
    if prev then
      t:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 4, 0)
      x = x + 4
    else
      t:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", 0, 0)
    end
    x = x + t:GetWidth()
    t:SetScript("OnClick", function()
      W.Sound(sub and "IG_MAINMENU_OPTION" or "IG_CHARACTER_INFO_TAB")
      g:Select(v)
      onPick(v)
    end)
    function t:SetSelected(on)
      self.selected = on
      if on then PanelTemplates_SelectTab(self) else PanelTemplates_DeselectTab(self) end
    end
    g.buttons[v] = t
    prev = t
  end
  g:SetSize(math.max(1, x), height or 32)
  function g:Select(value)
    self.value = value
    for v, t in pairs(self.buttons) do t:SetSelected(v == value) end
  end
  return g
end

-- Can the game's small tabs be built and switched here? (tried once: an old client's
-- tab code wants named frames)
local subTabsOK
local function subTabsWork()
  if subTabsOK == nil then
    subTabsOK = W.HasTemplate(NATIVE_SUBTAB) and PanelTemplates_TabResize and PanelTemplates_SelectTab
      and pcall(function()
        local t = CreateFrame("Button", nil, UIParent, NATIVE_SUBTAB)
        t:Hide()
        PanelTemplates_TabResize(t, 10, nil, 60)
        PanelTemplates_SelectTab(t)
        PanelTemplates_DeselectTab(t)
      end) or false
  end
  return subTabsOK
end

-- A group of mutually exclusive buttons. onPick(value)
-- style: "tab" (the window's tabs), "seg" (a view switch: the game's small tabs), or a
-- button style for a row of buttons
function W.Choice(parent, values, style, onPick, height)
  if style == "tab" and W.HasTemplate(NATIVE_TAB) and PanelTemplates_TabResize and PanelTemplates_SelectTab then
    return nativeTabs(parent, values, onPick, height)
  end
  if style == "seg" and subTabsWork() then
    return nativeTabs(parent, values, onPick, height, NATIVE_SUBTAB)
  end
  local native = style ~= "tab" and W.HasTemplate(NATIVE_BUTTON)
  local g = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  g.buttons = {}
  local x = 0
  local inset = (style == "seg" and not native) and 3 or 0
  local gap
  if native then
    gap = (style == "seg") and 2 or 4
  else
    gap = (style == "seg") and 2 or (style == "tab" and 0 or 6)
  end
  if inset > 0 then
    g:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    g:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
    g:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    x = inset
  end
  for _, v in ipairs(values) do
    local b = W.Button(g, v, nil, (height or 26) - inset * 2, style)
    b:SetPoint("LEFT", g, "LEFT", x, 0)
    b:SetScript("OnClick", function() g:Select(v); onPick(v) end)
    x = x + b:GetWidth() + gap
    g.buttons[v] = b
  end
  g:SetSize(math.max(1, x - gap + inset), height or 26)
  function g:Select(value)
    self.value = value
    for v, b in pairs(self.buttons) do b:SetSelected(v == value) end
  end
  return g
end

-- An on/off option: the game's checkbox with its label to the right (click either),
-- or a pill button in the flat look. onToggle(on). t:SetOn(on), t.on
function W.Toggle(parent, label, onToggle)
  if W.Native() and W.HasTemplate("UICheckButtonTemplate") then
    local t = CreateFrame("Frame", nil, parent)
    local cb = CreateFrame("CheckButton", nil, t, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", -2, 0)
    local own = cb.Text or cb.text
    if own then own:SetText("") end
    t.check = cb
    t.label = W.Text(t, W.SIZE.label, C.text)
    t.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    function t:SetLabel(text)
      self.label:SetText(text)
      local w = math.ceil(self.label:GetStringWidth() or 0)
      self:SetSize(22 + 1 + w + 4, 24)
      cb:SetHitRectInsets(0, -(w + 4), 0, 0) -- the label clicks too
    end
    function t:SetOn(on)
      self.on = on and true or false
      cb:SetChecked(self.on)
    end
    cb:SetScript("OnClick", function(self)
      W.Sound(self:GetChecked() and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
      t.on = self:GetChecked() and true or false
      onToggle(t.on)
    end)
    -- tooltips set on the toggle show from the box as well
    cb:SetScript("OnEnter", function() local f = t:GetScript("OnEnter"); if f then f(t) end end)
    cb:SetScript("OnLeave", function() local f = t:GetScript("OnLeave"); if f then f(t) end end)
    t:SetLabel(label)
    return t
  end
  local b = W.Button(parent, label, nil, 24, "pill")
  function b:SetOn(on)
    self.on = on and true or false
    self:SetSelected(self.on)
  end
  b:SetScript("OnClick", function(self) self:SetOn(not self.on); onToggle(self.on) end)
  return b
end

-- A dropdown for picking one of several options (a filter, a time frame). It stays the
-- same width whatever is picked, so a row of them can't run off its panel the way a row
-- of buttons can. The game's own dropdown when the client has it; else a button that
-- opens a list. Same interface as W.Choice: g:Select(value), g.value.
--   entries: strings, or { text, value } when the text shown differs from the value
--   label: optional text to its left, part of the returned frame
--   emptyText: shown when the value isn't one of the entries (a chart zoomed by hand)
function W.Dropdown(parent, entries, onPick, width, label, emptyText)
  local g = CreateFrame("Frame", nil, parent)
  g.isDropdown, g.emptyText = true, emptyText or ""
  local x = 0
  if label then
    g.label = W.Text(g, 12, C.soft)
    g.label:SetText(label)
    g.label:SetPoint("LEFT")
    x = math.ceil(g.label:GetStringWidth() or 0) + 8
  end

  local function find(value)
    for _, e in ipairs(g.entries or {}) do if e.value == value then return e end end
  end
  local function pick(value)
    g.value = value
    if not g.native then g:UpdateText() end -- the game's dropdown updates its own text
    -- while the game's menu is still handling the click, don't rebuild it from inside
    -- onPick (a refresh that calls g:Select)
    g.picking = true
    local ok, err = pcall(onPick, value)
    g.picking = nil
    if not ok then geterrorhandler()(err) end
  end

  local dd
  if W.HasTemplate(NATIVE_DROPDOWN) and MenuUtil and MenuUtil.CreateRadioMenu then
    dd = CreateFrame("DropdownButton", nil, g, NATIVE_DROPDOWN)
    dd.native, g.native = true, true
    if dd.SetDefaultText then dd:SetDefaultText(g.emptyText) end
  else
    dd = W.Button(g, "", width, 26, "pill")
    local arrow = dd:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, -2)
    -- the list of options, opened under the button
    local list = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    list:SetFrameStrata("DIALOG")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    list:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    list:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    list:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    list.rows = {}
    list:Hide()
    g.list = list
    dd:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
    g:SetScript("OnHide", function() list:Hide() end)
  end
  dd:SetWidth(width)
  dd:SetPoint("LEFT", g, "LEFT", x, 0)
  g.button = dd
  g:SetSize(x + width, math.max(26, dd:GetHeight() or 0))

  function g:UpdateText()
    local e = find(self.value)
    if self.native then
      dd:GenerateMenu() -- re-reads which option is picked and shows its text
      if not e and dd.Text and not dd.SetDefaultText then dd.Text:SetText(self.emptyText) end
    else
      dd:SetLabel(e and e.text or self.emptyText)
    end
  end

  function g:SetEntries(list)
    local es = {}
    for i, e in ipairs(list) do
      if type(e) == "table" then es[i] = { text = e[1], value = e[2] } else es[i] = { text = e, value = e } end
    end
    self.entries = es
    if self.native then
      local args = {}
      for i, e in ipairs(es) do args[i] = { e.text, e.value } end
      MenuUtil.CreateRadioMenu(dd, function(v) return v == g.value end, pick, unpack(args))
    else
      local rows = self.list.rows
      for i, e in ipairs(es) do
        local r = rows[i] or W.Button(self.list, "", width - 4, 22, "ghost")
        rows[i] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 22)
        r:SetLabel(e.text)
        r:SetScript("OnClick", function() self.list:Hide(); pick(e.value) end)
        r:Show()
      end
      for i = #es + 1, #rows do rows[i]:Hide() end
      self.list:SetSize(width, #es * 22 + 4)
    end
    self:UpdateText()
  end

  function g:Select(value)
    self.value = value
    if not (self.picking and self.native) then self:UpdateText() end
  end

  -- a tooltip on the dropdown: fn(tooltip) adds the lines
  function g:SetTooltip(fn)
    dd:HookScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      fn(GameTooltip)
      GameTooltip:Show()
    end)
    dd:HookScript("OnLeave", GameTooltip_Hide)
  end

  g:SetEntries(entries)
  return g
end

-- A text field: the game's search box (magnifier, clear button, grey hint), or with
-- plain = true its plain input box. Hook OnTextChanged, don't set it: the search box
-- needs its own handler to hide the hint and show the clear button.
function W.EditBox(parent, width, placeholder, plain)
  local template = plain and "InputBoxTemplate" or "SearchBoxTemplate"
  if W.HasTemplate(template) then
    local e = CreateFrame("EditBox", nil, parent, template)
    e:SetSize(width, 26) -- the template's art is 20 high, centered in the row
    e:SetAutoFocus(false)
    e.native = true
    if e.Instructions then
      e.Instructions:SetText(placeholder or "")
    elseif placeholder then
      e.ph = W.Text(e, 12, C.muted)
      e.ph:SetPoint("LEFT", 2, 0)
      e.ph:SetText(placeholder)
      e:HookScript("OnTextChanged", function(self) self.ph:SetShown(self:GetText() == "") end)
    end
    return e
  end
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(width, 26)
  e:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  e:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
  e:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
  e:SetFont(W.FONT, 12, "")
  e:SetTextColor(C.text[1], C.text[2], C.text[3])
  e:SetTextInsets(8, 8, 0, 0)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1) end)
  e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) end)
  if placeholder then
    e.ph = W.Text(e, 12, C.muted)
    e.ph:SetPoint("LEFT", 8, 0)
    e.ph:SetText(placeholder)
    e:HookScript("OnTextChanged", function(self) self.ph:SetShown(self:GetText() == "") end)
  end
  return e
end

-- A heading, in the game's gold (Title Case, like the game's own column headers)
function W.Heading(parent, text)
  local fs = W.Text(parent, W.SIZE.label, C.gold)
  fs:SetText(text)
  return fs
end

-- A straight line using the Line API when present (sparklines), else nothing
function W.Line(parent, color, thickness)
  if not parent.CreateLine then return nil end
  local l = parent:CreateLine(nil, "ARTWORK")
  l:SetColorTexture(color[1], color[2], color[3], 1)
  l:SetThickness(thickness or 1.5)
  return l
end

-- Pools of textures/lines so charts can be redrawn without leaking objects
function W.Pool(create)
  local p = { items = {}, used = 0 }
  function p:Get()
    self.used = self.used + 1
    local o = self.items[self.used]
    if not o then
      o = create()
      self.items[self.used] = o
    end
    o:Show()
    return o
  end
  function p:Reset()
    for i = 1, #self.items do self.items[i]:Hide() end
    self.used = 0
  end
  return p
end

-- ---------------------------------------------------------------------------
-- Table rows: background, hover, money columns
-- ---------------------------------------------------------------------------
-- A row's own background (a selected row, a group's header row): hidden until the
-- row raises its alpha. The color itself is solid, so SetAlpha(1) shows all of it.
function W.RowBg(r, color)
  local t = W.Tex(r, color or C.raised, nil, "BACKGROUND")
  t:SetAllPoints()
  t:SetAlpha(0)
  return t
end

-- The selected row (the item on the chart, the open recipe): the game's own selection
-- highlight, else a solid band. Hidden at first, like W.RowBg: SetAlpha(1) to show.
local SELECT_ATLAS = "auctionhouse-ui-row-select"
local SELECT_FILE = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local function hasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
function W.RowSelect(r)
  if not W.Native() then return W.RowBg(r) end
  local t = r:CreateTexture(nil, "BACKGROUND", nil, 6)
  t:SetAllPoints()
  if hasAtlas(SELECT_ATLAS) then
    t:SetAtlas(SELECT_ATLAS)
  else
    t:SetTexture(SELECT_FILE)
    t:SetVertexColor(1, 0.82, 0.3, 0.55)
  end
  t:SetBlendMode("ADD")
  t:SetAlpha(0)
  return t
end

-- The Auction House's own row highlight when the client has it, else a warm tint
local HOVER_ATLAS = "auctionhouse-ui-row-highlight"

-- The row under the mouse: its plain text (grey or off-white) turns white. Colored text
-- (green, red, an item's quality) keeps its color, so the meaning stays.
local function light(r)
  r.lit = {}
  for _, region in ipairs({ r:GetRegions() }) do
    if region:GetObjectType() == "FontString" then
      local cr, cg, cb = region:GetTextColor()
      local hi = math.max(cr, cg, cb)
      if hi >= 0.65 and hi - math.min(cr, cg, cb) < 0.15 then
        r.lit[region] = { cr, cg, cb }
        region:SetTextColor(1, 1, 1)
      end
    end
  end
end
local function unlight(r)
  if not r.lit then return end
  for fs, c in pairs(r.lit) do fs:SetTextColor(c[1], c[2], c[3]) end
  r.lit = nil
end

-- Gives a row the hover highlight. Rows in a W.List get it by themselves.
function W.RowHover(r)
  if r.hover then return end
  local hl = r:CreateTexture(nil, "BACKGROUND", nil, 7)
  hl:SetAllPoints()
  if hasAtlas(HOVER_ATLAS) then
    hl:SetAtlas(HOVER_ATLAS)
    hl:SetBlendMode("ADD")
  else
    hl:SetColorTexture(0.32, 0.28, 0.20, 0.55)
  end
  hl:Hide()
  r.hover = hl
  r:HookScript("OnEnter", function(self) self.hover:Show(); light(self) end)
  r:HookScript("OnLeave", function(self) self.hover:Hide(); unlight(self) end)
end

-- Refills a row that the mouse may be on: its old colors go back first, then the new
-- ones light up (a refresh or a scroll under a still mouse).
function W.RefillRow(r, fill, ...)
  local lit = r.lit
  if lit then unlight(r) end
  fill(r, ...)
  if lit then light(r) end
end

-- A money column: each amount is one right-aligned piece of text, so every row ends on
-- the column's edge, with the unit letters in grey so the digits stand out. One
-- W.MoneyColumn is shared by that column's cells in every row: it shows copper only
-- when nothing in the column reaches 1 gold.

function W.MoneyColumn()
  local col = { copper = true }
  -- Looks at every row, not just the ones on screen, so it holds while scrolling.
  -- get: a field name, or get(row) returning the amount
  function col:Fit(rows, get)
    local top = 0
    for _, row in ipairs(rows) do
      local v
      if type(get) == "function" then v = get(row) else v = row[get] end
      if type(v) == "number" then top = math.max(top, math.abs(v)) end
    end
    self.copper = top < 10000
  end
  return col
end

-- right: the column's right edge (offset from the row's right side)
function W.MoneyCell(r, right, column, size)
  local fs = W.Text(r, size or W.SIZE.cell, C.text, true)
  fs:SetPoint("RIGHT", r, "RIGHT", right, 0)
  fs:SetJustifyH("RIGHT")
  fs.column = column or { copper = true }
  -- sign: true puts a + on gains (a loss always gets its -)
  function fs:SetMoney(copper, sign)
    if not copper then return self:SetText("-") end
    copper = math.floor(copper + 0.5)
    local pre = copper < 0 and "-" or (sign and "+" or "")
    copper = math.abs(copper)
    local gv, sv, cv = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    local out
    if gv >= 1000 then
      out = FI.Number(gv) .. FI.COIN.g
    elseif gv > 0 then
      out = gv .. FI.COIN.g .. (sv > 0 and (" " .. sv .. FI.COIN.s) or "")
    elseif sv > 0 then
      out = sv .. FI.COIN.s .. ((self.column.copper and cv > 0) and (" " .. cv .. FI.COIN.c) or "")
    else
      out = cv .. FI.COIN.c
    end
    self:SetText(pre .. out)
  end
  return fs
end

-- Mouse-wheel list. Builds `rowCount` rows; shows as many as fit the frame's height,
-- so a taller window shows more rows. update(row, index) fills a row.
function W.List(parent, rowCount, rowHeight, makeRow, update)
  local l = CreateFrame("Frame", nil, parent)
  l.rows, l.offset, l.count, l.visible = {}, 0, 0, rowCount
  for i = 1, rowCount do
    local r = makeRow(l, i)
    r:SetHeight(rowHeight)
    -- a stripe on every other row, under the row's own hover/selection, so the eye
    -- stays on one row across a wide table
    r.zebra = r:CreateTexture(nil, "BACKGROUND", nil, -8)
    r.zebra:SetAllPoints()
    r.zebra:SetColorTexture(1, 0.95, 0.85, 0.05)
    W.RowHover(r)
    r:SetPoint("TOPLEFT", l, "TOPLEFT", 0, -(i - 1) * rowHeight)
    r:SetPoint("RIGHT", l, "RIGHT")
    l.rows[i] = r
  end
  function l:Fit()
    local h = self:GetHeight()
    if h and h > rowHeight then self.visible = math.max(1, math.min(rowCount, math.floor(h / rowHeight))) end
  end
  function l:SetCount(n)
    self:Fit()
    self.count = n
    self.offset = math.max(0, math.min(self.offset, n - self.visible))
    self:Refresh()
  end
  function l:Refresh()
    for i, r in ipairs(self.rows) do
      local idx = self.offset + i
      if i <= self.visible and idx <= self.count then
        r:Show()
        r.zebra:SetShown(idx % 2 == 0)
        W.RefillRow(r, update, idx)
      else
        r:Hide()
      end
    end
    self:UpdateBar()
  end
  function l:ScrollTo(offset)
    self.offset = math.max(0, math.min(math.floor(offset + 0.5), self.count - self.visible))
    self:Refresh()
  end
  l:EnableMouseWheel(true)
  l:SetScript("OnMouseWheel", function(self, delta)
    local step = IsShiftKeyDown() and self.visible or 3
    self:ScrollTo(self.offset - delta * step)
  end)

  -- Scroll bar on the right. The game's look: arrows at both ends and its knob; the
  -- flat look: a thin track whose thumb's size is how much of the list you see. Drag
  -- the thumb, click an arrow for a row, or click the track to jump a page.
  local native = W.Native()
  local arrow = native and 12 or 0 -- room each arrow takes at the ends
  local bar = CreateFrame("Button", nil, l)
  bar:SetPoint("TOPRIGHT", l, "TOPRIGHT", native and -1 or -3, native and -1 or -3)
  bar:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", native and -1 or -3, native and 1 or 3)
  bar:SetWidth(native and 12 or 7)
  bar:SetFrameLevel((l:GetFrameLevel() or 1) + 10)
  bar.track = W.Tex(bar, native and C.bg or C.border, native and 0.6 or 0.55, "BACKGROUND")
  bar.track:SetPoint("TOPLEFT", 0, -arrow)
  bar.track:SetPoint("BOTTOMRIGHT", 0, arrow)
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(native and 12 or 7)
  thumb:SetPoint("TOP", bar, "TOP", 0, -arrow)
  thumb:EnableMouse(true)
  if native then
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    thumb.tex:SetTexCoord(0.2, 0.8, 0.125, 0.875)
  else
    thumb.tex = W.Tex(thumb, C.muted, 0.9, "ARTWORK")
  end
  thumb.tex:SetAllPoints()
  local function thumbLit(on)
    if native then
      local v = on and 1 or 0.85
      thumb.tex:SetVertexColor(v, v, v)
    elseif on then
      thumb.tex:SetColorTexture(C.soft[1], C.soft[2], C.soft[3], 1)
    else
      thumb.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.9)
    end
  end
  thumbLit(false)
  bar.thumb = thumb
  l.bar = bar
  if native then
    local function arrowButton(dir, step)
      local b = CreateFrame("Button", nil, bar)
      b:SetSize(12, 12)
      b:SetPoint(dir == "Up" and "TOP" or "BOTTOM")
      local base = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. dir .. "Button-"
      for _, kind in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
        local file = base .. (kind == "Normal" and "Up" or kind == "Pushed" and "Down" or kind)
        local set = b["Set" .. kind .. "Texture"]
        if kind == "Highlight" then set(b, file, "ADD") else set(b, file) end
        local t = b["Get" .. kind .. "Texture"](b)
        if t then t:SetTexCoord(0.2, 0.8, 0.25, 0.75) end
      end
      b:SetScript("OnClick", function() l:ScrollTo(l.offset + step) end)
      return b
    end
    bar.up = arrowButton("Up", -1)
    bar.down = arrowButton("Down", 1)
  end
  local function travel()
    local trackH = (bar:GetHeight() or 0) - 2 * arrow
    return trackH, math.max(0, trackH - (thumb:GetHeight() or 0)), math.max(1, l.count - l.visible)
  end
  function l:UpdateBar()
    if self.count <= self.visible then bar:Hide(); return end
    bar:Show()
    if bar.up then
      bar.up:SetEnabled(self.offset > 0)
      bar.down:SetEnabled(self.offset < self.count - self.visible)
    end
    local trackH = travel()
    if trackH <= 0 then return end
    -- the game's knob keeps its shape; the flat thumb shows how much is in view
    thumb:SetHeight(native and math.min(18, trackH) or math.max(24, trackH * self.visible / self.count))
    local _, room, maxOff = travel()
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -arrow - room * math.min(1, self.offset / maxOff))
  end
  local function cursorY()
    local _, y = GetCursorPosition()
    return (y or 0) / ((bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1)
  end
  thumb:SetScript("OnEnter", function() thumbLit(true) end)
  thumb:SetScript("OnLeave", function() if not bar.dragging then thumbLit(false) end end)
  thumb:SetScript("OnMouseDown", function()
    bar.dragging = { y = cursorY(), offset = l.offset }
  end)
  thumb:SetScript("OnMouseUp", function()
    bar.dragging = nil
    thumbLit(false)
  end)
  bar:SetScript("OnUpdate", function()
    local d = bar.dragging
    if not d then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      bar.dragging = nil
      thumbLit(false)
      return
    end
    local _, room, maxOff = travel()
    if room <= 0 then return end
    l:ScrollTo(d.offset + (d.y - cursorY()) / room * maxOff)
  end)
  bar:SetScript("OnClick", function()
    -- a page towards where you clicked
    local top = thumb:GetTop() or 0
    local bottom = thumb:GetBottom() or 0
    local y = cursorY()
    if y > top then l:ScrollTo(l.offset - l.visible) elseif y < bottom then l:ScrollTo(l.offset + l.visible) end
  end)
  bar:Hide()
  l:SetScript("OnSizeChanged", function(self) self:Fit(); self:UpdateBar() end)
  return l
end

-- ---------------------------------------------------------------------------
-- Sortable column headers (click to sort, click again to reverse)
-- ---------------------------------------------------------------------------
function W.Chevron(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(8, 5)
  f.a = W.Line(f, C.gold, 1.5)
  f.b = W.Line(f, C.gold, 1.5)
  -- pointing right (a closed section): ">"
  function f:SetRight()
    if not self.a then return end
    self:SetSize(5, 8)
    self.a:SetStartPoint("TOPLEFT", self, 0, 0); self.a:SetEndPoint("RIGHT", self, 0, 0)
    self.b:SetStartPoint("RIGHT", self, 0, 0); self.b:SetEndPoint("BOTTOMLEFT", self, 0, 0)
  end
  function f:SetDown(down)
    if not self.a then return end
    self:SetSize(8, 5)
    if down then
      self.a:SetStartPoint("TOPLEFT", self, 0, 0); self.a:SetEndPoint("BOTTOM", self, 0, 0)
      self.b:SetStartPoint("BOTTOM", self, 0, 0); self.b:SetEndPoint("TOPRIGHT", self, 0, 0)
    else
      self.a:SetStartPoint("BOTTOMLEFT", self, 0, 0); self.a:SetEndPoint("TOP", self, 0, 0)
      self.b:SetStartPoint("TOP", self, 0, 0); self.b:SetEndPoint("BOTTOMRIGHT", self, 0, 0)
    end
  end
  return f
end

-- The open/closed mark on a group row: the quest log's +/- in the game's look, else a
-- chevron. Same calls as W.Chevron: SetRight() closed, SetDown(true) open.
local PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
function W.Expander(parent)
  if not W.Native() then return W.Chevron(parent) end
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(14, 14)
  t:SetTexture(PLUS)
  function t:SetRight() self:SetTexture(PLUS) end
  function t:SetDown(down) self:SetTexture(down and MINUS or PLUS) end
  return t
end

-- cols: { key, label, x = offset from the left edge | r = offset from the right edge
--         | at = offset from the right edge for a left-aligned column, dir = 1 (A-Z) or
--         -1 (highest first, the default), nosort = true }
-- state: a table with .sort (key) and .dir; onChange() is called after a click.
function W.SortHeaders(head, cols, state, onChange)
  local hs = { buttons = {}, state = state }
  for _, col in ipairs(cols) do
    local b = CreateFrame("Button", nil, head)
    b:SetHeight(head:GetHeight() > 0 and head:GetHeight() or 30)
    b.text = W.Heading(b, col.label)
    b.col = col
    b.left = col.x ~= nil or col.at ~= nil
    if col.x then
      b:SetPoint("LEFT", head, "LEFT", col.x, 0)
    elseif col.at then
      b:SetPoint("LEFT", head, "RIGHT", col.at, 0)
    else
      b:SetPoint("RIGHT", head, "RIGHT", col.r or -14, 0)
    end
    b.text:SetPoint(b.left and "LEFT" or "RIGHT")
    if not b.left then b.text:SetJustifyH("RIGHT") end
    b:SetWidth(b.text:GetStringWidth() + 14)
    if not col.nosort then
      b.arrow = W.Chevron(b)
      b.arrow:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
      b.arrow:Hide()
      b:SetScript("OnClick", function()
        if state.sort == col.key then
          state.dir = -(state.dir or -1)
        else
          state.sort, state.dir = col.key, col.dir or -1
        end
        hs:Update()
        onChange()
      end)
      b:SetScript("OnEnter", function(self)
        self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(state.sort == col.key and "Click to reverse the order" or ("Click to sort by " .. col.label:lower()), C.soft[1], C.soft[2], C.soft[3])
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() hs:Update(); GameTooltip_Hide() end)
    end
    hs.buttons[col.key] = b
  end
  function hs:Update()
    for key, b in pairs(self.buttons) do
      local on = key == state.sort
      local c = on and C.gold or C.soft
      b.text:SetTextColor(c[1], c[2], c[3])
      if b.arrow then
        b.arrow:SetShown(on)
        if on then b.arrow:SetDown((state.dir or -1) < 0) end
        if not b.left then
          -- right-aligned: make room for the arrow so it sits beside its own column
          b.text:ClearAllPoints()
          b.text:SetPoint("RIGHT", b, "RIGHT", on and -12 or 0, 0)
        end
      end
    end
  end
  function hs:SetLabel(key, text)
    local b = self.buttons[key]
    if not b then return end
    b.col.label = text
    b.text:SetText(text)
    b:SetWidth(b.text:GetStringWidth() + 14)
  end
  hs:Update()
  return hs
end

-- Sorts rows by a field (or get(row) for computed values). Missing values go last
-- either way; ties fall back to the name, so the order never jumps around.
function W.SortRows(rows, key, dir, get)
  dir = dir or -1
  local function val(r)
    if get then return get(r) end
    return r[key]
  end
  local cache = {}
  for i = 1, #rows do
    local v = val(rows[i])
    if type(v) == "string" then v = v:lower() end
    if v == nil then v = false end -- (a missing value; "v == nil and false or v" would give nil back)
    cache[rows[i]] = v
  end
  table.sort(rows, function(a, b)
    local va, vb = cache[a], cache[b]
    if va == false and vb == false then return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end
    if va == false then return false end
    if vb == false then return true end
    if va == vb then return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end
    if dir < 0 then return va > vb else return va < vb end
  end)
  return rows
end

-- ---------------------------------------------------------------------------
-- The goblin: the game's own goblin NPC models. The first one the client can
-- load is used; if none load, `fallback` (a texture) is shown instead.
-- portrait = true frames just the head, for the logo.
-- ---------------------------------------------------------------------------
W.GOBLINS = { 3391, 8738, 2496 }

-- onReady(model) runs once a goblin has loaded.
function W.Goblin(parent, portrait, onFail, onReady)
  local m = CreateFrame("PlayerModel", nil, parent)
  local function try(i)
    local id = W.GOBLINS[i]
    if not id then
      m:Hide()
      if onFail then onFail() end
      return
    end
    m:ClearModel()
    m:SetCreature(id)
    C_Timer.After(0.6, function()
      local loaded = true
      if m.GetModelFileID then loaded = m:GetModelFileID() ~= nil end
      if not loaded then return try(i + 1) end
      if portrait then
        m:SetPortraitZoom(1)
        m:SetCamDistanceScale(1)
        m:SetFacing(0)
      else
        m:SetPortraitZoom(0)
        m:SetCamDistanceScale(1.15)
        m:SetFacing(-0.35)
      end
      m:Show()
      if onReady then onReady(m) end
    end)
  end
  m.Load = function() if not m.loaded then m.loaded = true; try(1) end end
  return m
end

-- A soft shadow around a frame (two dark layers just outside its edges)
function W.Shadow(f)
  for i, a in ipairs({ 0.35, 0.18 }) do
    local sh = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sh:SetPoint("TOPLEFT", -3 * i, 3 * i)
    sh:SetPoint("BOTTOMRIGHT", 3 * i, -3 * i)
    sh:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    sh:SetBackdrop({ edgeFile = WHITE, edgeSize = 3 })
    sh:SetBackdropBorderColor(0, 0, 0, a)
  end
end

-- Header band for tables: slightly darker strip with a hairline under it
function W.TableHeader(parent, height)
  local head = CreateFrame("Frame", nil, parent)
  head:SetPoint("TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", -1, -1)
  head:SetHeight(height or 30)
  local bg = head:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(C.side[1], C.side[2], C.side[3], C.side[4] or 1)
  local line = head:CreateTexture(nil, "BORDER")
  line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  return head
end
