-- Goonberg Terminal: small UI building blocks in the Goonberg Terminal look
local _, FI = ...
local W = {}
FI.Widgets = W
local C = FI.colors

W.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
W.NUMFONT = "Fonts\\ARIALN.TTF"
local WHITE = "Interface\\Buttons\\WHITE8X8"

function W.Box(parent, bg, border, alpha)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  bg = bg or C.panel
  border = border or C.border
  f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
  f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
  return f
end

function W.Tex(parent, color, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
  return t
end

-- Nothing smaller than 11: below that the game's fonts get hard to read
W.MIN_SIZE = 11
function W.Text(parent, size, color, num, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  size = math.max(size or 12, W.MIN_SIZE)
  -- Arial Narrow runs small next to the game font: one point up keeps numbers level with words
  if num then size = size + 1 end
  fs:SetFont(num and W.NUMFONT or W.FONT, size, flags or "")
  color = color or C.text
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- A flat button. style: "gold" (filled), "pill" (outlined, gold when selected), "seg" (segment), "ghost"
function W.Button(parent, label, width, height, style)
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
    local bg, bd, tx, ba = C.panel, C.border, C.soft, 0
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

-- A group of mutually exclusive buttons. onPick(value)
function W.Choice(parent, values, style, onPick, height)
  local g = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  g.buttons = {}
  local x = 0
  local inset = (style == "seg") and 3 or 0
  if style == "seg" then
    g:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    g:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 1)
    g:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
    x = inset
  end
  for _, v in ipairs(values) do
    local b = W.Button(g, v, nil, (height or 26) - inset * 2, style)
    b:SetPoint("LEFT", g, "LEFT", x, 0)
    b:SetScript("OnClick", function() g:Select(v); onPick(v) end)
    x = x + b:GetWidth() + ((style == "seg") and 2 or (style == "tab" and 0 or 6))
    g.buttons[v] = b
  end
  g:SetSize(math.max(1, x - ((style == "seg") and 2 or 6) + inset), height or 26)
  function g:Select(value)
    self.value = value
    for v, b in pairs(self.buttons) do b:SetSelected(v == value) end
  end
  return g
end

function W.EditBox(parent, width, placeholder)
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

-- Small uppercase heading
function W.Heading(parent, text)
  local fs = W.Text(parent, 11, C.muted)
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

-- Mouse-wheel list. Builds `rowCount` rows; shows as many as fit the frame's height,
-- so a taller window shows more rows. update(row, index) fills a row.
function W.List(parent, rowCount, rowHeight, makeRow, update)
  local l = CreateFrame("Frame", nil, parent)
  l.rows, l.offset, l.count, l.visible = {}, 0, 0, rowCount
  for i = 1, rowCount do
    local r = makeRow(l, i)
    r:SetHeight(rowHeight)
    -- faint stripe on every other row, under the row's own hover/selection
    r.zebra = r:CreateTexture(nil, "BACKGROUND", nil, -8)
    r.zebra:SetAllPoints()
    r.zebra:SetColorTexture(1, 1, 1, 0.025)
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
        update(r, idx)
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

  -- Scroll bar on the right: the thumb's size is how much of the list you see, its
  -- place is where you are. Drag it, or click the track to jump a page.
  local bar = CreateFrame("Button", nil, l)
  bar:SetPoint("TOPRIGHT", l, "TOPRIGHT", -3, -3)
  bar:SetPoint("BOTTOMRIGHT", l, "BOTTOMRIGHT", -3, 3)
  bar:SetWidth(7)
  bar:SetFrameLevel((l:GetFrameLevel() or 1) + 10)
  bar.track = W.Tex(bar, C.border, 0.55, "BACKGROUND")
  bar.track:SetAllPoints()
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(7)
  thumb:SetPoint("TOP", bar, "TOP", 0, 0)
  thumb:EnableMouse(true)
  thumb.tex = W.Tex(thumb, C.muted, 0.9, "ARTWORK")
  thumb.tex:SetAllPoints()
  bar.thumb = thumb
  l.bar = bar
  local function travel()
    local trackH = bar:GetHeight() or 0
    return trackH, math.max(0, trackH - (thumb:GetHeight() or 0)), math.max(1, l.count - l.visible)
  end
  function l:UpdateBar()
    if self.count <= self.visible then bar:Hide(); return end
    bar:Show()
    local trackH = bar:GetHeight() or 0
    if trackH <= 0 then return end
    thumb:SetHeight(math.max(24, trackH * self.visible / self.count))
    local _, room, maxOff = travel()
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -room * math.min(1, self.offset / maxOff))
  end
  local function cursorY()
    local _, y = GetCursorPosition()
    return (y or 0) / ((bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1)
  end
  thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(C.soft[1], C.soft[2], C.soft[3], 1) end)
  thumb:SetScript("OnLeave", function(self) if not bar.dragging then self.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.9) end end)
  thumb:SetScript("OnMouseDown", function()
    bar.dragging = { y = cursorY(), offset = l.offset }
  end)
  thumb:SetScript("OnMouseUp", function()
    bar.dragging = nil
    thumb.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.9)
  end)
  bar:SetScript("OnUpdate", function()
    local d = bar.dragging
    if not d then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
      bar.dragging = nil
      thumb.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.9)
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
        GameTooltip:AddLine(state.sort == col.key and "Click to reverse the order" or ("Click to sort by " .. col.label:lower()), 0.76, 0.79, 0.83)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() hs:Update(); GameTooltip_Hide() end)
    end
    hs.buttons[col.key] = b
  end
  function hs:Update()
    for key, b in pairs(self.buttons) do
      local on = key == state.sort
      local c = on and C.gold or C.muted
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

function W.Goblin(parent, portrait, onFail)
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
  bg:SetColorTexture(C.side[1], C.side[2], C.side[3], 1)
  local line = head:CreateTexture(nil, "BORDER")
  line:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
  line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
  return head
end
