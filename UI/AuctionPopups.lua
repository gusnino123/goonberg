-- Goonberg Terminal: move the Auction House's buy confirmations.
-- Drag the "buy this?" box anywhere and it opens there from then on:
--   modern AH: the commodity Buy dialog (AuctionHouseFrame.BuyDialog)
--   both AHs: the game's Buyout / Bid confirmation popups
-- /goon buypopup reset puts them back where the game puts them.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.AuctionPopups
local P = {}
FI.AuctionPopups = P

-- the game's AH confirmation popups (StaticPopup "which" names)
P.WHICH = { BUYOUT_AUCTION = true, BID_AUCTION = true }

local function saved(key)
  FI.settings.ahPopups = FI.settings.ahPopups or {}
  return FI.settings.ahPopups, FI.settings.ahPopups[key]
end

local function place(f, key)
  local _, pos = saved(key)
  if not pos then return end
  f:ClearAllPoints()
  f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

-- Make a frame draggable. `canDrag(f)` decides each time (a shared popup frame is
-- only ours to move while it's asking about an auction); `keyOf(f)` names the spot.
local function movable(f, keyOf, canDrag)
  if not f or f.goonMovable then return end
  f.goonMovable = true
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:HookScript("OnDragStart", function(self)
    if canDrag and not canDrag(self) then return end
    self.goonMoving = true
    self:StartMoving()
  end)
  f:HookScript("OnDragStop", function(self)
    if not self.goonMoving then return end
    self.goonMoving = false
    self:StopMovingOrSizing()
    -- keep the spot in Goonberg's settings, not the game's layout cache, which would
    -- also pin the shared popup for everything else that uses it
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    local point, _, relPoint, x, y = self:GetPoint(1)
    local all = saved(keyOf(self))
    all[keyOf(self)] = { point, relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
  end)
end

-- Modern AH: the commodity Buy dialog. It loads with the AH, so we set it up once
-- the AH has opened.
function P:SetupModern()
  local ah = _G.AuctionHouseFrame
  local dlg = ah and ah.BuyDialog
  if not dlg or dlg.goonMovable then return end
  dlg.goonHome = { dlg:GetPoint(1) } -- where the game puts it, for a reset
  movable(dlg, function() return "commodity" end)
  dlg:HookScript("OnShow", function(self) place(self, "commodity") end)
end

-- Both AHs: the game's popups are shared frames (StaticPopup1..4) that it places
-- again each time one opens, so ours go back to the saved spot right after.
local function popupFrames()
  local out = {}
  for i = 1, (_G.STATICPOPUP_NUMDIALOGS or 4) do
    local f = _G["StaticPopup" .. i]
    if f then out[#out + 1] = f end
  end
  return out
end

function P:SetupPopups()
  if self.popupsDone then return end
  self.popupsDone = true
  for _, f in ipairs(popupFrames()) do
    movable(f, function() return "popup" end, function(self) return P.WHICH[self.which] end)
  end
  if hooksecurefunc and _G.StaticPopup_Show then
    hooksecurefunc("StaticPopup_Show", function(which)
      if not P.WHICH[which] then return end
      for _, f in ipairs(popupFrames()) do
        if f:IsShown() and f.which == which then place(f, "popup") end
      end
    end)
  end
end

function P:Reset()
  FI.settings.ahPopups = nil
  -- the game places its popups itself each time they open; the Buy dialog goes home
  local dlg = _G.AuctionHouseFrame and _G.AuctionHouseFrame.BuyDialog
  if dlg and dlg.goonHome and dlg.goonHome[1] then
    dlg:ClearAllPoints()
    dlg:SetPoint(unpack(dlg.goonHome))
  end
end

FI:On("PLAYER_LOGIN", function() P:SetupPopups() end)
FI:On("FI_AH_OPEN", function()
  P:SetupPopups()
  P:SetupModern()
end)
