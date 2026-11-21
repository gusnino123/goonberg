-- Goonberg Terminal: your own auctions, and the mail they turn into.
-- At the Auction House we read your auctions (the game's "owner" list) and keep a
-- copy per character and auction house, so the Auctions tab shows them anywhere.
-- When one sells, the game says "A buyer has been found for your auction of X": we
-- match that to the copy and say in chat what sold, how many, for how much, and when
-- its mail arrives (on Classic realms the money comes an hour after the sale).
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Auctions
local A = {}
FI.Auctions = A

local HOUR = 3600
local CUT = 0.05
-- AH money mail arrives an hour after the sale on Classic realms, at once on retail
A.MAIL_DELAY = (WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and 0 or HOUR
-- The owner list says how long an auction has left only as a range (1-4)
A.TIME_LEFT = { { 0, HOUR / 2 }, { HOUR / 2, 2 * HOUR }, { 2 * HOUR, 8 * HOUR }, { 8 * HOUR, 24 * HOUR } }
-- what a just-posted auction in each range was put up for (2, 8 or 24 hours)
local POSTED_FOR = { [2] = 2 * HOUR, [3] = 8 * HOUR, [4] = 24 * HOUR }
local KEEP_MAIL = 3 * 86400 -- forget mail we expected this long ago

---@class GT.MyAuction
---@field id integer?     item
---@field n string        item name (what the game's sold message names)
---@field q integer       stack size
---@field buy integer     buyout for the whole stack (0 = none)
---@field bid integer     current bid (0 = none yet)
---@field minBid integer
---@field tl integer?     time-left range (1-4) when last read
---@field expLo integer?  ends no earlier than this
---@field expHi integer?  and no later than this
---@field posted integer? when it went up, if we saw that happen
---@field sold boolean?
---@field soldAt integer? when the game told us (nil: sold while we weren't watching)
---@field m string        "home" or "neutral": which auction house

---@class GT.IncomingMail
---@field id integer?
---@field n string
---@field q integer?
---@field gross integer?  what the buyer paid (nil = we didn't have its price)
---@field net integer?    what reaches you after the AH cut
---@field soldAt integer?
---@field due integer     when the mail arrives (at the latest, when approx)
---@field approx boolean? sold while we weren't watching: due is the latest it can be
---@field expired boolean? an auction that ran out: the item comes back
---@field m string?

-- Your auctions and expected mail, per character (kept with your faction's market,
-- like the rest of your own things)
function A:Data(who)
  local realm = FI:Market("home")
  realm.auctions = realm.auctions or {}
  who = who or UnitName("player") or "?"
  local d = realm.auctions[who]
  if not d then d = {}; realm.auctions[who] = d end
  d.lists = d.lists or {}   -- market -> { GT.MyAuction }
  d.seen = d.seen or {}     -- market -> when we last read that auction house
  d.incoming = d.incoming or {}
  return d
end

-- every auction we know of, both auction houses
function A:All()
  local out = {}
  for _, list in pairs(self:Data().lists) do
    for _, e in ipairs(list) do out[#out + 1] = e end
  end
  return out
end

local function unitPrice(e)
  local total = (e.buy and e.buy > 0) and e.buy or (e.bid or 0)
  return total / math.max(1, e.q or 1)
end
A.UnitPrice = unitPrice

-- ---------------------------------------------------------------------------
-- Reading your auctions at the Auction House
-- ---------------------------------------------------------------------------
-- Classic AH: the "owner" list. Returns the auctions and whether every one was
-- readable (an item the game hasn't loaded yet comes back without a name).
local function readLegacy()
  local out, complete = {}, true
  local n = GetNumAuctionItems("owner") or 0
  for i = 1, n do
    local name, _, count, _, _, _, _, minBid, _, buyout, bidAmount, _, _, _, _, saleStatus, itemID = GetAuctionItemInfo("owner", i)
    if name and itemID then
      out[#out + 1] = {
        id = itemID, n = name, q = count or 1, buy = buyout or 0, bid = bidAmount or 0, minBid = minBid or 0,
        tl = GetAuctionItemTimeLeft and GetAuctionItemTimeLeft("owner", i) or nil,
        sold = saleStatus == 1 or nil,
      }
    else
      complete = false
    end
  end
  return out, complete
end

-- Modern AH (C_AuctionHouse): exact seconds left. Its buyout is per unit for
-- stackable goods, as the game's own Auctions list shows it.
local function readModern()
  local out, complete = {}, true
  local ok, list = pcall(C_AuctionHouse.GetOwnedAuctions)
  if not ok or type(list) ~= "table" then return out, false end
  for _, a in ipairs(list) do
    local id = a.itemKey and a.itemKey.itemID
    if id then
      local name, loading = FI:ItemName(id)
      if loading then complete = false end
      local q = a.quantity or 1
      local each = a.buyoutAmount or 0
      out[#out + 1] = {
        id = id, n = name, q = q, buy = each * q, bid = a.bidAmount or 0, minBid = 0,
        secs = a.timeLeftSeconds, sold = (a.status == 1) or nil,
      }
    end
  end
  return out, complete
end

local function key(e) return (e.id or e.n) .. ":" .. (e.q or 0) .. ":" .. (e.buy or 0) end

-- A fresh read of one auction house's auctions replaces our copy. What we already
-- knew about each (when it ends, when it sold) carries over. `fresh`: we read this
-- auction house moments ago during this visit, so anything new was just posted.
function A:Update(market, list, fresh)
  local d = self:Data()
  local now = time()
  local pool = {}
  for _, e in ipairs(d.lists[market] or {}) do
    local k = key(e)
    pool[k] = pool[k] or {}
    table.insert(pool[k], e)
  end
  for _, e in ipairs(list) do
    local same = pool[key(e)]
    local prev = same and table.remove(same, 1)
    if prev then
      e.expLo, e.expHi, e.posted, e.soldAt = prev.expLo, prev.expHi, prev.posted, prev.soldAt
    elseif fresh and e.tl and POSTED_FOR[e.tl] then
      e.posted = now
      e.expLo, e.expHi = now + POSTED_FOR[e.tl], now + POSTED_FOR[e.tl]
    end
    if e.secs then
      e.expLo, e.expHi = now + e.secs, now + e.secs
      e.secs = nil
    elseif e.tl and A.TIME_LEFT[e.tl] then
      -- each read narrows when it ends: within this range now, and every earlier one
      local lo, hi = now + A.TIME_LEFT[e.tl][1], now + A.TIME_LEFT[e.tl][2]
      local nlo, nhi = math.max(e.expLo or lo, lo), math.min(e.expHi or hi, hi)
      if nlo > nhi then nlo, nhi = lo, hi end
      e.expLo, e.expHi = nlo, nhi
    end
    e.m = market
    if e.sold and not (prev and prev.sold) then
      -- sold while we weren't watching (offline, or before Goonberg knew it)
      self:AddIncoming(e, nil)
    elseif prev and prev.sold then
      e.sold = true
    end
  end
  d.lists[market] = list
  d.seen[market] = now
  FI:Fire("FI_AUCTIONS_CHANGED")
end

local tries = 0
function A:Read()
  if not FI.ahOpen then return end
  local list, complete
  if GetNumAuctionItems and GetAuctionItemInfo then
    list, complete = readLegacy()
  elseif C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions then
    list, complete = readModern()
  else
    return
  end
  -- a few items still loading: read again in a moment rather than lose them
  if not complete and tries < 3 then
    tries = tries + 1
    C_Timer.After(1, function() A:Read() end)
    return
  end
  tries = 0
  self:Update(FI.ahMarket or "home", list, self.readThisVisit)
  self.readThisVisit = true
end

-- Ask the game for your auctions (it answers with AUCTION_OWNED_LIST_UPDATE)
function A:Query()
  if not FI.ahOpen then return false end
  if GetOwnerAuctionItems then
    return (pcall(GetOwnerAuctionItems, 0))
  elseif C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
    return (pcall(C_AuctionHouse.QueryOwnedAuctions, {}))
  end
  return false
end

FI:On("FI_AH_OPEN", function()
  A.readThisVisit = false
  -- after the AH has settled (and after a scan request, which goes first)
  C_Timer.After(2, function() A:Query() end)
end)
FI:On("FI_AH_CLOSED", function() A.readThisVisit = false end)
for _, e in ipairs({ "AUCTION_OWNED_LIST_UPDATE", "OWNED_AUCTIONS_UPDATED" }) do
  FI:On(e, function() FI:Debounce("ownedAuctions", 0.3, function() A:Read() end) end)
end

-- ---------------------------------------------------------------------------
-- Sales and the mail they turn into
-- ---------------------------------------------------------------------------
---@param e table  the auction (or what we know of it)
---@param soldAt integer?  nil: sold at some point before now
---@return GT.IncomingMail
function A:AddIncoming(e, soldAt, expired)
  local d = self:Data()
  local gross = (e.buy and e.buy > 0) and e.buy or ((e.bid and e.bid > 0) and e.bid or nil)
  local m = {
    id = e.id, n = e.n, q = e.q, m = e.m, soldAt = soldAt,
    gross = not expired and gross or nil,
    net = (not expired and gross) and math.floor(gross * (1 - CUT) + 0.5) or nil,
    due = expired and time() or ((soldAt or time()) + A.MAIL_DELAY),
    approx = (not expired and soldAt == nil) or nil,
    expired = expired or nil,
  }
  d.incoming[#d.incoming + 1] = m
  return m
end

local function mailWhen(m)
  if m.due <= time() then return "The money is in your mailbox." end
  return ("Mail arrives at %s (in %s)."):format(date("%H:%M", m.due), FI.Duration(m.due - time()))
end

function A:Say(text)
  local c = ChatTypeInfo and ChatTypeInfo.SYSTEM
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Goonberg:|r " .. text, c and c.r or 1, c and c.g or 1, c and c.b or 0)
end

-- Your unsold auctions of an item, cheapest each first: a buyer takes the cheapest
local function unsoldOf(name)
  local list = {}
  for _, e in ipairs(A:All()) do
    if e.n == name and not e.sold then list[#list + 1] = e end
  end
  table.sort(list, function(a, b) return unitPrice(a) < unitPrice(b) end)
  return list
end

-- "A buyer has been found for your auction of X."
function A:OnSold(name, now)
  now = now or time()
  local list = unsoldOf(name)
  local e = list[1]
  local text
  if e then
    e.sold, e.soldAt = true, now
    local m = self:AddIncoming(e, now)
    -- several different stacks of it up: we can't tell which one went
    local unsure = false
    for i = 2, #list do
      if list[i].q ~= e.q or list[i].buy ~= e.buy then unsure = true end
    end
    local link = (e.id and FI:ItemLink(e.id)) or name
    if m.gross then
      text = ("Sold %s x%d for %s (%s after the AH cut)%s. %s"):format(link, e.q, FI.Money(m.gross), FI.Money(m.net),
        unsure and ", probably the cheapest of your stacks of it" or "", mailWhen(m))
    else
      text = ("Sold %s x%d. %s"):format(link, e.q, mailWhen(m))
    end
  else
    -- not in our copy: put up before Goonberg last read your auctions
    local m = self:AddIncoming({ n = name }, now)
    text = ("Sold %s. %s Open your auctions at the Auction House once and Goonberg will know their prices."):format(name, mailWhen(m))
  end
  if FI.settings.saleAlerts ~= false then self:Say(text) end
  FI:Fire("FI_AUCTIONS_CHANGED")
  return text
end

-- "Your auction of X has expired." The one that was due to end first goes.
function A:OnExpired(name)
  local best, bestList, bestIdx
  for _, list in pairs(self:Data().lists) do
    for i, e in ipairs(list) do
      if e.n == name and not e.sold and (not best or (e.expHi or math.huge) < (best.expHi or math.huge)) then
        best, bestList, bestIdx = e, list, i
      end
    end
  end
  if best then table.remove(bestList, bestIdx) end
  self:AddIncoming(best or { n = name }, nil, true)
  FI:Fire("FI_AUCTIONS_CHANGED")
end

-- the game's sentences, as patterns ("%s" becomes the item name)
local function pattern(fmt)
  if not fmt then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
  return "^" .. p .. "$"
end
A.SOLD = pattern(_G.ERR_AUCTION_SOLD_S or "A buyer has been found for your auction of %s.")
A.EXPIRED = pattern(_G.ERR_AUCTION_EXPIRED_S or "Your auction of %s has expired.")

FI:On("CHAT_MSG_SYSTEM", function(_, msg)
  if type(msg) ~= "string" or not FI.db then return end
  local name = A.SOLD and msg:match(A.SOLD)
  if name then A:OnSold(name); return end
  name = A.EXPIRED and msg:match(A.EXPIRED)
  if name then A:OnExpired(name) end
end)

-- Mail that has arrived is in your mailbox when you open it: off the list. Very old
-- entries go too (a sale we never heard back about).
FI:On("MAIL_SHOW", function()
  local d = A:Data()
  local now, changed = time(), false
  for i = #d.incoming, 1, -1 do
    if d.incoming[i].due <= now then table.remove(d.incoming, i); changed = true end
  end
  -- sold auctions whose money has arrived are done (the AH drops them then too)
  for _, list in pairs(d.lists) do
    for i = #list, 1, -1 do
      local e = list[i]
      if e.sold and (e.soldAt or 0) + A.MAIL_DELAY <= now then table.remove(list, i); changed = true end
    end
  end
  if changed then FI:Fire("FI_AUCTIONS_CHANGED") end
end)
FI:On("PLAYER_LOGIN", function()
  local d = A:Data()
  local now = time()
  for i = #d.incoming, 1, -1 do
    if now - d.incoming[i].due > KEEP_MAIL then table.remove(d.incoming, i) end
  end
  -- auctions long past their end that never came back to us (sold or expired offline)
  for _, list in pairs(d.lists) do
    for i = #list, 1, -1 do
      local e = list[i]
      if e.expHi and now - e.expHi > KEEP_MAIL then table.remove(list, i) end
    end
  end
end)
