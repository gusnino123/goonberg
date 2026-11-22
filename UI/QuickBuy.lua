-- Goonberg Terminal: the quick-buy key's buttons and its status line at the AH.
-- Macro (the same shape as a hand-made AH buy macro):
--   /click GoonBuy
--   /click GoonBuyRow LeftButton 1
--   /click GoonBuyBtn LeftButton 1
-- GoonBuy decides (FI.QuickBuy:Press). The two secure proxies then click the
-- cheapest row and the game's Buy button, but only when that press decided to buy;
-- otherwise they have nothing to click.
---@type string, GoonbergTerminal
local _, FI = ...
local Q = FI.QuickBuy

local function proxy(name)
  local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
  b:RegisterForClicks("AnyDown", "AnyUp")
  b:Hide()
  return b
end
local rowBtn = proxy("GoonBuyRow")
local buyBtn = proxy("GoonBuyBtn")

local function arm(row, btn)
  rowBtn:SetAttribute("type", row and "click" or nil)
  rowBtn:SetAttribute("clickbutton", row)
  buyBtn:SetAttribute("type", btn and "click" or nil)
  buyBtn:SetAttribute("clickbutton", btn)
end

-- the Buy button: a hand-made macro's proven target (AHBuyC) if you have one,
-- otherwise the game's Buy button where Goonberg expects it
local function buyTarget(fallback)
  local own = _G.AHBuyC
  local t = own and own.GetAttribute and own:GetAttribute("clickbutton")
  if type(t) == "table" then return t, true end
  return fallback, false
end

local main = CreateFrame("Button", "GoonBuy", UIParent)
main:RegisterForClicks("AnyDown", "AnyUp")
main:Hide()
-- one decision per press: a key press can reach us as both a down and an up click
local lastPress = -1
main:SetScript("OnClick", function()
  -- (secure buttons can't change in combat; the AH is never used in combat anyway)
  if InCombatLockdown() then return end
  local now = GetTime()
  if now == lastPress then return end
  lastPress = now
  arm(nil, nil) -- nothing to click unless this press buys
  local ok, step = pcall(Q.Press, Q)
  if not ok then return end
  if step == "buy" then
    local row, fallback = Q:Targets()
    local btn = buyTarget(fallback)
    if row and btn then
      arm(row, btn)
    else
      Q.last.step = "nobutton"
      FI:Fire("FI_QUICKBUY", "nobutton")
    end
  end
end)
-- disarm once the proxies have clicked, so nothing else can buy through them
buyBtn:HookScript("PostClick", function()
  if not InCombatLockdown() then C_Timer.After(0, function() arm(nil, nil) end) end
end)

-- /goon quickbuy debug: what a buy press would click
function Q:Debug()
  local row, fallback = self:Targets()
  local btn, own = buyTarget(fallback)
  local function name(f) return f and (f.GetDebugName and f:GetDebugName() or tostring(f)) or "not found" end
  FI:Print("Quick buy targets: row %s; Buy button %s%s.", name(row), name(btn), own and " (from your AHBuyC)" or "")
end

-- ---------------------------------------------------------------------------
-- Status line, under the Auction House window
-- ---------------------------------------------------------------------------
local status
local function statusText()
  local id = Q:CurrentItem()
  if not id then return nil end
  local cap = Q:Caps()[id]
  if not cap then return "no buy cap for this item (/goon buycap 1g50s)" end
  local last = Q.last
  local step = last and last.id == id and last.step
  local capText = "cap " .. FI.Money(cap)
  if step == "popup" or step == "buy" then return "buy ready: confirm in the popup (" .. capText .. ")" end
  if step == "nobutton" then return "couldn't find the game's Buy button" end
  if step == "norefresh" then return "couldn't refresh the list" end
  if Q.pending and Q.pending.id == id then return "waiting for results (" .. capText .. ")" end
  if Q.queued and Q.queued.id == id then return "refresh queued: sends the moment the AH allows (" .. capText .. ")" end
  local price = Q:Cheapest(id)
  local fresh = Q.freshAt[id] and GetTime() - Q.freshAt[id] <= Q.FRESH
  if price and fresh then
    if price <= cap then return ("cheapest %s, under your %s: press to buy"):format(FI.Money(price), capText) end
    return ("cheapest %s, over your %s: press to refresh"):format(FI.Money(price), capText)
  end
  return "press to refresh (" .. capText .. ")"
end

local function update()
  local ah = _G.AuctionHouseFrame
  if not ah then return end
  if not status then
    -- right side, under the window: the Buy / Sell / Auctions tabs hang off the left
    status = ah:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPRIGHT", ah, "BOTTOMRIGHT", -8, -6)
    status:SetJustifyH("RIGHT")
  end
  local text = statusText()
  if text then
    status:SetText("|cffffd100Goonberg quick buy:|r " .. text)
    status:Show()
  else
    status:Hide()
  end
end

FI:On("FI_QUICKBUY", function() FI:Debounce("quickbuyStatus", 0.05, update) end)
FI:On("FI_AH_OPEN", function() C_Timer.After(0.5, update) end)
-- a fresh list goes stale after a few seconds: keep the line honest while the AH is open
local tick = 0
CreateFrame("Frame"):SetScript("OnUpdate", function(_, dt)
  if not FI.ahOpen then return end
  tick = tick + dt
  if tick < 1 then return end
  tick = 0
  update()
end)
