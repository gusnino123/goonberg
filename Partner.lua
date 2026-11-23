-- Goonberg Terminal: partner link (a shared ledger)
-- Two guildmates who trade together link up. From then on each sees the other's Auction
-- House purchases and sales on the Ledger tab, beside their own and summed.
-- Both have to say yes: one asks (/goon partner <name>, or the Ledger tab), the other
-- accepts. Only AH purchases and sales are sent, only to that one player, by addon
-- whisper; nothing goes to the guild. Unlinking removes the other's trades from your
-- saved data. A link belongs to the character that made it.
--   I1                     will you link with me?
--   A1 / D1                yes / no (also: the asker taking the question back)
--   U1                     the link is over
--   H1:<ledger>:<have>:<r> hello: "of your ledger <ledger> I hold trades up to number
--                          <have>". r = 1 asks for a hello back, so both sides catch up
--   S1:<ledger>:<from>:<through>:<count>   a chunk of trades starts
--   B<n,t,k,q,g,f,name;...>                trades (numbers in base 36; k: b bought, s sold)
--   E1:<through>           the chunk is complete: only now does the receiver keep it
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Partner
local P = {}
FI.Partner = P
local Y = FI.Sync
local b36, n36 = Y.b36, Y.n36

local PREFIX = "GoonbergPair"
local PROTO = "1"
local MSG_MAX = 250
local CHUNK = 60                 -- trades per chunk: a lost message costs one chunk, not the whole transfer
local INVITE_KEEP = 7 * 86400    -- an unanswered question is forgotten after a week
local NAME_MAX = 100
P.MIN_VERSION = "0.41"           -- the first Goonberg that can link

local CI = C_ChatInfo

local function me() return UnitName("player") or "?" end
local function short(full) return (full and full:match("^([^%-]+)")) or full end

-- The same player? Addon chat on some servers adds a surname ("Bob Smith" for "Bob").
local function same(a, b)
  if not a or not b then return false end
  a, b = a:lower(), b:lower()
  return a == b or a:sub(1, #b + 1) == b .. " " or b:sub(1, #a + 1) == a .. " "
end
P.Same = same

local function changed(...) FI:Fire("FI_PARTNER_CHANGED", ...) end

-- ---------------------------------------------------------------------------
-- Saved data: per character, with your faction's market (FI:Market("home"))
--   link = { name, state = "invited"|"linked", at, split,
--            epoch, have, entries, synced }   -- the partner's trades we hold
--   invites = { [name] = when they asked }
-- ---------------------------------------------------------------------------
function P:Data()
  local realm = FI:Market("home")
  realm.partner = realm.partner or {}
  local who = me()
  local d = realm.partner[who]
  if not d then
    d = { invites = {} }
    realm.partner[who] = d
  end
  d.invites = d.invites or {}
  return d
end

function P:Link() return self:Data().link end

function P:Linked()
  local link = self:Link()
  return link ~= nil and link.state == "linked"
end

-- Can we whisper at all? (a partner is a guildmate, so no guild means no link)
function P:Ready()
  return self.ready == true and CI ~= nil and CI.SendAddonMessage ~= nil and IsInGuild() and true or false
end

-- The newest unanswered question, or the one from `name`
function P:Asker(name)
  local who, newest
  for n, t in pairs(self:Data().invites) do
    if name and name ~= "" then
      if same(n, name) then return n end
    elseif not newest or t > newest then
      who, newest = n, t
    end
  end
  return who
end

local function whisper(msg, to, tag, first)
  Y.Send(msg, "WHISPER", to, tag or "pair", first, PREFIX)
end

-- ---------------------------------------------------------------------------
-- Your own trades, numbered. Each AH purchase and sale gets a running number the
-- first time it's shared, so a partner can say "I have yours up to 412" and get only
-- what's new. The numbers belong to this saved ledger (its name is a random one): if
-- the ledger is wiped or restored from a backup, it gets a new name and the partner
-- starts over.
-- ---------------------------------------------------------------------------
local function shareable(e)
  return (e.k == "buy" or e.k == "sale") and e.i ~= nil and e.t ~= nil
end

local function newEpoch(d)
  d.pairEpoch = b36(time()) .. b36(math.random(1, 46655))
  d.pairSeq = 0
  for _, e in ipairs(d.entries) do e.sn = nil end
end

function P:Numbered()
  local d = FI.Ledger:Data()
  if not d.pairEpoch then newEpoch(d) end
  local seq = d.pairSeq or 0
  for _, e in ipairs(d.entries) do
    if not e.sn and shareable(e) then
      seq = seq + 1
      e.sn = seq
    end
  end
  d.pairSeq = seq
  return d
end

-- One trade as text. The name goes last, so it may hold commas; ";" separates trades.
local function encode(e)
  local name = tostring(e.i):gsub("[;%c]", " "):sub(1, NAME_MAX)
  return table.concat({ b36(e.sn), b36(e.t), e.k == "buy" and "b" or "s", b36(e.q or 1), b36(e.g or 0), b36(e.f or 0), name }, ",")
end

-- ...and back. Whatever arrives is someone else's text: nothing in a name may act as
-- a color, a texture or a link when it's drawn, and no number may be absurd.
local function decode(s)
  local a, t, k, q, g, f, name = s:match("^(%w+),(%w+),([bs]),(%w+),(%w+),(%w+),(.+)$")
  local sn, when = n36(a), n36(t)
  if not sn or not when or when > time() + 86400 then return nil end
  name = name:gsub("|", ""):gsub("%c", " "):sub(1, NAME_MAX)
  if name:gsub("%s", "") == "" then return nil end
  return { sn = sn, t = when, k = k == "b" and "buy" or "sale", q = math.max(1, n36(q) or 1), g = n36(g) or 0, f = n36(f) or 0, i = name }
end
P.Encode, P.Decode = encode, decode

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
function P:Hello(wantReply)
  local link = self:Link()
  if not link or link.state ~= "linked" or not self:Ready() then return false end
  whisper(("H%s:%s:%s:%s"):format(PROTO, link.epoch or "0", b36(link.have or 0), wantReply and "1" or "0"), link.name, "pair", true)
  return true
end

-- Your trades numbered above `from`, in chunks. Each chunk says where it starts, so the
-- chunks form a chain and the receiver notices a missing one.
function P:SendFrom(from)
  local link = self:Link()
  if not link or link.state ~= "linked" or not self:Ready() then return end
  local d = self:Numbered()
  local list = {}
  for _, e in ipairs(d.entries) do
    if e.sn and e.sn > from and shareable(e) then list[#list + 1] = e end
  end
  if Y.RefreshRoster then Y.RefreshRoster() end
  local to, cursor, i = link.name, from, 1
  repeat
    local last = math.min(#list, i + CHUNK - 1)
    local through = last >= #list and d.pairSeq or list[last].sn
    whisper(("S%s:%s:%s:%s:%s"):format(PROTO, d.pairEpoch, b36(cursor), b36(through), b36(math.max(0, last - i + 1))), to, "ledger")
    local cur = "B"
    for j = i, last do
      local text = encode(list[j])
      if #cur + #text + 1 > MSG_MAX then
        whisper(cur, to, "ledger")
        cur = "B"
      end
      cur = (cur == "B") and (cur .. text) or (cur .. ";" .. text)
    end
    if cur ~= "B" then whisper(cur, to, "ledger") end
    whisper("E" .. PROTO .. ":" .. b36(through), to, "ledger")
    cursor, i = through, last + 1
  until i > #list
  self.sentThrough = d.pairSeq
end

-- "Send me yours again from where I am": after a chunk that didn't add up, at most
-- every 20 seconds so two confused sides can't keep each other busy
local function resync()
  local now = GetTime()
  if P.lastResync and now - P.lastResync < 20 then return end
  P.lastResync = now
  P:Hello(false)
end

-- ---------------------------------------------------------------------------
-- Receiving a partner's trades
-- ---------------------------------------------------------------------------
local function onHello(body)
  local epoch, have, reply = body:match("^(%w+):(%w+):([01])$")
  if not epoch then return end
  local d = P:Numbered()
  local from = n36(have) or 0
  if epoch ~= d.pairEpoch then
    from = 0
  elseif from > (d.pairSeq or 0) then
    -- they hold more of this ledger than exists: ours was restored from an older
    -- copy. A new name makes them drop what they hold and take it all again.
    newEpoch(d)
    P:Numbered()
    from = 0
  end
  Y:DropTagged("ledger") -- whatever was still going out is replaced by this answer
  P:SendFrom(from)
  if reply == "1" then P:Hello(false) end
end

local function onStart(link, body)
  P.session = nil
  local epoch, a, b, c = body:match("^(%w+):(%w+):(%w+):(%w+)$")
  local from, through, count = n36(a), n36(b), n36(c)
  if not epoch or not from or not through or not count or through < from then return end
  local fresh = epoch ~= link.epoch
  -- a ledger we don't hold must start at the beginning; one we do hold must carry on
  -- from where we are (or before: trades we already have are skipped)
  if fresh and from ~= 0 then return resync() end
  if not fresh and from > (link.have or 0) then return resync() end
  P.session = { epoch = epoch, through = through, count = count, got = {}, seen = 0, fresh = fresh }
end

local function onBatch(body)
  local s = P.session
  if not s then return end
  for text in body:gmatch("[^;]+") do
    s.seen = s.seen + 1
    local e = decode(text)
    if e then s.got[#s.got + 1] = e end
  end
end

local function onEnd(link, body)
  local s = P.session
  P.session = nil
  if not s or n36(body) ~= s.through then return end
  if s.seen ~= s.count then return resync() end -- a message went missing: ask again
  if s.fresh then link.entries, link.have, link.epoch = {}, 0, s.epoch end
  link.entries = link.entries or {}
  local have, added = link.have or 0, 0
  for _, e in ipairs(s.got) do
    if e.sn > have and e.sn <= s.through then
      link.entries[#link.entries + 1] = { t = e.t, k = e.k, i = e.i, q = e.q, g = e.g, f = e.f }
      added = added + 1
    end
  end
  link.have = math.max(have, s.through)
  link.synced = time()
  changed(added)
end

-- ---------------------------------------------------------------------------
-- Linking up
-- ---------------------------------------------------------------------------
local function inGuild(who)
  -- (before the game has given us the roster nobody can be checked: let them through,
  -- an invite still needs your own yes)
  if (GetNumGuildMembers and GetNumGuildMembers() or 0) == 0 then return true end
  return Y:GuildMember(who) ~= nil
end

local function onInvite(data, who)
  if not inGuild(who) then return end
  local link = data.link
  if link and same(who, link.name) then
    -- we already said yes to them (their side started over), or we asked them and
    -- our questions crossed: either way it's a yes
    local was = link.state
    link.state = "linked"
    if was ~= "linked" then link.at = time() end
    whisper("A" .. PROTO, link.name, "pair", true)
    if was ~= "linked" then FI:Print("%s and you are now linked: your AH purchases and sales show on each other's Ledger tab.", link.name) end
    return changed()
  end
  local before = data.invites[who]
  data.invites[who] = time()
  if not before or time() - before > 60 then
    FI:Print("%s wants to link ledgers with you: you'd both see each other's AH purchases and sales. Accept on the Ledger tab or with /goon partner accept (decline: /goon partner decline).", who)
  end
  changed()
end

local function onAccept(data, who)
  local link = data.link
  if link and same(who, link.name) then
    if link.state == "invited" then
      link.state, link.at = "linked", time()
      FI:Print("%s accepted: you're linked. Your AH purchases and sales now show on each other's Ledger tab.", link.name)
      changed()
    end
    return P:Hello(true)
  end
  -- a yes to a question we've taken back
  whisper("U" .. PROTO, who, "pair", true)
end

local function onDecline(data, who)
  local link = data.link
  if link and link.state == "invited" and same(who, link.name) then
    data.link = nil
    FI:Print("%s declined to link ledgers.", link.name)
    return changed()
  end
  for n in pairs(data.invites) do
    if same(n, who) then data.invites[n] = nil; changed() end
  end
end

local function onUnlink(data, who)
  local link = data.link
  for n in pairs(data.invites) do
    if same(n, who) then data.invites[n] = nil end
  end
  if not link or not same(who, link.name) then return end
  data.link = nil
  P.session, P.sentThrough = nil, nil
  Y:DropTagged("ledger")
  if link.state == "linked" then
    FI:Print("%s ended the link: their trades are gone from your Ledger tab, and yours no longer go to them.", link.name)
  end
  changed()
end

local unlinkTold = {}
FI:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, from)
  if prefix ~= PREFIX or channel ~= "WHISPER" or type(text) ~= "string" or text == "" or not P.ready then return end
  local who = short(from)
  if not who or who == me() then return end
  local kind, rest = text:sub(1, 1), text:sub(2)
  local data = P:Data()
  local link = data.link
  local partner = link ~= nil and same(who, link.name)
  if partner then
    Y:Heard(who)
    Y:Heard(link.name)
  end
  if kind == "B" then
    if partner and link.state == "linked" then onBatch(rest) end
    return
  end
  local proto, body = rest:match("^(%d+):?(.*)$")
  if proto ~= PROTO then return end
  if kind == "I" then onInvite(data, who)
  elseif kind == "A" then onAccept(data, who)
  elseif kind == "D" then onDecline(data, who)
  elseif kind == "U" then onUnlink(data, who)
  elseif kind == "H" or kind == "S" or kind == "E" then
    if partner and link.state == "linked" then
      if kind == "H" then onHello(body) elseif kind == "S" then onStart(link, body) else onEnd(link, body) end
    elseif not partner and kind ~= "E" then
      -- they still think we're linked (we unlinked while they were away): tell them,
      -- once a minute at most
      local now = GetTime()
      if not unlinkTold[who] or now - unlinkTold[who] > 60 then
        unlinkTold[who] = now
        whisper("U" .. PROTO, who, "pair", true)
      end
    end
  end
end)

-- Each of these returns ok, and a sentence for the player
function P:Invite(name)
  name = (name or ""):match("^%s*(.-)%s*$")
  if name == "" then return false, "Type a guildmate's name: /goon partner <name>" end
  if not self:Ready() then return false, "Linking ledgers needs a guild: your partner has to be a guildmate." end
  local data = self:Data()
  local link = data.link
  if link and link.state == "linked" then
    return false, ("You're already linked with %s. Unlink first: /goon partner unlink"):format(link.name)
  end
  local member, online = Y:GuildMember(name)
  if not member then
    if Y.RefreshRoster then Y.RefreshRoster() end
    return false, ("%s isn't in your guild's roster. Check the spelling, or try again in a few seconds if you've just logged in."):format(name)
  end
  if member == me() then return false, "That's you. Name the guildmate you trade with." end
  if not online then return false, ("%s is offline. They have to be online to accept."):format(member) end
  -- they asked us already: this is the yes
  local asker = self:Asker(member)
  if asker then return self:Accept(asker) end
  if link and not same(link.name, member) then whisper("D" .. PROTO, link.name, "pair", true) end
  data.link = { name = member, state = "invited", at = time() }
  whisper("I" .. PROTO, member, "pair", true)
  changed()
  return true, ("Asked %s to link ledgers. It starts when they accept (they need Goonberg %s or newer)."):format(member, self.MIN_VERSION)
end

function P:Accept(name)
  local data = self:Data()
  local who = self:Asker(name)
  if not who then return false, "Nobody has asked to link ledgers with you." end
  if not self:Ready() then return false, "Linking ledgers needs a guild: your partner has to be a guildmate." end
  local link = data.link
  if link and not same(link.name, who) then
    if link.state == "linked" then
      return false, ("You're already linked with %s. Unlink first: /goon partner unlink"):format(link.name)
    end
    whisper("D" .. PROTO, link.name, "pair", true) -- the question we had out to someone else
  end
  data.invites[who] = nil
  data.link = { name = who, state = "linked", at = time() }
  self.session, self.sentThrough = nil, nil
  whisper("A" .. PROTO, who, "pair", true)
  changed()
  return true, ("Linked with %s. Your AH purchases and sales now show on each other's Ledger tab."):format(who)
end

function P:Decline(name)
  local data = self:Data()
  local who = self:Asker(name)
  if not who then return false, "Nobody has asked to link ledgers with you." end
  data.invites[who] = nil
  if self:Ready() then whisper("D" .. PROTO, who, "pair", true) end
  changed()
  return true, ("Declined %s."):format(who)
end

-- Ends the link, or takes back a question nobody answered yet
function P:Unlink()
  local data = self:Data()
  local link = data.link
  if not link then return false, "You aren't linked with anyone." end
  if self:Ready() then whisper((link.state == "linked" and "U" or "D") .. PROTO, link.name, "pair", true) end
  Y:DropTagged("ledger")
  data.link = nil
  self.session, self.sentThrough = nil, nil
  changed()
  if link.state ~= "linked" then return true, ("Took back your question to %s."):format(link.name) end
  return true, ("Unlinked from %s: their trades are gone from your Ledger tab, and yours no longer go to them."):format(link.name)
end

function P:SyncNow()
  if not self:Linked() then return false, "You aren't linked with anyone." end
  local now = GetTime()
  if self.lastSyncNow and now - self.lastSyncNow < 10 then return false, "Already asked a moment ago." end
  self.lastSyncNow = now
  if not self:Hello(true) then return false, "Can't reach your guild right now." end
  return true, ("Asked %s for their newest trades and sent yours. It only works while you're both online."):format(self:Link().name)
end

-- Your share of what the two of you make, in percent (the partner gets the rest).
-- Kept on your side only: it changes the "settling up" line, nothing that is sent.
function P:SetSplit(pct)
  local link = self:Link()
  if not link then return false, "You aren't linked with anyone." end
  pct = tonumber(pct)
  if not pct or pct < 0 or pct > 100 then return false, "Usage: /goon partner split 50  (your share in percent, 0 to 100)" end
  link.split = pct ~= 50 and pct or nil
  changed()
  return true, ("Settling up now splits what you make together %d / %d (you / %s)."):format(pct, 100 - pct, link.name)
end

function P:Split()
  local link = self:Link()
  return link and link.split or 50
end

-- ---------------------------------------------------------------------------
-- Both ledgers together, for the Ledger tab
-- ---------------------------------------------------------------------------
local function row(e, mine, who)
  local q = math.max(1, e.q or 1)
  local gross, fee = e.g or 0, e.f or 0
  local sale = e.k == "sale"
  return {
    mine = mine, who = who, t = e.t, kind = e.k, name = e.i, q = q,
    each = gross / q, gross = gross, fee = fee,
    total = sale and (gross - fee) or -gross, -- what it did to that player's gold
  }
end

-- Every AH purchase and sale since `since`: yours and, when linked, your partner's
function P:Trades(since)
  since = since or 0
  local rows = {}
  for _, e in ipairs(FI.Ledger:Data().entries) do
    if shareable(e) and e.t >= since then rows[#rows + 1] = row(e, true, "You") end
  end
  local link = self:Link()
  if link and link.state == "linked" then
    for _, e in ipairs(link.entries or {}) do
      if e.t >= since then rows[#rows + 1] = row(e, false, link.name) end
    end
  end
  return rows
end

local function side() return { spent = 0, sold = 0, fees = 0, net = 0, buys = 0, sales = 0 } end
local function count(s, r)
  if r.kind == "sale" then
    s.sold, s.fees, s.sales = s.sold + r.gross, s.fees + r.fee, s.sales + 1
  else
    s.spent, s.buys = s.spent + r.gross, s.buys + 1
  end
  s.net = s.net + r.total
end

-- { me, them, both }, each { spent, sold (before the AH cut), fees, net, buys, sales }
function P:Totals(rows)
  local t = { me = side(), them = side(), both = side() }
  for _, r in ipairs(rows) do
    count(r.mine and t.me or t.them, r)
    count(t.both, r)
  end
  return t
end

-- The same trades by item: what each of you paid and got for it
function P:Items(rows)
  local by, list = {}, {}
  for _, r in ipairs(rows) do
    local it = by[r.name]
    if not it then
      it = { name = r.name, mine = 0, theirs = 0, paid = 0, sold = 0, net = 0,
        myQty = 0, theirQty = 0, mySoldQty = 0, theirSoldQty = 0, mySold = 0, theirSold = 0 }
      by[r.name] = it
      list[#list + 1] = it
    end
    if r.kind == "sale" then
      it.sold = it.sold + r.total
      if r.mine then it.mySold, it.mySoldQty = it.mySold + r.total, it.mySoldQty + r.q
      else it.theirSold, it.theirSoldQty = it.theirSold + r.total, it.theirSoldQty + r.q end
    else
      it.paid = it.paid + r.gross
      if r.mine then it.mine, it.myQty = it.mine + r.gross, it.myQty + r.q
      else it.theirs, it.theirQty = it.theirs + r.gross, it.theirQty + r.q end
    end
    it.net = it.net + r.total
  end
  return list
end

-- Who owes whom so each ends up with their share of what you made together.
-- More than 0: you owe your partner that much; less: they owe you.
function P:Settle(totals, pct)
  pct = pct or self:Split()
  return totals.me.net - totals.both.net * pct / 100
end

-- ---------------------------------------------------------------------------
-- /goon partner
-- ---------------------------------------------------------------------------
function P:Status()
  local data = self:Data()
  local link = data.link
  if link and link.state == "linked" then
    local n = #(link.entries or {})
    FI:Print("Linked with %s since %s. You hold %s of their trades%s.", link.name, date("%b %d", link.at or time()),
      FI.Number(n), link.synced and (", updated " .. FI.Ago(link.synced)) or " (none yet: they arrive when you're both online)")
    FI:Print("Settling up splits what you make together %d / %d (you / %s): /goon partner split 60 changes your share.", self:Split(), 100 - self:Split(), link.name)
  elseif link then
    FI:Print("Waiting for %s to accept your question (asked %s). /goon partner unlink takes it back.", link.name, FI.Ago(link.at))
  else
    FI:Print("Not linked. /goon partner <guildmate> asks them to link ledgers: you both see each other's AH purchases and sales on the Ledger tab.")
  end
  local asker = self:Asker()
  if asker then FI:Print("%s wants to link ledgers with you: /goon partner accept  |  /goon partner decline", asker) end
end

function P:Command(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  local word, arg = rest:match("^(%S*)%s*(.-)$")
  word = (word or ""):lower()
  local ok, msg
  if word == "" or word == "status" then
    return self:Status()
  elseif word == "accept" then ok, msg = self:Accept(arg)
  elseif word == "decline" then ok, msg = self:Decline(arg)
  elseif word == "unlink" or word == "cancel" then ok, msg = self:Unlink()
  elseif word == "sync" then ok, msg = self:SyncNow()
  elseif word == "split" then ok, msg = self:SetSplit(arg)
  else ok, msg = self:Invite(rest) end
  if msg then FI:Print(msg) end
  return ok
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
FI:On("PLAYER_LOGIN", function()
  if CI and CI.RegisterAddonMessagePrefix then CI.RegisterAddonMessagePrefix(PREFIX) end
  P.ready = true
  local data, now = P:Data(), time()
  for who, t in pairs(data.invites) do
    if now - t > INVITE_KEEP then data.invites[who] = nil end
  end
  -- say hello once the guild roster is in: each side then sends what the other lacks
  C_Timer.After(22, function() P:Hello(true) end)
end)

-- New trades (you opened a mailbox) go to a partner who's been heard from since login.
-- If they've logged off meanwhile the whispers are dropped, and their next hello says
-- where to pick up.
FI:On("FI_LEDGER_CHANGED", function()
  if not P.sentThrough or not P:Linked() then return end
  FI:Debounce("partnerSend", 8, function()
    if not P.sentThrough or not P:Linked() then return end
    local d = P:Numbered()
    if (d.pairSeq or 0) > P.sentThrough then P:SendFrom(P.sentThrough) end
  end)
end)
