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

function W.Text(parent, size, color, num, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(num and W.NUMFONT or W.FONT, size or 12, flags or "")
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
  b.label = W.Text(b, 12, C.soft)
  b.label:SetPoint("CENTER")
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
    elseif s == "seg" then
      bd = on and C.raised or C.panel
      bg, tx, ba = C.raised, on and C.text or C.muted, on and 1 or (hover and 0.5 or 0)
      if not on then bd = C.panel end
    else
      bg, bd, tx, ba = C.raised, hover and C.muted or C.border, hover and C.text or C.soft, hover and 1 or 0
    end
    self:SetBackdropColor(bg[1], bg[2], bg[3], ba)
    self:SetBackdropBorderColor(bd[1], bd[2], bd[3], (s == "seg") and 0 or 1)
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
  local g = CreateFrame("Frame", nil, parent)
  g.buttons = {}
  local x = 0
  for _, v in ipairs(values) do
    local b = W.Button(g, v, nil, height or 26, style)
    b:SetPoint("LEFT", g, "LEFT", x, 0)
    b:SetScript("OnClick", function() g:Select(v); onPick(v) end)
    x = x + b:GetWidth() + 4
    g.buttons[v] = b
  end
  g:SetSize(math.max(1, x - 4), height or 26)
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
        update(r, idx)
      else
        r:Hide()
      end
    end
  end
  l:EnableMouseWheel(true)
  l:SetScript("OnMouseWheel", function(self, delta)
    local step = IsShiftKeyDown() and self.visible or 3
    self.offset = math.max(0, math.min(self.offset - delta * step, self.count - self.visible))
    self:Refresh()
  end)
  return l
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
