-- Goonberg Terminal: move the Auction House's buy confirmations (and any other
-- popup that opens at the AH). Hold Alt and drag the popup by its background: it
-- opens there from then on. /goon buypopup reset puts them all back.
-- Alt-drag works on whatever frame you grab, so it doesn't depend on knowing the
-- popup's name in your client. It never starts on a button, so dragging can't press
-- Buy.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.AuctionPopups
local P = {}
FI.AuctionPopups = P

local function store()
  FI.settings.ahPopups = FI.settings.ahPopups or {}
  local s = FI.settings.ahPopups
  -- spots saved by 0.35.0 under its own names
  if s.commodity then s["AuctionHouseFrame.BuyDialog"] = s["AuctionHouseFrame.BuyDialog"] or s.commodity; s.commodity = nil end
  if s.popup then
    s["popup:BUYOUT_AUCTION"] = s["popup:BUYOUT_AUCTION"] or s.popup
    s["popup:BID_AUCTION"] = s["popup:BID_AUCTION"] or s.popup
    s.popup = nil
  end
  return s
end

local function setAt(f, pos)
  local x, y = pos[3], pos[4]
  -- a spot in screen units (from the placement box): convert to the frame's scale,
  -- since a popup on the AH window is scaled with it
  if pos.ui then
    local fs, us = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if fs and fs > 0 and us then x, y = x * us / fs, y * us / fs end
  end
  f:ClearAllPoints()
  f:SetPoint(pos[1], UIParent, pos[2], x, y)
end

local function place(f, key)
  local pos = store()[key]
  if not pos then return end
  setAt(f, pos)
  -- and again a moment later, in case the game lays the popup out after showing it
  C_Timer.After(0, function()
    local now = store()[key]
    if now and f:IsShown() then setAt(f, now) end
  end)
end

-- A frame's lasting name: its global name, or its parent's name plus its key
-- ("AuctionHouseFrame.BuyDialog"). The game's shared popups (StaticPopup1..4) are
-- named by what they're asking ("popup:BUYOUT_AUCTION"), since the same frame asks
-- different things.
local function keyOf(f)
  if f.which and type(f.which) == "string" then return "popup:" .. f.which end
  local n = f.GetName and f:GetName()
  if n then return n end
  local parent = f:GetParent()
  local pk = f.GetParentKey and f:GetParentKey()
  local pn = parent and parent.GetName and parent:GetName()
  if pk and pn then return pn .. "." .. pk end
  return nil
end

local function resolve(key)
  local f
  for part in key:gmatch("[^%.]+") do
    f = (f == nil) and _G[part] or (f and f[part])
  end
  return type(f) == "table" and f.GetObjectType and f or nil
end

-- frames we put back each time they open
local hooked = {}
local function remember(f, key)
  if hooked[f] or key:find("^popup:") then return end
  hooked[f] = true
  f:HookScript("OnShow", function(self) place(self, key) end)
end

-- the popups we know by name, checked by where the cursor is (a popup's background
-- often ignores the mouse, so what's "under the mouse" can be the window behind it)
local function knownPopups()
  local out = {}
  local ah = _G.AuctionHouseFrame
  if ah and ah.BuyDialog then out[#out + 1] = ah.BuyDialog end
  for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
    local f = _G["StaticPopup" .. i]
    if f then out[#out + 1] = f end
  end
  return out
end

local function mouseFocus()
  if GetMouseFoci then
    local list = GetMouseFoci()
    return list and list[1]
  elseif GetMouseFocus then
    return GetMouseFocus()
  end
end

-- the window you grabbed: a known popup under the cursor, or else climb from what's
-- under the mouse to the frame that sits directly on the screen or on the AH window
-- (not the AH window itself)
-- a button you'd actually press (Buy Now, Cancel, a close X): labelled, or small next
-- to the popup. Some clients build the popup's background as one big unlabelled
-- button, and grabbing that is fine.
local function pressable(b, popup)
  if not (b and b.IsObjectType and b:IsObjectType("Button")) then return false end
  if b == popup then return false end
  local t = b.GetText and b:GetText()
  if t and t ~= "" then return true end
  if popup and b.GetWidth and popup.GetWidth then
    return (b:GetWidth() or 0) < (popup:GetWidth() or 0) * 0.6
  end
  return true
end

local function grabbed()
  local focus = mouseFocus()
  local popup
  for _, f in ipairs(knownPopups()) do
    if f:IsShown() and f:IsMouseOver() then popup = f; break end
  end
  if pressable(focus, popup) then return nil, "button" end
  if popup then return popup end
  if not focus or focus == WorldFrame or not focus.GetParent then return nil, "nothing" end
  local ah = _G.AuctionHouseFrame or _G.AuctionFrame
  local f = focus
  while f do
    local parent = f:GetParent()
    if not parent or parent == UIParent or parent == ah then break end
    f = parent
  end
  if not f or f == UIParent or f == ah then return nil, "nothing" end
  return f
end

local moving
local function startMove()
  local f, why = grabbed()
  if not f then
    if why == "button" then
      FI:Print("Grab the popup by its background, not a button, to move it (or use /goon buypopup move).")
    elseif not P.toldNothing then
      P.toldNothing = true
      local focus = mouseFocus()
      FI:Print("Found no popup to move there (under the cursor: %s).",
        focus and (focus.GetDebugName and focus:GetDebugName() or tostring(focus)) or "nothing")
    end
    return
  end
  local key = keyOf(f)
  if not key then return end
  if not f:IsMovable() then f:SetMovable(true) end
  f:SetClampedToScreen(true)
  local ok = pcall(f.StartMoving, f)
  if ok then moving = { f = f, key = key } end
end

local function stopMove()
  local m = moving
  moving = nil
  if not m then return end
  m.f:StopMovingOrSizing()
  -- keep the spot in Goonberg's settings, not the game's layout cache
  if m.f.SetUserPlaced then pcall(m.f.SetUserPlaced, m.f, false) end
  local point, _, relPoint, x, y = m.f:GetPoint(1)
  if not point then return end
  store()[m.key] = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
  remember(m.f, m.key)
  if not P.toldOnce then
    P.toldOnce = true
    FI:Print("Moved. It opens there from now on (/goon buypopup reset puts it back).")
  end
end

-- Watch for Alt + left mouse button while an AH window is showing (also right after
-- a /reload at the AH, when the AH-open event has already passed)
local function ahShowing()
  local ah = _G.AuctionHouseFrame or _G.AuctionFrame
  return FI.ahOpen or (ah and ah:IsShown())
end
local watch = CreateFrame("Frame")
local wasDown = false
watch:SetScript("OnUpdate", function()
  if not moving and not ahShowing() then wasDown, P.restored = false, false; return end
  if not P.restored then P.restored = true; P:Restore() end
  local down = IsMouseButtonDown("LeftButton")
  if down and not wasDown and IsAltKeyDown() and not moving then startMove()
  elseif not down and moving then stopMove() end
  wasDown = down
end)

-- the game's shared popups: back to the saved spot each time one asks the same thing
function P:SetupPopups()
  if self.popupsDone or not hooksecurefunc or not _G.StaticPopup_Show then return end
  self.popupsDone = true
  hooksecurefunc("StaticPopup_Show", function(which)
    if not which or not store()["popup:" .. which] then return end
    for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
      local f = _G["StaticPopup" .. i]
      if f and f:IsShown() and f.which == which then place(f, "popup:" .. which) end
    end
  end)
end

-- frames moved before (they load with the AH, so this runs when it opens)
function P:Restore()
  for key in pairs(store()) do
    if not key:find("^popup:") then
      local f = resolve(key)
      if f then remember(f, key) end
    end
  end
end

-- /goon buypopup move: a box of Goonberg's own that you drag to where the Buy popup
-- should open. Works whatever the popup does with the mouse.
local BUY_KEY = "AuctionHouseFrame.BuyDialog"
function P:Hook()
  local dlg = _G.AuctionHouseFrame and _G.AuctionHouseFrame.BuyDialog
  if dlg then remember(dlg, BUY_KEY) end
  return dlg
end

function P:ShowPlacer()
  local box = self.placer
  if not box then
    box = CreateFrame("Frame", "GoonbergBuyPopupPlacer", UIParent)
    box:SetSize(380, 110)
    box:SetFrameStrata("DIALOG")
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", box.StopMovingOrSizing)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.85)
    local edge = box:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", 2, -2)
    edge:SetColorTexture(1, 0.82, 0, 0.6)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOP", 0, -16)
    text:SetWidth(350)
    text:SetText("|cffffd100Goonberg|r\nDrag this box to where the Buy popup should open.")
    local done = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    done:SetSize(110, 24)
    done:SetPoint("BOTTOM", 0, 12)
    done:SetText("Done")
    done:SetScript("OnClick", function() P:SavePlacer() end)
    self.placer = box
  end
  box:ClearAllPoints()
  local pos = store()[BUY_KEY]
  if pos and pos.ui then box:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else box:SetPoint("CENTER") end
  box:Show()
end

function P:SavePlacer()
  local box = self.placer
  if not box then return end
  local x, y = box:GetCenter()
  if not x then return end
  store()[BUY_KEY] = { "CENTER", "BOTTOMLEFT", math.floor(x + 0.5), math.floor(y + 0.5), ui = true }
  box:Hide()
  self:Hook()
  FI:Print("The Buy popup opens there from now on (/goon buypopup reset puts it back).")
end

function P:Reset()
  FI.settings.ahPopups = nil
  FI:Print("AH popups open where the game puts them again (after a /reload for any that are open now).")
end

FI:On("PLAYER_LOGIN", function() P:SetupPopups() end)
FI:On("FI_AH_OPEN", function()
  P:SetupPopups()
  P:Restore()
  P:Hook()
end)
FI:On("FI_AH_CLOSED", function()
  if moving then stopMove() end
end)
