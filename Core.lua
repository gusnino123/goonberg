-- Goonberg Terminal: core (saved data, helpers, events, slash commands)

-- The ---@ comments are type annotations for the Lua language server (editor
-- autocomplete and `lua-language-server --check .`). The game ignores them.

local ADDON, ns = ...
---The addon's shared table: `FI` in every file. Each module adds itself here.
---@class GoonbergTerminal
---@field db GT.DB                 saved data (GoonbergTerminalDB), set at ADDON_LOADED
---@field settings GT.Settings     FI.db.settings
---@field realmKey string?         "Realm - Faction"
---@field ahOpen boolean?
---@field SetMinimapButton fun(self: GoonbergTerminal, show: boolean)  UI/Minimap.lua
---@field NoDisenchant table<integer, true>  gear that can't be disenchanted (Disenchant/NoDE.lua, generated)
---@field LootData table           dungeon loot tables (Loot/Data.lua, generated)
---@field Alerts GT.Alerts
---@field Crafting GT.Crafting
---@field Deals GT.Deals
---@field Disenchant GT.Disenchant
---@field History GT.History
---@field Import GT.Import
---@field Ledger GT.Ledger
---@field LedgerTab GT.LedgerTab
---@field Loot GT.Loot
---@field Partner GT.Partner
---@field Scanner GT.Scanner
---@field Seed GT.Seed
---@field Sync GT.Sync
---@field UI GT.UI
---@field Widgets GT.Widgets
---@field ChartView GT.ChartView
---@field ChartTab GT.ChartTab
---@field CraftTab GT.CraftTab
---@field DealsTab GT.DealsTab
---@field LootTab GT.LootTab
---@field OverviewTab GT.OverviewTab
---@field PnLTab GT.PnLTab
---@field PositionsView GT.PositionsView
local FI = ns
_G.GoonbergTerminal = FI

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
FI.version = (GetMeta and GetMeta(ADDON, "Version")) or "dev"

FI.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
FI.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Text colors: the game's gold for headings, labels and what's selected; a warm off-white
-- for values (pure white on black glares over a long session); greys for the rest. Green
-- and red are a touch softer than pure, so a column of them stays easy on the eyes.
-- See-through blacks for panels, so the window's background shows through.
-- A 4th value is the color's alpha.
FI.colors = {
  gold   = { 1.00, 0.82, 0.00 }, -- the game's gold (NORMAL_FONT_COLOR)
  up     = { 0.40, 0.78, 0.38 },
  down   = { 1.00, 0.45, 0.40 },
  text   = { 0.90, 0.88, 0.82 },
  soft   = { 0.74, 0.72, 0.68 },
  muted  = { 0.62, 0.60, 0.56 },
  bg     = { 0.00, 0.00, 0.00, 0.60 },
  side   = { 0.00, 0.00, 0.00, 0.35 },
  panel  = { 0.00, 0.00, 0.00, 0.45 },
  raised = { 0.17, 0.17, 0.17 },
  border = { 0.29, 0.27, 0.24 },
}
FI.hex = { gold = "ffffd100", up = "ff66c761", down = "ffff7366", muted = "ff9e998f", soft = "ffbdb8ad", text = "ffe6e0d1" }

-- ---------------------------------------------------------------------------
-- Events: a tiny dispatcher so every module can listen to game and own events
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if list then
    -- one broken handler must not stop the others (or leave a scan half done)
    for i = 1, #list do
      local ok, err = pcall(list[i], event, ...)
      if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) else print("Goonberg Terminal error: " .. tostring(err)) end
      end
    end
  end
end)

---Listens to a game event, or one of our own (FI_...).
---@param event string
---@param fn fun(event: string, ...)
function FI:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- Our own events are all upper case and start with FI_
    if not event:find("^FI_") then pcall(eventFrame.RegisterEvent, eventFrame, event) end
  end
  table.insert(handlers[event], fn)
end

---@param event string  one of our own events (FI_...)
function FI:Fire(event, ...)
  local list = handlers[event]
  if list then
    -- one broken handler must not stop the others (or leave a scan half done)
    for i = 1, #list do
      local ok, err = pcall(list[i], event, ...)
      if not ok then
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) else print("Goonberg Terminal error: " .. tostring(err)) end
      end
    end
  end
end

-- Runs fn once after `delay` seconds, however many times it is asked for meanwhile
local pending = {}
function FI:Pending(key) return pending[key] == true end
---@param key string
---@param delay number  seconds
---@param fn fun()
function FI:Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function()
    pending[key] = nil
    fn()
  end)
end

-- Background work (reading a scan, saving it, the overview, deals, imports) runs in
-- slices over many frames. Each job has its own limit per frame, and together they
-- share this one, so several running at once (after a scan) still cost one slice.
-- GetTime() is the same all frame long, which tells frames apart.
local FRAME_MS = 10
local frameT, frameEnd = nil, 0
---When a background job should stop for this frame (a debugprofilestop() value):
---its own `ms` from now, or sooner if other jobs already used the frame's share.
---@param ms number
---@return number
function FI:WorkUntil(ms)
  local now = debugprofilestop()
  local t = GetTime()
  if t ~= frameT then frameT, frameEnd = t, now + FRAME_MS end
  return math.min(now + ms, frameEnd)
end

-- ---------------------------------------------------------------------------
-- Printing and formatting
-- ---------------------------------------------------------------------------
function FI:Print(msg, ...)
  if select("#", ...) > 0 then msg = msg:format(...) end
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Goonberg Terminal|r: " .. tostring(msg))
end

---"3g 50s" from copper; `full` always shows every unit ("3g 50s 00c").
---@param copper number?
---@param full boolean?
---@return string
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
    -- drop units that add nothing: "9g", "5s" rather than "9g 00s", "5s 00c"
    if g >= 1000 then out = ("%sg"):format(FI.Number(g))
    elseif g > 0 then out = s > 0 and ("%dg %02ds"):format(g, s) or ("%dg"):format(g)
    elseif s > 0 then out = c > 0 and ("%ds %02dc"):format(s, c) or ("%ds"):format(s)
    else out = ("%dc"):format(c) end
  end
  return neg and ("-" .. out) or out
end

-- The same amount with coin icons, the way the bags and the AH show money
-- ("34 [gold] 20 [silver] 49 [copper]", no zero padding). For the screen only: chat
-- messages sent to other players and edit boxes keep FI.Money's letters. The sale
-- line Goonberg shows in your own chat window uses the icons.
local function coinIcon(name) return "|TInterface\\MoneyFrame\\UI-" .. name .. "Icon:0:0:2:0|t" end
FI.COIN = { g = coinIcon("Gold"), s = coinIcon("Silver"), c = coinIcon("Copper") }
---@param copper number?
---@param full boolean?
---@return string
function FI.Coins(copper, full)
  local out = FI.Money(copper, full)
  if out == "-" then return out end
  out = out:gsub(" 0(%d)", " %1")
  return (out:gsub("(%d)([gsc])", function(d, u) return d .. FI.COIN[u] end))
end

---@param n number?
---@return string
function FI.Number(n)
  if not n then return "-" end
  local s = tostring(math.floor(n + 0.5))
  local k
  repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
  return s
end

---@param v number?  already in percent (12.5 = 12.5%)
---@return string
function FI.Percent(v)
  if not v then return "-" end
  return ("%s%.1f%%"):format(v >= 0 and "+" or "", v)
end

function FI.ChangeColor(v)
  if not v then return FI.colors.muted end
  return v >= 0 and FI.colors.up or FI.colors.down
end

function FI.ColoredPercent(v)
  if not v then return "|c" .. FI.hex.muted .. "-|r" end
  return ("|c%s%s|r"):format(v >= 0 and FI.hex.up or FI.hex.down, FI.Percent(v))
end

---@param sec number
---@return string
function FI.Duration(sec)
  sec = math.max(0, math.floor(sec))
  if sec < 60 then return sec .. "s" end
  if sec < 3600 then return math.floor(sec / 60) .. " min" end
  if sec < 86400 then return ("%dh %dm"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
  return math.floor(sec / 86400) .. "d"
end

---@param t integer?  a time() value
---@return string
function FI.Ago(t)
  if not t or t == 0 then return "never" end
  local d = time() - t
  if d < 60 then return "just now" end
  return FI.Duration(d) .. " ago"
end

-- "3g50s", "3g 50s 20c", "3.5" (gold), "350s", "75c" -> copper
---@param text string?
---@return integer? copper  nil when the text isn't a price
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

-- While the game is still loading an item it returns "Item <id>" and true; anything
-- that keeps the name should look it up again once FI_ITEM_LOADED fires.
---@param itemID integer
---@return string name
---@return boolean? loading
function FI:ItemName(itemID)
  local name = FI.GetItemInfo(itemID)
  if name then
    local realm = self:Realm()
    local it = realm and realm.items[itemID]
    if it and it.n ~= name then
      it.n = name
      if FI.Ledger then FI.Ledger:NoteName(name, itemID) end
    end
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
  return "Item " .. itemID, true
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

---@param link string?
---@return integer?
function FI:ItemIDFromLink(link)
  if not link then return nil end
  local id = link:match("|Hitem:(%d+)") or link:match("item:(%d+)")
  return id and tonumber(id)
end

-- Category used by the overview filters
local tradeGoods = { [5] = "Cloth", [6] = "Leather", [7] = "Ore & Bars", [9] = "Herbs", [12] = "Enchanting" }
---@param itemID integer
---@return string
function FI:Category(itemID)
  local _, _, _, _, _, classID, subID = FI.GetItemInfoInstant(itemID)
  if classID == 7 then return tradeGoods[subID] or "Trade Goods" end
  if classID == 0 then return "Consumables" end
  if classID == 2 or classID == 4 then return "Gear" end
  if classID == 9 then return "Recipes" end
  if classID == 6 then return "Ammo" end -- arrows and bullets
  return "Other"
end
FI.categories = { "All", "Herbs", "Ore & Bars", "Cloth", "Leather", "Enchanting", "Trade Goods", "Consumables", "Gear", "Recipes", "Ammo", "Other" }

-- Accepts an item link, an item ID or (part of) a name the addon has seen
---@param text string?
---@return integer? itemID
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

---GoonbergTerminalDB, shared by every character on the account.
---@class GT.DB
---@field settings GT.Settings
---@field newestVersion string?   Sync.lua: the newest Goonberg version a guildmate runs
---@field realms table<string, GT.Realm>   by "Realm - Faction"
---@field lastFullScan integer
---@field window {point: string, relPoint: string, x: number, y: number}?
---@field size {w: integer, h: integer}?
---@field scale number?
---@field minimap {x: integer, y: integer}?
---@field vendor table<integer, integer>?    what an NPC charges for one, in copper
---@field deLearned table<integer, boolean>? found out in game: true = can be disenchanted, false = can't
---@field deYields table<string, {n: integer, out: table<integer, {h: integer, q: integer}>}>?  your disenchants by table row (GT.DEBand.key): n done, and per material how often it came (h) and how many in all (q)
---@field loot table?                        Loot.lua
---@field importSeen table<string, integer>   Import.lua: newest Auctionator day imported per item (created by the first import)
---@field lastImport integer?
---@field lastScanRequest integer?
---@field indexVersion integer?

---@class GT.Settings
---@field autoScan boolean
---@field dock boolean
---@field sound boolean
---@field flash boolean
---@field chatAlerts boolean
---@field tooltip boolean
---@field tooltipLines table<string, boolean>   item tooltip lines by FI.TOOLTIP_LINES key; false hides one
---@field buyMinQty number   the smallest listing the quick-buy key takes (/goon quant); 1 takes any
---@field guildSync boolean?
---@field importAuctionator boolean?
---@field minimapButton boolean?
---@field dealAlerts boolean?
---@field guildDealAlerts boolean? pop-ups after a guildmate's scan too (off by default)
---@field dealAlertGold integer?   copper
---@field rareAlerts boolean?
---@field rarePct number?          0.20 = 20% under the usual price
---@field rareMinGold integer?     copper
---@field rareMinDays integer?
---@field market string?           ruleset picked with /goon market; nil = from the realm name
---@field marketHint boolean?
---@field ownMats "free"|"market"|nil  how the P&L values your own materials
---@field pnlHideOld boolean?
---@field pnlMode string?

---One realm and faction's market.
---@class GT.Realm
---@field items table<integer, GT.Item>
---@field index number[]                Goonberg Index: flat time, level pairs
---@field watch table<integer, GT.Watch>
---@field lastScan integer
---@field scans integer
---@field scanDays table<integer, true>? days (time() / 86400) that anything was scanned
---@field indexAdds integer?
---@field lastOnline integer?
---@field liveScan integer?            the newest scan with listings (yours or a guildmate's), not a catch-up
---@field lastShared {from: string, t: integer, items: integer}?  the latest guildmate scan
---@field syncPeers table<string, integer>?  Sync.lua: guildmates running Goonberg, when last heard from
---@field ledger table?                 Ledger.lua
---@field partner table?                Partner.lua: per character, the linked guildmate and their trades
---@field recipes table?                Crafting.lua, per character
---@field marketBuilt integer?          Seed.lua
---@field seedBuilt integer?

---A watched item. Alert levels are in copper; nil means no alert that way.
---@class GT.Watch
---@field added integer
---@field below integer?
---@field above integer?
---@field belowFired boolean?
---@field aboveFired boolean?

local defaults = {
  settings = {
    autoScan = true,   -- scan when the AH opens (if Blizzard's limit allows)
    dock = true,       -- open the window beside the AH
    sound = true,
    flash = true,
    chatAlerts = true,
    tooltip = true,
    -- which lines the item tooltip shows (Options in the window); see FI.TOOLTIP_LINES
    tooltipLines = { vendor = true, vendorEach = true, market = true, marketEach = true, de = true, cap = true, qty = true },
    -- the smallest listing the quick-buy key takes (/goon quant 20); 1 takes any
    buyMinQty = 1,
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

---This realm and faction's data (nil only before the addon has loaded).
---@return GT.Realm
-- ---------------------------------------------------------------------------
-- Markets. Your faction's auction house and the neutral one (Booty Bay, Gadgetzan,
-- Everlook) are separate markets with their own prices, so each keeps its own
-- prices and scans: "Realm - Horde" and "Realm - Neutral AH". Your own things
-- (P&L, recipes, watchlist, leaderboard, guildmates) live with your faction's
-- market and are the same whichever market you look at.
-- FI.market is the market the tabs show ("home" or "neutral").
-- ---------------------------------------------------------------------------
FI.market = "home"
local PERSONAL = { ledger = true, recipes = true, watch = true, board = true, syncPeers = true, lastOnline = true, bank = true }

local function newMarket()
  return { items = {}, index = {}, watch = {}, lastScan = 0, scans = 0 }
end

---This realm's market: "home" (your faction's AH) or "neutral".
---@param which ("home"|"neutral")?
---@return GT.Realm
function FI:Market(which)
  ---@diagnostic disable-next-line: return-type-mismatch
  if not self.db then return nil end
  if not self.realmKey then
    local faction = UnitFactionGroup("player") or "Neutral"
    self.realmKey = (GetRealmName() or "Unknown") .. " - " .. faction
    self.neutralKey = (GetRealmName() or "Unknown") .. " - Neutral AH"
  end
  local home = self.db.realms[self.realmKey]
  if not home then
    home = newMarket()
    self.db.realms[self.realmKey] = home
  end
  home.items = home.items or {}
  home.index = home.index or {}
  home.watch = home.watch or {}
  if which ~= "neutral" then return home end
  local n = self.db.realms[self.neutralKey]
  if not n then
    n = newMarket()
    n.watch = nil
    self.db.realms[self.neutralKey] = n
  end
  n.items = n.items or {}
  n.index = n.index or {}
  -- your own things come from (and go to) your faction's market
  if getmetatable(n) == nil then
    setmetatable(n, {
      __index = function(_, k) if PERSONAL[k] then return home[k] end end,
      __newindex = function(t, k, v) if PERSONAL[k] then home[k] = v else rawset(t, k, v) end end,
    })
  end
  return n
end

---The market the tabs are showing (a scan in progress uses its own, see Scanner.lua).
---@return GT.Realm
function FI:Realm()
  return self:Market(self.marketOverride or self.market)
end

-- Show the other market. Caches that depend on prices are dropped and the open tab
-- redraws (FI_MARKET_CHANGED).
function FI:SetMarket(which)
  which = which == "neutral" and "neutral" or "home"
  if which == self.market then return end
  self.market = which
  self:Fire("FI_MARKET_CHANGED", which)
end

function FI:MarketName(which)
  which = which or self.market
  if which == "neutral" then return "Neutral AH" end
  local f = UnitFactionGroup("player")
  return (f == "Horde" or f == "Alliance") and (f .. " AH") or "Your AH"
end

-- Is the auction house that's open the neutral one? The goblin auctioneers of
-- Booty Bay, Gadgetzan and Everlook belong to no faction; the zones say it too.
local NEUTRAL_ZONES = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn, Tanaris, Winterspring
function FI:AtNeutralAH()
  if UnitExists and UnitExists("npc") then
    -- faction auctioneers are Alliance or Horde; the goblins are neither
    local f = UnitFactionGroup("npc")
    return f ~= "Alliance" and f ~= "Horde"
  end
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  return map ~= nil and NEUTRAL_ZONES[map] == true
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
  -- at Booty Bay (and co.) the tabs show the neutral market while you're there
  FI.ahMarket = FI:AtNeutralAH() and "neutral" or "home"
  FI.marketBeforeAH = FI.market
  FI:SetMarket(FI.ahMarket)
  FI:Fire("FI_AH_OPEN")
end
local function ahHidden()
  FI.ahOpen = false
  if FI.marketBeforeAH and FI.market == FI.ahMarket then FI:SetMarket(FI.marketBeforeAH) end
  FI.marketBeforeAH = nil
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
  "/goon rare  - rare finds  |  /goon rare 30 (percent)  |  rare min 10 (gold)  |  rare days 4  |  rare on|off",
  "/goon2 (or /goon craft)  - crafting profit for your professions",
  "/goon scan  - full Auction House scan (AH must be open)",
  "/goon watch <item>  |  /goon unwatch <item>",
  "/goon alert <item> below|above <price>  (e.g. 3g50s)",
  "/goon alert <item> clear",
  "/goon post <item> [guild|party|raid|say]  - share a price",
  "/goon loot  - dungeon drops worth selling: where they drop, chance and value",
  "/goon market  - which market's daily Blizzard prices you get  |  /goon market pvp|normal|rp|rppvp|auto",
  "/goon autoscan|dock|sound|tooltip on|off",
  "/goon options  - what Goonberg adds to item tooltips, line by line (also the Options button in the window)",
  "/goon minimap on|off|reset  - the button under the minimap",
  "/goon bank  - your bank at market  |  bank on|off|reset (the panel on the bank window; Alt + drag moves it)",
  "/goon bags  - your bags at market  |  bags on|off|reset (the panel beside your backpack; Alt + drag moves it)",
  "/goon de <item>  - what it disenchants into and is worth  |  /goon de watch",
  "/goon sync  - guild sync status  |  /goon sync on|off|history|catchup|scan",
  "/goon partner <guildmate>  - link ledgers: you both see each other's AH purchases and sales (/goon ledger)  |  partner accept|decline|unlink|sync|split 50|only <item>|pause|resume|paid 500g|got 500g|payments",
  "/goon sales on|off  - when one of your auctions sells, the game's chat line says how many and for how much",
  "/goon buycap 1g50s | off  - quick-buy cap for the item open at the AH (/goon quickbuy for the macro)",
  "/goon quantity 20 | 1  (or /goon quant)  - quick buy skips listings smaller than that (1 takes any size)",
  "/goon sell <item> <price each> [x20] [short|medium|long]  - post it at the AH in one press (put it in a macro)",
  "/goon buypopup move  - drag a box to where the AH Buy popup should open (reset puts it back)",
  "/goon import  - pull price history from Auctionator (also automatic at login; /goon import off)",
  "/goon scale 0.9  |  /goon scale reset  - window size (or drag its corner)",
}

SLASH_GOONBERG1 = "/goon"
SLASH_GOONBERG2 = "/goonberg"
-- /goon price: every source behind an item's price, so a wrong number can be traced
function FI:ExplainPrice(id, forgetVendor)
  local it = self:Realm().items[id]
  local now = time()
  local function ago(t)
    if not t then return "never" end
    local a = now - t
    if a < 3600 then return math.floor(a / 60) .. " min ago" end
    if a < 86400 then return math.floor(a / 3600) .. " h ago" end
    return math.floor(a / 86400) .. " d ago"
  end
  self:Print("Price of %s (item %d):", self:ItemLink(id) or self:ItemName(id) or "?", id)
  if forgetVendor and self.db.vendor and self.db.vendor[id] then
    self.db.vendor[id] = nil
    self:Print("  Vendor price forgotten.")
    self:Fire("FI_DATA_MERGED", "vendor")
  end
  if not it then
    self:Print("  Never seen on the AH.")
  else
    local src = self.Crafting.PriceSource and self.Crafting.PriceSource(it) or "?"
    self:Print("  Current market price: %s  (from %s, %s)", self.Money(it.mkt or 0),
      src == "scan" and "your scan" or src == "guild" and "a guildmate's scan" or (src .. ", the lowest listing it saw that day"),
      ago(math.max(it.seen or 0, it.imported or 0)))
    if it.seen then
      self:Print("  Last seen listed: %s  ·  %s listed%s", ago(it.seen), self.Number(it.qty or 0),
        it.min and ("  ·  lowest " .. self.Money(it.min)) or "")
    end
    if it.d and it.dt and #it.d >= 2 then
      local lv = {}
      for i = 1, math.min(#it.d, 8), 2 do lv[#lv + 1] = ("%s x%d"):format(self.Money(it.d[i]), it.d[i + 1]) end
      self:Print("  Cheapest listings (%s): %s", ago(it.dt), table.concat(lv, ", "))
    end
    local h = it.h or {}
    local pts = {}
    for i = #h - 3, math.max(1, #h - 4 * 4 + 1), -4 do
      if h[i] then pts[#pts + 1] = ("%s %s"):format(date("%b %d %H:%M", h[i]), h[i + 1] > 0 and self.Money(h[i + 1]) or "none listed") end
    end
    if #pts > 0 then self:Print("  History (newest first): %s", table.concat(pts, "  ·  ")) end
  end
  local vendor = self.db.vendor and self.db.vendor[id]
  if vendor then
    self:Print("  Vendor price recorded: %s  (|cffe8b84acrafting uses it when it's cheaper than the AH|r; wrong? /goon price [item] forget vendor)", self.Money(vendor))
  end
  local p, from, _, how = self.Crafting:ReagentPrice(id, 1)
  local sell = self.Crafting:SellPrice(id)
  self:Print("  Crafting uses: buying %s (%s)  ·  selling %s", p and self.Money(p) or "no price",
    from == "vendor" and "vendor" or (how or "-"), sell and self.Money(sell) or "no price")
end

SlashCmdList.GOONBERG = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    FI.UI:Toggle()
  elseif cmd == "overview" then
    FI.UI:Show("overview")
  elseif cmd == "rare" then
    local arg = rest:lower()
    local st = FI.settings
    if arg == "off" or arg == "on" then
      st.rareAlerts = arg == "on"
      return FI:Print("Rare find pop-ups are now %s.", arg)
    end
    local pct = arg:match("^(%d+)%%?$")
    local gold = arg:match("^min%s+([%d%.]+)")
    local days = arg:match("^days%s+(%d+)")
    if pct then st.rarePct = math.max(5, math.min(90, tonumber(pct))) / 100 end
    if gold then st.rareMinGold = math.floor(tonumber(gold) * 10000) end
    if days then st.rareMinDays = math.max(2, tonumber(days)) end
    local p, g, d = FI.Deals:RareSettings()
    FI:Print("Rare finds: at least %d%% under the usual price and under its cheapest-typical price, worth %s+, seen on %d+ days. Pop-ups %s.",
      math.floor(p * 100 + 0.5), FI.Money(g), d, st.rareAlerts == false and "off" or "on")
    if not (pct or gold or days) then FI.DealsTab.kind = "Rare"; FI.UI:Show("deals") end
  elseif cmd == "loot" then
    FI.UI:Show("loot")
  elseif cmd == "deals" then
    local arg = rest:lower()
    if arg == "alert on" or arg == "alert off" then
      FI.settings.dealAlerts = arg == "alert on"
      return FI:Print("Deal alerts are now %s.", arg:sub(7))
    end
    if arg == "guildalerts on" or arg == "guildalerts off" then
      FI.settings.guildDealAlerts = arg == "guildalerts on" or nil
      return FI:Print("Deal pop-ups after a guildmate's scan are now %s. (Your own scans always %s.)",
        arg:sub(13), FI.settings.dealAlerts == false and "stay quiet: deal alerts are off" or "pop up")
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
  elseif cmd == "ledger" then
    FI.UI:Show("ledger")
  elseif cmd == "partner" or cmd == "link" then
    -- a shared ledger with one guildmate: /goon partner <name> | accept | decline | unlink | sync | split 50
    FI.Partner:Command(rest)
  elseif cmd == "chart" then
    local id = FI:FindItem(rest)
    FI.UI:ShowItem(id)
  elseif cmd == "scan" then
    FI.Scanner:Start(true)
  elseif cmd == "watch" or cmd == "unwatch" then
    local id = FI:FindItem(rest)
    if not id then return FI:Print("Couldn't find that item. Shift-click it into the command, or scan the AH first.") end
    if cmd == "watch" then FI.Alerts:Watch(id) else FI.Alerts:Unwatch(id) end
  elseif cmd == "bags" then
    -- the bags worth panel beside the game's backpack
    local arg = rest:lower()
    if arg == "on" or arg == "off" then
      FI.settings.bagValue = arg == "on" or false
    elseif arg == "reset" then
      FI.settings.bagValuePos = nil
    else
      return FI:Print("Your bags: %s at market (%s).", FI.Money(FI.Ledger:BagValue()), FI:MarketName())
    end
    if FI.BagValue then FI.BagValue:Refresh() end
    return FI:Print(arg == "reset" and "The bags worth panel is back beside your backpack."
      or ("The bags worth panel beside your backpack is now %s."):format(arg))
  elseif cmd == "bank" then
    -- what's in your bank (as of your last visit) at market prices
    if rest:lower() == "off" or rest:lower() == "on" then
      FI.settings.bankValue = rest:lower() == "on" or false
      if FI.settings.bankValue == false and FI.BankValue then FI.BankValue:Hide() end
      return FI:Print("The bank worth panel on the bank window is now %s.", rest:lower())
    end
    if rest:lower() == "reset" then
      FI.settings.bankValuePos = nil
      if FI.BankValue and FI.BankValue.frame and FI.BankValue.frame:IsShown() then FI.BankValue:Place() end
      return FI:Print("The bank worth panel is back under the bank window.")
    end
    local L = FI.Ledger
    local total, list, t = L:BankValue()
    if not total then return FI:Print("Open your bank at a banker once and it's counted from then on.") end
    FI:Print("Your bank: %s at market (%s), as of %s.", FI.Money(total), FI:MarketName(), FI.Ago and FI.Ago(t) or date("%b %d %H:%M", t))
    for i = 1, math.min(10, #list) do
      local e = list[i]
      FI:Print("  %s%s  %s", e.n > 1 and (e.n .. "x ") or "", FI:ItemLink(e.id) or FI:ItemName(e.id) or e.id, FI.Money(e.value))
    end
    local banks = L:Banks()
    if #banks > 1 then
      local sum = 0
      for _, b in ipairs(banks) do sum = sum + b.total end
      FI:Print("All your banks on this realm: %s (%d characters).", FI.Money(sum), #banks)
    end
  elseif cmd == "share" then
    -- the guild leaderboard: /goon share on|off
    local arg = rest:lower()
    if arg == "on" or arg == "off" then
      FI.Sync:SetSharing(arg == "on")
      FI:Print(arg == "on" and "You're on your guild's leaderboard: guildmates see your P&L totals (today, 7 and 30 days), nothing else."
        or "Stopped sharing: your row is gone from your guild's leaderboard.")
    else
      FI:Print("Leaderboard sharing is %s. /goon share on|off  (P&L tab > Leaderboard)", FI.Sync:Sharing() and "on" or "off")
    end
  elseif cmd == "price" then
    -- where an item's price comes from: /goon price [item]  (add "forget vendor" to drop a vendor price)
    local forget = rest:lower():match("%s*forget vendor%s*$")
    if forget then rest = rest:gsub("%s*[Ff][Oo][Rr][Gg][Ee][Tt] [Vv][Ee][Nn][Dd][Oo][Rr]%s*$", "") end
    local id = FI:FindItem(rest)
    if not id then return FI:Print("Usage: /goon price [item]  (shift-click the item in)") end
    FI:ExplainPrice(id, forget)
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
    local v, complete, parts = FI.Disenchant:Value(id, FI.Disenchant.LAST_KNOWN)
    if not parts then return FI:Print("%s can't be disenchanted.", FI:ItemName(id)) end
    FI:Print("%s disenchants for about %s%s:", FI:ItemLink(id) or FI:ItemName(id), FI.Money(v or 0), complete and "" or " (some materials not priced yet)")
    for _, p in ipairs(parts) do
      local pct = p.chance < 0.01 and ("%.1f"):format(p.chance * 100) or tostring(math.floor(p.chance * 100 + 0.5))
      local qty = p.qty % 1 == 0 and tostring(p.qty) or ("%.1f"):format(p.qty)
      local age = p.t and time() - p.t > 86400 and (" (price from " .. FI.Ago(p.t) .. ")") or ""
      DEFAULT_CHAT_FRAME:AddMessage(("   %s%%  %s x%s  %s%s%s"):format(pct, FI:ItemName(p.id), qty, p.price and FI.Money(p.price * p.qty) or "never priced", p.converted and " (as 3:1 essence)" or "", age))
    end
    local n = FI.Disenchant:Samples(id)
    DEFAULT_CHAT_FRAME:AddMessage(n > 0 and ("   Odds: the disenchanting table plus %d of your own disenchants of this kind of gear."):format(n)
      or "   Odds: the disenchanting table (your own disenchants refine them).")
  elseif cmd == "sync" then
    local arg = rest:lower()
    if arg == "on" or arg == "off" then
      FI.settings.guildSync = arg == "on"
      FI:Print("Guild sync is now %s.", arg)
    elseif arg == "history" then
      FI.Sync:RequestHistory(true)
    elseif arg == "catchup" then
      FI.Sync:RequestCatchup(FI:Realm().lastScan or (time() - 86400), true)
    elseif arg == "scan" then
      FI.Sync:RequestScan(true)
    else
      FI.Sync:Status()
    end
  elseif cmd == "sell" then
    FI.Sell:Command(rest)
  elseif cmd == "buycap" then
    FI.QuickBuy:SetCap(rest)
  elseif cmd == "quant" or cmd == "quantity" or cmd == "buyqty" then
    FI.QuickBuy:SetMinQty(rest)
  elseif cmd == "quickbuy" then
    if rest:lower() == "debug" then
      FI.QuickBuy:Debug()
    else
      FI:Print("Quick buy: open an item at the AH and set its cap with /goon buycap 1g50s. Then make a macro of these three lines and press it:")
      FI:Print("/click GoonBuy")
      FI:Print("/click GoonBuyRow LeftButton 1")
      FI:Print("/click GoonBuyBtn LeftButton 1")
      FI:Print("/click GoonBuyOk LeftButton 1")
      FI:Print("Each press refreshes or, when the cheapest price is at or under your cap, opens the game's buy popup. With the fourth line, another press confirms it, unless the price is now over your cap. Leave that line out to confirm by mouse only.")
      FI:Print("/goon quant 20 makes it skip listings smaller than 20 (/goon quant 1 takes any size).")
    end
  elseif cmd == "buypopup" then
    if rest:lower() == "reset" then
      FI.AuctionPopups:Reset()
    elseif rest:lower() == "move" then
      FI.AuctionPopups:ShowPlacer()
    else
      FI:Print("Hold Alt and drag the Auction House's buy popup (or any popup at the AH) by its background; it opens there from then on. /goon buypopup reset puts them back.")
    end
  elseif cmd == "sales" then
    local arg = rest:lower()
    if arg == "on" or arg == "off" then
      FI.settings.saleAlerts = arg == "on"
      FI:Print("Sale messages in chat are now %s.", arg)
    elseif arg == "debug" then
      FI.settings.salesDebug = not FI.settings.salesDebug
      FI:Print("Auction chat debug is now %s: chat lines that mention an auction are shown raw.", FI.settings.salesDebug and "on" or "off")
    else
      FI:Print("Sale messages in chat are %s (/goon sales on|off).", FI.settings.saleAlerts == false and "off" or "on")
    end
  elseif cmd == "market" then
    local SD = FI.Seed
    if rest ~= "" then
      if rest == "auto" then
        FI.settings.market = nil
      else
        local r = SD.RulesetFrom(rest)
        if not r then return FI:Print("Unknown ruleset %q. Use normal, pvp, rp, rppvp or auto.", rest) end
        FI.settings.market = r
      end
    end
    local market, status, name = SD:MarketStatus()
    if not market then
      FI:Print("Couldn't tell your ruleset from the realm name %q. Set it with /goon market normal|pvp|rp|rppvp.", tostring(GetRealmName()))
    elseif status == "missing" then
      FI:Print("Market: %s. Its data addon (%s) isn't installed: download the full Goonberg zip from GitHub.", market, name)
    else
      FI:Print("Market: %s. Daily Blizzard prices are %s.", market, status == "current" and "up to date" or "being added")
      if rest ~= "" then SD:Run(false) end
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
  elseif cmd == "layout" then
    FI.UI:CheckLayout()
  elseif cmd == "options" then
    FI.UI:ShowOptions()
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
