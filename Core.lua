-- Goonberg Terminal: core (saved data, helpers, events, slash commands)
local ADDON, FI = ...
_G.GoonbergTerminal = FI

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
FI.version = (GetMeta and GetMeta(ADDON, "Version")) or "dev"

FI.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
FI.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

FI.colors = {
  gold   = { 0.91, 0.72, 0.29 },
  up     = { 0.25, 0.71, 0.55 },
  down   = { 0.94, 0.38, 0.23 },
  text   = { 0.90, 0.91, 0.93 },
  soft   = { 0.76, 0.79, 0.83 },
  muted  = { 0.55, 0.58, 0.64 },
  bg     = { 0.055, 0.067, 0.086 },
  side   = { 0.071, 0.086, 0.110 },
  panel  = { 0.082, 0.102, 0.129 },
  raised = { 0.110, 0.137, 0.176 },
  border = { 0.137, 0.165, 0.200 },
}
FI.hex = { gold = "ffe8b84a", up = "ff3fb68b", down = "fff0613a", muted = "ff8b95a3", text = "ffe6e9ee" }

-- ---------------------------------------------------------------------------
-- Events: a tiny dispatcher so every module can listen to game and own events
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if list then
    for i = 1, #list do list[i](event, ...) end
  end
end)

function FI:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- Our own events are all upper case and start with FI_
    if not event:find("^FI_") then pcall(eventFrame.RegisterEvent, eventFrame, event) end
  end
  table.insert(handlers[event], fn)
end

function FI:Fire(event, ...)
  local list = handlers[event]
  if list then
    for i = 1, #list do list[i](event, ...) end
  end
end

-- Runs fn once after `delay` seconds, however many times it is asked for meanwhile
local pending = {}
function FI:Pending(key) return pending[key] == true end
function FI:Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    fn()
  end)
end

-- ---------------------------------------------------------------------------
-- Printing and formatting
-- ---------------------------------------------------------------------------
function FI:Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  DEFAULT_CHAT_FRAME:AddMessage("|cffe8b84aGoonberg Terminal|r: " .. tostring(msg))
end

function FI.Money(copper, full)
  if not copper then return "-" end
  copper = math.floor(copper + 0.5)
  local neg = copper < 0
  if neg then copper = -copper end
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out
  if full then
    if g > 0 then out = ("%dg %02ds %02dc"):format(g, s, c)
    elseif s > 0 then out = ("%ds %02dc"):format(s, c)
    else out = ("%dc"):format(c) end
  else
    if g >= 1000 then out = ("%sg"):format(FI.Number(g))
    elseif g > 0 then out = ("%dg %02ds"):format(g, s)
    elseif s > 0 then out = ("%ds %02dc"):format(s, c)
    else out = ("%dc"):format(c) end
  end
  return neg and ("-" .. out) or out
end

function FI.Number(n)
  if not n then return "-" end
  local s = tostring(math.floor(n + 0.5))
  local k
  repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

function FI.Percent(v)
  if not v then return "-" end
  return ("%s%.1f%%"):format(v >= 0 and "+" or "", v)
end

function FI.ChangeColor(v)
  if not v then return FI.colors.muted end
  return v >= 0 and FI.colors.up or FI.colors.down
end

function FI.ColoredPercent(v)
  if not v then return "|cff8b95a3-|r" end
  return ("|c%s%s|r"):format(v >= 0 and FI.hex.up or FI.hex.down, FI.Percent(v))
end

function FI.Duration(sec)
  sec = math.max(0, math.floor(sec))
  if sec < 60 then return sec .. "s" end
  if sec < 3600 then return math.floor(sec / 60) .. " min" end
  if sec < 86400 then return ("%dh %dm"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
  return math.floor(sec / 86400) .. "d"
end

function FI.Ago(t)
  if not t or t == 0 then return "never" end
  local d = time() - t
  if d < 60 then return "just now" end
  return FI.Duration(d) .. " ago"
end

-- "3g50s", "3g 50s 20c", "3.5" (gold), "350s", "75c" -> copper
function FI.ParseMoney(text)
  if not text then return nil end
  text = text:lower():gsub("%s+", "")
  if text == "" then return nil end
  local plain = tonumber(text)
  if plain then return math.floor(plain * 10000 + 0.5) end
  local total, matched = 0, false
  for num, unit in text:gmatch("([%d%.]+)([gsc])") do
    local v = tonumber(num)
    if not v then return nil end
    matched = true
    if unit == "g" then total = total + v * 10000
    elseif unit == "s" then total = total + v * 100
    else total = total + v end
  end
  if not matched then return nil end
  -- Anything left over that isn't a number+unit pair means bad input
  if text:gsub("[%d%.]+[gsc]", "") ~= "" then return nil end
  return math.floor(total + 0.5)
end

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------
local pendingNames = {}

function FI:ItemName(itemID)
  local name = FI.GetItemInfo(itemID)
  if name then
    local realm = self:Realm()
    local it = realm and realm.items[itemID]
    if it and it.n ~= name then it.n = name end
    return name
  end
  local realm = self:Realm()
  local it = realm and realm.items[itemID]
  if it and it.n then return it.n end
  if not pendingNames[itemID] and Item and Item.CreateFromItemID then
    pendingNames[itemID] = true
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
      pendingNames[itemID] = nil
      FI:Fire("FI_ITEM_LOADED", itemID)
    end)
  end
  return "Item " .. itemID
end

function FI:ItemIcon(itemID)
  local _, _, _, _, icon = FI.GetItemInfoInstant(itemID)
  return icon or 134400 -- question mark
end

function FI:ItemLink(itemID)
  local _, link = FI.GetItemInfo(itemID)
  return link
end

function FI:ItemQualityColor(itemID)
  local _, _, quality = FI.GetItemInfo(itemID)
  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    local c = ITEM_QUALITY_COLORS[quality]
    return c.r, c.g, c.b
  end
  return unpack(FI.colors.text)
end

function FI:ItemIDFromLink(link)
  if not link then return nil end
  local id = link:match("|Hitem:(%d+)") or link:match("item:(%d+)")
  return id and tonumber(id)
end

-- Category used by the overview filters
local tradeGoods = { [5] = "Cloth", [6] = "Leather", [7] = "Ore & Bars", [9] = "Herbs", [12] = "Enchanting" }
function FI:Category(itemID)
  local _, _, _, _, _, classID, subID = FI.GetItemInfoInstant(itemID)
  if classID == 7 then return tradeGoods[subID] or "Trade Goods" end
  if classID == 0 then return "Consumables" end
  if classID == 2 or classID == 4 then return "Gear" end
  if classID == 9 then return "Recipes" end
  return "Other"
end
FI.categories = { "All", "Herbs", "Ore & Bars", "Cloth", "Leather", "Enchanting", "Trade Goods", "Consumables", "Gear", "Recipes", "Other" }

-- Accepts an item link, an item ID or (part of) a name the addon has seen
function FI:FindItem(text)
  if not text or text == "" then return nil end
  local id = self:ItemIDFromLink(text) or tonumber(text)
  if id then return id end
  local realm = self:Realm()
  local needle = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local prefix
  for itemID, it in pairs(realm.items) do
    local name = (FI.GetItemInfo(itemID)) or it.n
    if name then
      local lower = name:lower()
      if lower == needle then return itemID end
      if not prefix and lower:sub(1, #needle) == needle then prefix = itemID end
    end
  end
  return prefix
end

-- ---------------------------------------------------------------------------
-- Saved data
-- ---------------------------------------------------------------------------
local defaults = {
  settings = {
    autoScan = true,   -- scan when the AH opens (if Blizzard's limit allows)
    dock = true,       -- open the window beside the AH
    sound = true,
    flash = true,
    chatAlerts = true,
    tooltip = true,
  },
  realms = {},
  lastFullScan = 0,
  window = nil,
}

local function fill(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      fill(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function FI:Realm()
  if not self.db then return nil end
  if not self.realmKey then
    local faction = UnitFactionGroup("player") or "Neutral"
    self.realmKey = (GetRealmName() or "Unknown") .. " - " .. faction
  end
  local r = self.db.realms[self.realmKey]
  if not r then
    r = { items = {}, index = {}, watch = {}, lastScan = 0, scans = 0 }
    self.db.realms[self.realmKey] = r
  end
  r.items = r.items or {}
  r.index = r.index or {}
  r.watch = r.watch or {}
  return r
end

FI:On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  if type(GoonbergTerminalDB) ~= "table" then GoonbergTerminalDB = {} end
  fill(GoonbergTerminalDB, defaults)
  FI.db = GoonbergTerminalDB
  FI.settings = FI.db.settings
end)

FI:On("PLAYER_LOGIN", function()
  FI:Realm()
  FI:Fire("FI_READY")
end)

-- ---------------------------------------------------------------------------
-- Auction House open/close
-- ---------------------------------------------------------------------------
local function ahShown()
  FI.ahOpen = true
  FI:Fire("FI_AH_OPEN")
end
local function ahHidden()
  FI.ahOpen = false
  FI:Fire("FI_AH_CLOSED")
end
FI:On("AUCTION_HOUSE_SHOW", ahShown)
FI:On("AUCTION_HOUSE_CLOSED", ahHidden)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
local function onOff(v, current)
  if v == "on" then return true elseif v == "off" then return false end
  return not current
end

local help = {
  "/goon  - open or close the window",
  "/goon overview  |  /goon chart <item>  |  /goon pnl",
  "/goon deals  - listings under what they're worth  |  /goon deals alert 10 | alert on|off",
  "/goon2 (or /goon craft)  - crafting profit for your professions",
  "/goon scan  - full Auction House scan (AH must be open)",
  "/goon watch <item>  |  /goon unwatch <item>",
  "/goon alert <item> below|above <price>  (e.g. 3g50s)",
  "/goon alert <item> clear",
  "/goon post <item> [guild|party|raid|say]  - share a price",
  "/goon autoscan|dock|sound|tooltip on|off",
  "/goon minimap on|off|reset  - the button under the minimap",
  "/goon de <item>  - what it disenchants into and is worth  |  /goon de watch",
  "/goon sync  - guild sync status  |  /goon sync on|off|history|catchup",
  "/goon import  - pull price history from Auctionator (also automatic at login; /goon import off)",
  "/goon scale 0.9  |  /goon scale reset  - window size (or drag its corner)",
}

SLASH_GOONBERG1 = "/goon"
SLASH_GOONBERG2 = "/goonberg"
SlashCmdList.GOONBERG = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    FI.UI:Toggle()
  elseif cmd == "overview" then
    FI.UI:Show("overview")
  elseif cmd == "deals" then
    local arg = rest:lower()
    if arg == "alert on" or arg == "alert off" then
      FI.settings.dealAlerts = arg == "alert on"
      return FI:Print("Deal alerts are now %s.", arg:sub(7))
    end
    local gold = arg:match("^alert%s+([%d%.]+)")
    if gold then
      FI.settings.dealAlertGold = math.floor(tonumber(gold) * 10000)
      FI.settings.dealAlerts = true
      return FI:Print("Deal alerts fire when new deals add up to %s.", FI.Money(FI.settings.dealAlertGold))
    end
    FI.UI:Show("deals")
  elseif cmd == "craft" or cmd == "crafting" then
    FI.UI:Show("craft")
  elseif cmd == "pnl" then
    FI.UI:Show("pnl")
  elseif cmd == "chart" then
    local id = FI:FindItem(rest)
    FI.UI:ShowItem(id)
  elseif cmd == "scan" then
    FI.Scanner:Start(true)
  elseif cmd == "watch" or cmd == "unwatch" then
    local id = FI:FindItem(rest)
    if not id then return FI:Print("Couldn't find that item. Shift-click it into the command, or scan the AH first.") end
    if cmd == "watch" then FI.Alerts:Watch(id) else FI.Alerts:Unwatch(id) end
  elseif cmd == "alert" then
    local itemText, dir, priceText = rest:match("^(.-)%s+(below)%s+(.+)$")
    if not itemText then itemText, dir, priceText = rest:match("^(.-)%s+(above)%s+(.+)$") end
    if not itemText then itemText, dir = rest:match("^(.-)%s+(clear)$") end
    local id = itemText and FI:FindItem(itemText)
    if not id then return FI:Print("Usage: /goon alert <item> below|above <price>, or /goon alert <item> clear") end
    if dir == "clear" then
      FI.Alerts:SetAlert(id, "below", nil)
      FI.Alerts:SetAlert(id, "above", nil)
      return FI:Print("Alerts cleared for %s.", FI:ItemName(id))
    end
    local copper = FI.ParseMoney(priceText)
    if not copper then return FI:Print("Couldn't read the price \"%s\". Try 3g50s or 3.5.", priceText) end
    FI.Alerts:SetAlert(id, dir, copper)
  elseif cmd == "post" then
    local itemText, channel = rest:match("^(.-)%s+(%a+)$")
    local chan = channel and channel:upper()
    if not (chan == "GUILD" or chan == "PARTY" or chan == "RAID" or chan == "SAY") then
      itemText, chan = rest, nil
    end
    FI.Alerts:Post(FI:FindItem(itemText), chan)
  elseif cmd == "scale" then
    local v = tonumber(rest)
    if rest:lower() == "reset" then
      FI.UI:ResetSize()
      return FI:Print("Window size, scale and position reset.")
    end
    if not v or v < 0.5 or v > 1.5 then return FI:Print("Usage: /goon scale 0.5 to 1.5 (now %.2f), or /goon scale reset", FI.db.scale or 1) end
    FI.UI:SetScale(v)
    FI:Print("Window scale set to %.2f.", v)
  elseif cmd == "de" or cmd == "disenchant" then
    if rest:lower() == "watch" then
      for _, id in ipairs(FI.Disenchant:Materials()) do FI.Alerts:Watch(id) end
      return FI:Print("Watching every disenchant material.")
    end
    local id = FI:FindItem(rest)
    if not id then return FI:Print("Usage: /goon de <item>  (or /goon de watch)") end
    local v, complete, parts = FI.Disenchant:Value(id)
    if not parts then return FI:Print("%s can't be disenchanted.", FI:ItemName(id)) end
    FI:Print("%s disenchants for about %s%s:", FI:ItemLink(id) or FI:ItemName(id), FI.Money(v or 0), complete and "" or " (some materials not priced yet)")
    for _, p in ipairs(parts) do
      DEFAULT_CHAT_FRAME:AddMessage(("   %d%%  %s x%s  %s"):format(math.floor(p.chance * 100 + 0.5), FI:ItemName(p.id), p.qty, p.price and FI.Money(p.price * p.qty) or "no price"))
    end
  elseif cmd == "sync" then
    local arg = rest:lower()
    if arg == "on" or arg == "off" then
      FI.settings.guildSync = arg == "on"
      FI:Print("Guild sync is now %s.", arg)
    elseif arg == "history" then
      FI.Sync:RequestHistory(true)
    elseif arg == "catchup" then
      FI.Sync:RequestCatchup(FI:Realm().lastScan or (time() - 86400), true)
    else
      FI.Sync:Status()
    end
  elseif cmd == "import" then
    if rest:lower() == "off" or rest:lower() == "on" then
      FI.settings.importAuctionator = rest:lower() == "on"
      return FI:Print("Auctionator import at login is now %s.", rest:lower())
    end
    FI.Import:Run(true)
  elseif cmd == "minimap" then
    local arg = rest:lower()
    if arg == "reset" then
      FI.db.minimap = nil
      FI:SetMinimapButton(false); FI:SetMinimapButton(true)
      return FI:Print("Minimap button moved back under the minimap.")
    end
    FI:SetMinimapButton(onOff(arg, FI.settings.minimapButton))
    FI:Print("Minimap button is now %s.", FI.settings.minimapButton and "shown" or "hidden")
  elseif cmd == "autoscan" or cmd == "dock" or cmd == "sound" or cmd == "tooltip" then
    local key = cmd == "autoscan" and "autoScan" or cmd
    FI.settings[key] = onOff(rest:lower(), FI.settings[key])
    FI:Print("%s is now %s.", cmd, FI.settings[key] and "on" or "off")
  else
    FI:Print("Commands:")
    for _, line in ipairs(help) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
  end
end

SLASH_GOONBERGCRAFT1 = "/goon2"
SlashCmdList.GOONBERGCRAFT = function() FI.UI:Show("craft") end

function GoonbergTerminal_OnAddonCompartmentClick()
  FI.UI:Toggle()
end
