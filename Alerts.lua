-- Goonberg Terminal: watchlist, price alerts (toast, sound, chat) and sharing prices
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Alerts
local A = {}
FI.Alerts = A

function A:Watch(itemID)
  local realm = FI:Realm()
  if not realm.watch[itemID] then
    realm.watch[itemID] = { added = time() }
    FI:Print("Watching %s.", FI:ItemLink(itemID) or FI:ItemName(itemID))
    FI:Fire("FI_WATCH_CHANGED")
  end
end

function A:Unwatch(itemID)
  local realm = FI:Realm()
  if realm.watch[itemID] then
    realm.watch[itemID] = nil
    FI:Print("Stopped watching %s.", FI:ItemName(itemID))
    FI:Fire("FI_WATCH_CHANGED")
  end
end

function A:IsWatched(itemID)
  return FI:Realm().watch[itemID] ~= nil
end

-- Sorted list of watched item IDs (by name)
function A:List()
  local list = {}
  for itemID in pairs(FI:Realm().watch) do list[#list + 1] = itemID end
  table.sort(list, function(a, b) return FI:ItemName(a) < FI:ItemName(b) end)
  return list
end

-- dir: "below" or "above"; copper nil clears it
function A:SetAlert(itemID, dir, copper)
  local realm = FI:Realm()
  local w = realm.watch[itemID]
  if not w then
    if not copper then return end
    w = { added = time() }
    realm.watch[itemID] = w
  end
  w[dir] = copper
  w[dir .. "Fired"] = nil
  if copper then
    FI:Print("Alert set: %s %s %s.", FI:ItemName(itemID), dir, FI.Money(copper))
    -- check right away against the data we already have
    self:Check(itemID, w, realm.items[itemID], true)
  end
  FI:Fire("FI_WATCH_CHANGED")
end

-- ---------------------------------------------------------------------------
-- The toast
-- ---------------------------------------------------------------------------
local toast
local function buildToast()
  local C = FI.colors
  toast = CreateFrame("Frame", "GoonbergTerminalToast", UIParent, "BackdropTemplate")
  toast:SetSize(360, 64)
  toast:SetPoint("TOP", UIParent, "TOP", 0, -140)
  toast:SetFrameStrata("DIALOG")
  toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  toast:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.97)
  toast:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
  toast:Hide()

  toast.icon = toast:CreateTexture(nil, "ARTWORK")
  toast.icon:SetSize(40, 40)
  toast.icon:SetPoint("LEFT", 12, 0)

  toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, -2)
  toast.title:SetPoint("RIGHT", -12, 0)
  toast.title:SetJustifyH("LEFT")
  toast.title:SetTextColor(unpack(C.text))

  toast.body = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  toast.body:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -6)
  toast.body:SetPoint("RIGHT", -12, 0)
  toast.body:SetJustifyH("LEFT")

  toast:EnableMouse(true)
  toast:SetScript("OnMouseUp", function(self)
    self:Hide()
    if self.onClick then self.onClick()
    elseif self.itemID then FI.UI:ShowItem(self.itemID) end
  end)
  toast:SetScript("OnUpdate", function(self)
    local age = GetTime() - self.shown
    if age > 8 then self:Hide()
    elseif age > 7 then self:SetAlpha(8 - age)
    else self:SetAlpha(1) end
  end)
end

function A:Toast(itemID, title, body, onClick)
  if not toast then buildToast() end
  toast.itemID = itemID
  toast.onClick = onClick
  toast.icon:SetTexture(FI:ItemIcon(itemID))
  toast.title:SetText(title)
  toast.body:SetText(body)
  toast.shown = GetTime()
  toast:SetAlpha(1)
  toast:Show()
  if FI.settings.sound and PlaySound then
    PlaySound((SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
  if FI.settings.flash then A:Flash() end
end

-- A gold glow around the screen edges that fades out over a second
local flash
function A:Flash()
  if not flash then
    flash = CreateFrame("Frame", nil, UIParent)
    flash:SetAllPoints(UIParent)
    flash:SetFrameStrata("FULLSCREEN_DIALOG")
    flash:EnableMouse(false)
    local g = FI.colors.gold
    local function edge(p1, p2, w, h)
      local t = flash:CreateTexture(nil, "OVERLAY")
      t:SetColorTexture(g[1], g[2], g[3], 0.55)
      t:SetPoint(p1)
      t:SetPoint(p2)
      if w then t:SetWidth(w) end
      if h then t:SetHeight(h) end
    end
    edge("TOPLEFT", "TOPRIGHT", nil, 6)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 6)
    edge("TOPLEFT", "BOTTOMLEFT", 6, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", 6, nil)
    flash:SetScript("OnUpdate", function(self)
      local a = 1 - (GetTime() - self.start)
      if a <= 0 then self:Hide() else self:SetAlpha(a) end
    end)
  end
  flash.start = GetTime()
  flash:SetAlpha(1)
  flash:Show()
end

-- ---------------------------------------------------------------------------
-- Checking alerts. Each alert fires once when the price crosses, and re-arms
-- when the price moves back.
-- ---------------------------------------------------------------------------
function A:Check(itemID, w, it, quiet)
  if not it or not it.min then return end
  local price = it.min
  local name = FI:ItemName(itemID)
  local fired = false
  for _, dir in ipairs({ "below", "above" }) do
    local target = w[dir]
    if target then
      local hit = (dir == "below" and price <= target) or (dir == "above" and price >= target)
      if hit and not w[dir .. "Fired"] then
        w[dir .. "Fired"] = true
        fired = true
        if not quiet then
          local s = FI.History.Stats(it, time())
          local title = ("%s is %s your alert"):format(name, dir == "below" and "below" or "above")
          local body = ("|c%s%s|r  -  alert at %s  -  24h %s"):format(FI.hex.gold, FI.Coins(price), FI.Coins(target), FI.ColoredPercent(s.c24))
          self:Toast(itemID, title, body)
          if FI.settings.chatAlerts then
            FI:Print("%s %s %s (lowest now %s).", FI:ItemLink(itemID) or name, dir == "below" and "dropped below" or "rose above", FI.Money(target), FI.Money(price))
          end
        end
      elseif not hit then
        w[dir .. "Fired"] = nil
      end
    end
  end
  return fired
end

FI:On("FI_SCAN_DONE", function()
  local realm = FI:Realm()
  for itemID, w in pairs(realm.watch) do
    A:Check(itemID, w, realm.items[itemID], false)
  end
end)

-- ---------------------------------------------------------------------------
-- /goon post: one line to chat. Every share puts the addon's name in front of
-- other players.
-- ---------------------------------------------------------------------------
function A:Post(itemID, channel)
  if not itemID then return FI:Print("Usage: /goon post <item> [guild|party|raid|say]") end
  local it = FI:Realm().items[itemID]
  if not it or not it.mkt then return FI:Print("No prices for %s yet. Scan the AH first.", FI:ItemName(itemID)) end
  local s = FI.History.Stats(it, time())
  local parts = { ("[Goonberg] %s %s"):format(FI:ItemLink(itemID) or FI:ItemName(itemID), FI.Money(it.mkt)) }
  if s.c7 then parts[#parts + 1] = ("%s this week"):format(FI.Percent(s.c7)) end
  if it.d and it.d[1] then
    local wallP, wallQ = it.d[1], it.d[2]
    for i = 1, #it.d, 2 do if it.d[i + 1] > wallQ then wallP, wallQ = it.d[i], it.d[i + 1] end end
    parts[#parts + 1] = ("wall of %d at %s"):format(wallQ, FI.Money(wallP))
  end
  local msg = table.concat(parts, " - ")
  if not channel then channel = IsInGuild() and "GUILD" or "SAY" end
  SendChatMessage(msg, channel)
end
