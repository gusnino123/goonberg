-- Goonberg Terminal: your own auctions, and the mail they turn into.
-- At the Auction House we read your auctions (the game's "owner" list) and keep a
-- copy per character and auction house, so the Auctions tab shows them anywhere.
-- When one sells, the game says "A buyer has been found for your auction of X": we
-- match that to the copy and say in chat what sold, how many and for how much. The
-- game's line names only the item, and a stack can sell in part, so how many went is
-- a guess until your auction list is read again (see A:Confirm).
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
---@field dep integer?    the deposit paid to post it (nil: posted before we could see)
---@field sold boolean?
---@field guessSold boolean? marked sold by a sale notice, not yet seen sold in the list
---@field soldAt integer? when the game told us (nil: sold while we weren't watching)
---@field m string        "home" or "neutral": which auction house

---@class GT.IncomingMail
---@field id integer?
---@field n string
---@field q integer?
---@field gross integer?  what the buyer paid (nil = we didn't have its price)
---@field net integer?    what reaches you: the price less the AH cut, plus the deposit back
---@field dep integer?    the deposit paid to post it, when we saw it posted
---@field soldAt integer?
---@field due integer     when the mail arrives (at the latest, when approx)
---@field approx boolean? sold while we weren't watching: due is the latest it can be
---@field expired boolean? an auction that ran out: the item comes back
---@field guess boolean?  from a sale notice: the whole stack is assumed until the list says
---@field m string?

-- Your auctions and expected mail, per character (kept with your faction's market,
-- like the rest of your own things)
function A:Data(who)
  local realm = FI:Market("home")
  realm.auctions = realm.auctions or {}
  who = who or UnitName("player") or "?"
  local d = realm.auctions[who]
  if not d then d = {}; realm.auctions[who] = d end
  -- 0.36.0 read some prices as a whole auction's and counted the quantity twice:
  -- start the copy afresh. Your next visit to the AH reads it back, sold ones too.
  if (d.v or 0) < 2 then
    d.lists, d.seen, d.incoming, d.v = {}, {}, {}, 2
  end
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

-- The AH cut taken from a sale: 5% at your faction's AH, 15% at a neutral one
function A.CutRate(market) return market == "neutral" and 0.15 or CUT end

-- What a sale would pay before the cut: the buyout, or the current bid
local function grossOf(e)
  if e.buy and e.buy > 0 then return e.buy end
  if e.bid and e.bid > 0 then return e.bid end
  return nil
end
A.GrossOf = grossOf

-- The AH cut if it sells at its buyout (or current bid)
function A.Fee(e)
  local g = grossOf(e)
  return g and math.floor(g * A.CutRate(e.m)) or nil
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
  -- each auction read, and what we knew of it before
  local prevOf = {}
  for _, e in ipairs(list) do
    local same = pool[key(e)]
    prevOf[e] = same and table.remove(same, 1) or nil
  end
  -- What's left of a stack that sold in part is the same auction, smaller: the same
  -- item at the same price each, fewer of them. It keeps when it was posted and ends.
  for _, e in ipairs(list) do
    if not prevOf[e] and not e.sold and (e.buy or 0) > 0 then
      for _, same in pairs(pool) do
        for i, p in ipairs(same) do
          if p.id == e.id and p.n == e.n and (p.q or 0) > (e.q or 0) and (p.buy or 0) > 0
            and math.abs(unitPrice(p) - unitPrice(e)) < 0.5 then
            prevOf[e] = { expLo = p.expLo, expHi = p.expHi, posted = p.posted }
            table.remove(same, i)
            break
          end
        end
        if prevOf[e] then break end
      end
    end
  end
  for _, e in ipairs(list) do
    local prev = prevOf[e]
    if prev then
      e.expLo, e.expHi, e.posted, e.soldAt, e.dep = prev.expLo, prev.expHi, prev.posted, prev.soldAt, prev.dep
    else
      if fresh and e.tl and POSTED_FOR[e.tl] then
        e.posted = now
        e.expLo, e.expHi = now + POSTED_FOR[e.tl], now + POSTED_FOR[e.tl]
      end
      e.dep = self:TakeDeposit(e)
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
      -- a sale new to our copy: the one a notice guessed at, or one made while we
      -- weren't watching (offline, or before Goonberg knew the auction)
      self:Confirm(e, market)
    elseif prev and prev.sold then
      -- the stack a notice guessed at: sold whole if the list says so too
      if e.sold and prev.guessSold then self:Confirm(e, market, true) else e.guessSold = prev.guessSold end
      e.sold = true
    end
  end
  d.lists[market] = list
  d.seen[market] = now
  FI:Fire("FI_AUCTIONS_CHANGED")
end

-- Deposits. The game never lists what you paid to post, so we note it as you post
-- (the same amount the Auction House window shows) and attach it to the new auction
-- the next time we read your list. Auctions posted before that have no deposit known.
A.pending = {}
local PENDING_FOR = 120 -- a post we haven't seen appear in the list by then is dropped

function A:NotePost(q, buy, dep, stacks)
  if not dep or dep <= 0 then return end
  local now = time()
  for i = #self.pending, 1, -1 do
    if now - self.pending[i].t > PENDING_FOR then table.remove(self.pending, i) end
  end
  for _ = 1, math.max(1, stacks or 1) do
    self.pending[#self.pending + 1] = { q = q, buy = buy or 0, dep = dep, t = now }
  end
end

-- the deposit noted for a newly seen auction, if we posted it moments ago
function A:TakeDeposit(e)
  local now = time()
  for i, p in ipairs(self.pending) do
    if now - p.t <= PENDING_FOR and p.q == e.q and p.buy == (e.buy or 0) then
      table.remove(self.pending, i)
      return p.dep
    end
  end
  return nil
end

-- An auction you just posted goes into our copy straight away, so a sale minutes
-- later is known (quantity, price) even before we next read your list. The next
-- read matches it and keeps what we noted (when posted, deposit).
function A:AddPosted(id, q, buy, minBid, dep, stacks)
  if not id or not q then return end
  local name = FI:ItemName(id)
  if not name and GetItemInfo then name = GetItemInfo(id) end
  if not name then return end
  local market = FI.ahMarket or "home"
  local d = self:Data()
  d.lists[market] = d.lists[market] or {}
  local now = time()
  for _ = 1, math.max(1, stacks or 1) do
    table.insert(d.lists[market], {
      id = id, n = name, q = q, buy = buy or 0, bid = 0, minBid = minBid or 0,
      posted = now, dep = dep, m = market,
    })
  end
  self:NotePost(q, buy, dep, stacks)
  FI:Fire("FI_AUCTIONS_CHANGED")
  -- No request for the real list here. The AH takes one request at a time and drops
  -- the rest, so asking right after a post could swallow the search you make next
  -- and leave it on "Searching...". What we noted above is enough until the list is
  -- next read: when you open the game's Auctions tab, or the AH again.
end

-- Classic AH: PostAuction(minBid, buyout, runTime, stackSize, numStacks). The item is
-- still in the sell slot as the call returns, so the game can still price its deposit.
if hooksecurefunc and PostAuction then
  hooksecurefunc("PostAuction", function(minBid, buyout, runTime, stackSize, numStacks)
    local dep
    if CalculateAuctionDeposit then
      local ok, all = pcall(CalculateAuctionDeposit, runTime, stackSize, numStacks)
      dep = ok and all or nil
      -- some clients price all the stacks at once: we want one stack's
      if dep and numStacks and numStacks > 1 then
        local ok1, one = pcall(CalculateAuctionDeposit, runTime, stackSize, 1)
        dep = (ok1 and one) or math.floor(dep / numStacks)
      end
    end
    local id
    if GetAuctionSellItemInfo then
      local ok, _, _, _, _, _, _, _, itemID = pcall(GetAuctionSellItemInfo)
      id = ok and itemID or nil
    end
    if id then
      A:AddPosted(id, stackSize or 1, buyout, minBid, dep, numStacks)
    else
      A:NotePost(stackSize or 1, buyout, dep, numStacks)
    end
  end)
end

-- Modern AH: PostCommodity(itemLocation, duration, quantity, unitPrice) and
-- PostItem(itemLocation, duration, quantity, bid, buyout). The hook runs as the call
-- returns, while the item is still in its bag slot waiting on the server.
local CA = C_AuctionHouse
local function locItem(loc)
  if not loc or not C_Item or not C_Item.GetItemID then return nil end
  local ok, id = pcall(C_Item.GetItemID, loc)
  return ok and id or nil
end
if hooksecurefunc and CA and CA.PostCommodity then
  hooksecurefunc(CA, "PostCommodity", function(loc, duration, quantity, unitPrice)
    local id = locItem(loc)
    if not id or not quantity or not unitPrice then return end
    local dep
    if CA.CalculateCommodityDeposit then
      local ok, v = pcall(CA.CalculateCommodityDeposit, id, duration, quantity)
      dep = ok and v or nil
    end
    A:AddPosted(id, quantity, unitPrice * quantity, 0, dep, 1)
  end)
end
if hooksecurefunc and CA and CA.PostItem then
  hooksecurefunc(CA, "PostItem", function(loc, duration, quantity, bid, buyout)
    local id = locItem(loc)
    if not id then return end
    local dep
    if CA.CalculateItemDeposit then
      local ok, v = pcall(CA.CalculateItemDeposit, loc, duration, quantity)
      dep = ok and v or nil
    end
    A:AddPosted(id, quantity or 1, buyout or 0, bid or 0, dep, 1)
  end)
end
local tries = 0
function A:Read()
  if not FI.ahOpen then return end
  local list, complete
  -- the classic owner list when the client has it: its prices are per auction, as
  -- the game's Auctions tab shows them. (Some clients also have the modern list, but
  -- there its buyout can already be the whole auction's, which counted it twice.)
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
FI:On("FI_AH_CLOSED", function()
  A.readThisVisit = false
  A:FlushAwaiting(true) -- the list can't be read any more: say the held lines now
end)
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
  local gross = grossOf(e)
  -- a sale's mail pays the price, less the AH cut, plus the deposit back
  local m = {
    id = e.id, n = e.n, q = e.q, m = e.m, soldAt = soldAt, dep = e.dep,
    gross = not expired and gross or nil,
    net = (not expired and gross) and (gross - A.Fee(e) + (e.dep or 0)) or nil,
    due = expired and time() or ((soldAt or time()) + A.MAIL_DELAY),
    approx = (not expired and soldAt == nil) or nil,
    expired = expired or nil,
  }
  d.incoming[#d.incoming + 1] = m
  return m
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

-- Sale notices for a stack, held back at the AH until the list says how many went
A.awaiting = {}  -- { m = the guessed mail, t = GetTime(), fallback = the line if the list never says }
A.HIDE = "\001goonberg-hide" -- in place of a line: show nothing now, ours follows
local CONFIRM_WAIT = 4

-- our own sale line, where the game's would have gone
local function say(text)
  if FI.settings.saleAlerts == false then return end
  local cf = DEFAULT_CHAT_FRAME
  if not (cf and cf.AddMessage) then return end
  local c = ChatTypeInfo and ChatTypeInfo.SYSTEM
  cf:AddMessage(text, c and c.r or 1, c and c.g or 1, c and c.b or 0)
end

local function soldLine(m)
  local link = (m.id and FI:ItemLink(m.id)) or m.n
  local q = m.q or 1
  if not m.gross then return ("Sold %s x%d."):format(link, q) end
  if q > 1 then
    return ("Sold %s x%d at %s each, %s total."):format(link, q, FI.Coins(math.floor(m.gross / q + 0.5)), FI.Coins(m.gross))
  end
  return ("Sold %s x%d for %s."):format(link, q, FI.Coins(m.gross))
end

-- A sold auction in a fresh read of your list. If a sale notice guessed at it, the
-- guess gives way to what the list says: how many went (a stack can sell in part),
-- at the price each we knew, at the time the notice came. `whole`: the very stack the
-- notice marked, now listed as sold.
function A:Confirm(e, market, whole)
  local d = self:Data()
  local guess
  for _, m in ipairs(d.incoming) do
    if m.guess and m.n == e.n and (m.m or market) == market then guess = m break end
  end
  if not guess then
    if not whole then self:AddIncoming(e, nil) end
    return
  end
  guess.guess = nil
  e.soldAt = e.soldAt or guess.soldAt
  if not whole and guess.gross and guess.q and e.q and e.q < guess.q then
    -- part of the stack: its share of the price, less the cut (the deposit comes
    -- back with the rest of the stack, not with this mail)
    local gross = math.floor(guess.gross / guess.q * e.q + 0.5)
    guess.q, guess.gross, guess.dep = e.q, gross, nil
    guess.net = gross - math.floor(gross * A.CutRate(market))
  end
  for i, w in ipairs(self.awaiting) do
    if w.m == guess then
      table.remove(self.awaiting, i)
      say(soldLine(guess))
      break
    end
  end
end

-- held lines the list never settled (not read in time): say what we do know
function A:FlushAwaiting(all)
  local now = GetTime()
  local due = {}
  for i = #self.awaiting, 1, -1 do
    local w = self.awaiting[i]
    if all or now - w.t >= CONFIRM_WAIT - 0.1 then
      table.insert(due, 1, w)
      table.remove(self.awaiting, i)
    end
  end
  for _, w in ipairs(due) do say(w.fallback) end
end

-- "A buyer has been found for your auction of X." Records the sale and returns the
-- line that replaces the game's in chat (A.HIDE: nothing now, the line follows once
-- your auction list has said how many went).
function A:OnSold(name, now)
  now = now or time()
  local list = unsoldOf(name)
  local e = list[1]
  local text
  if e then
    e.sold, e.soldAt, e.guessSold = true, now, true
    local m = self:AddIncoming(e, now)
    m.guess = true
    -- several different stacks of it up: we can't tell which one went
    local unsure = false
    for i = 2, #list do
      if list[i].q ~= e.q or list[i].buy ~= e.buy then unsure = true end
    end
    local link = (e.id and FI:ItemLink(e.id)) or name
    -- a stack can sell in part, and the game's line doesn't say how many went
    local stack = (e.q or 1) > 1
    if m.gross and stack then
      text = ("Sold %s: part or all of your x%d at %s each%s."):format(link, e.q,
        FI.Coins(math.floor(m.gross / e.q + 0.5)), unsure and ", probably the cheapest of your stacks of it" or "")
    elseif m.gross then
      -- kept short: what you get after the cut and when the mail lands are on the
      -- Auctions tab (Mail on the way)
      text = ("Sold %s x%d for %s%s."):format(link, e.q, FI.Coins(m.gross),
        unsure and ", probably the cheapest of your stacks of it" or "")
    elseif stack then
      text = ("Sold %s: part or all of your x%d."):format(link, e.q)
    else
      text = ("Sold %s x%d."):format(link, e.q)
    end
    -- at the AH your list is about to be read again and says exactly how many went:
    -- hold the line for that, and fall back to this one if it doesn't come
    if stack and FI.ahOpen then
      self.awaiting[#self.awaiting + 1] = { m = m, t = GetTime(), fallback = text }
      C_Timer.After(CONFIRM_WAIT, function() A:FlushAwaiting() end)
      text = A.HIDE
    end
  else
    -- not in our copy: put up before Goonberg last read your auctions
    self:AddIncoming({ n = name }, now)
    text = ("Sold %s. Open your auctions at the Auction House once and Goonberg will know their prices."):format(name)
  end
  FI:Fire("FI_AUCTIONS_CHANGED")
  -- at the AH, read the real list again (a commodity can sell only part of a stack)
  if FI.ahOpen then FI:Debounce("ownedAfterSale", 1, function() A:Query() end) end
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
-- the client's own wording first, then the English text as a fallback
local function patterns(global, english)
  local list = {}
  if global then list[#list + 1] = pattern(global) end
  if global ~= english then list[#list + 1] = pattern(english) end
  return list
end
A.SOLD_ALL = patterns(_G.ERR_AUCTION_SOLD_S, "A buyer has been found for your auction of %s.")
A.EXPIRED_ALL = patterns(_G.ERR_AUCTION_EXPIRED_S, "Your auction of %s has expired.")
A.SOLD, A.EXPIRED = A.SOLD_ALL[1], A.EXPIRED_ALL[1]

-- the item name in one of the game's sentences (colour codes, links and stray spaces aside)
local function clean(msg)
  return (msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")
    :gsub("^%s+", ""):gsub("%s+$", ""))
end
local function matchAny(msg, list)
  for _, p in ipairs(list) do
    local name = msg:match(p)
    if name then return name end
  end
end
function A.SoldName(msg) return matchAny(clean(msg), A.SOLD_ALL) end
function A.ExpiredName(msg) return matchAny(clean(msg), A.EXPIRED_ALL) end

-- One game line can reach us several ways: the CHAT_MSG_SYSTEM event, the chat filter
-- (once per chat window that shows system messages), and each chat window printing it
-- (some clients print auction notices straight to chat with no event). Each way sees
-- the same lines in the same order within a frame, so "the 2nd copy of this text this
-- frame" names the same sale everywhere: whichever way sees it first records it, and
-- the rest reuse the result. Two sales of the same item at once stay two sales.
local seq, handled, handledOrder = {}, {}, {}
local function lineKey(source, msg)
  local now = GetTime()
  local s = seq[source]
  if not s or s.t ~= now then s = { t = now, n = {} }; seq[source] = s end
  s.n[msg] = (s.n[msg] or 0) + 1
  return msg .. "@" .. now .. "#" .. s.n[msg]
end

-- Records a sold or expired notice once. Returns the line to show instead of the
-- game's for a sale (nil for anything else).
function A:HandleLine(msg, source)
  if type(msg) ~= "string" or not FI.db then return nil end
  local sold = A.SoldName(msg)
  local expired = not sold and A.ExpiredName(msg)
  if not sold and not expired then return nil end
  local k = lineKey(source, msg)
  if handled[k] ~= nil then return handled[k] or nil end
  local text = false
  if sold then text = self:OnSold(sold) else self:OnExpired(expired) end
  handled[k] = text
  handledOrder[#handledOrder + 1] = k
  if #handledOrder > 40 then handled[table.remove(handledOrder, 1)] = nil end
  return text or nil
end

local function alertsOn() return FI.settings.saleAlerts ~= false end

FI:On("CHAT_MSG_SYSTEM", function(_, msg) A:HandleLine(msg, "event") end)

-- The game's "A buyer has been found..." line becomes ours: what sold, how many, for
-- how much. With sale alerts off the game's line shows as it is.
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(frame, _, msg, ...)
    local text = A:HandleLine(msg, "filter:" .. tostring(frame))
    if text and alertsOn() then
      if text == A.HIDE then return true end
      return false, text, ...
    end
    return false
  end)
end

-- Chat windows themselves, for notices the client prints without an event
local hooked = {}
function A:HookChatFrames()
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and not hooked[cf] and cf.AddMessage then
      hooked[cf] = true
      local orig = cf.AddMessage
      local source = "print:" .. i
      cf.AddMessage = function(frame, msg, ...)
        if type(msg) == "string" and FI.db then
          if FI.settings.salesDebug and msg:lower():find("auction", 1, true) then
            orig(frame, "|cffffd100Goonberg debug:|r " .. msg:gsub("|", "||") .. (A.SoldName(msg) and "  (sold: matched)" or ""))
          end
          local text = A:HandleLine(msg, source)
          if text and alertsOn() then
            if text == A.HIDE then return end
            msg = text
          end
        end
        return orig(frame, msg, ...)
      end
    end
  end
end
A:HookChatFrames()
FI:On("PLAYER_LOGIN", function() A:HookChatFrames() end)

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
