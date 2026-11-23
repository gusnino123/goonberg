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
--   W1:<a>-<b>,...         the pauses: trades from a up to b (0: still paused) don't count.
--                          Sent with each hello and on pause / resume; older clients
--                          ignore it
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
local PAUSE_AHEAD_MAX = 7200     -- a pause from the partner can't start further ahead than this (0.43.0/0.43.1 started an hour late)
local PAUSES_SENT = 10           -- the newest pauses each W message carries
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
--            epoch, have, entries, synced,   -- the partner's trades we hold
--            off = { { a, b }, ... },        -- pauses (P:Pause), shared with the partner
--            paid = { { t, d = "out"|"in", g, via = "trade"|"mail"|"typed" }, ... } }
--                                            -- gold between the two of you (P:Payments)
--   invites = { [name] = when they asked }
--   only = { [lowercase item name] = item name }  -- the items the totals count (none: all)
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

-- ---------------------------------------------------------------------------
-- Pauses: stretches of time when you aren't working together. Trades in a pause
-- (yours and your partner's) are left out of the Ledger tab on both sides. A pause
-- starts the moment it's pressed and resuming counts again at once. (A partner on
-- 0.43.0 or 0.43.1 sends pauses that start an hour after their press.) A pause is never deleted, only closed: one
-- resumed before it began becomes empty (b == a), so both sides can merge their lists.
-- ---------------------------------------------------------------------------
local function pauses(link)
  link.off = link.off or {}
  return link.off
end

function P:SendPauses()
  local link = self:Link()
  if not link or link.state ~= "linked" or not self:Ready() then return end
  local list = pauses(link)
  local parts = {}
  for i = math.max(1, #list - PAUSES_SENT + 1), #list do
    parts[#parts + 1] = b36(list[i].a) .. "-" .. b36(list[i].b or 0)
  end
  whisper("W" .. PROTO .. ":" .. table.concat(parts, ","), link.name, "pair", true)
end

-- Their list into ours: the same pause (same start) closed on either side is closed
local function onPauses(link, body)
  local list, grew = pauses(link), false
  local byStart = {}
  for _, w in ipairs(list) do byStart[w.a] = w end
  local now = time()
  for a36, b36s in body:gmatch("(%w+)%-(%w+)") do
    local a, b = n36(a36), n36(b36s)
    if a and b and a < now + PAUSE_AHEAD_MAX and (b == 0 or b >= a) then
      local w = byStart[a]
      if not w then
        w = { a = a, b = b ~= 0 and b or nil }
        list[#list + 1], byStart[a], grew = w, w, true
      elseif b ~= 0 and (not w.b or b < w.b) then
        w.b, grew = b, true
      end
    end
  end
  if grew then
    table.sort(list, function(x, y) return x.a < y.a end)
    changed()
  end
end

-- The open pause, if any: { a = when it starts (maybe still ahead), b = nil }
function P:Paused()
  local link = self:Link()
  if not link or link.state ~= "linked" then return nil end
  for _, w in ipairs(pauses(link)) do
    if not w.b then return w end
  end
end

-- Is a trade at time t in a pause?
function P:InPause(t)
  local link = self:Link()
  if not link or link.state ~= "linked" or not link.off then return false end
  for _, w in ipairs(link.off) do
    if t >= w.a and (not w.b or t < w.b) then return true end
  end
  return false
end

function P:Pause()
  local link = self:Link()
  if not link or link.state ~= "linked" then return false, "You aren't linked with anyone." end
  local open = self:Paused()
  if open then return false, ("Already paused from %s. /goon partner resume counts trades again."):format(date("%H:%M", open.a)) end
  local a = time()
  local list = pauses(link)
  list[#list + 1] = { a = a }
  self:SendPauses()
  changed()
  return true, ("Paused: trades from now on don't count, for you and %s. Resume when you work together again."):format(link.name)
end

function P:Resume()
  local link = self:Link()
  if not link or link.state ~= "linked" then return false, "You aren't linked with anyone." end
  local now, any, began = time(), false, false
  for _, w in ipairs(pauses(link)) do
    if not w.b then
      w.b = math.max(w.a, now)
      any, began = true, began or now > w.a
    end
  end
  if not any then return false, "You aren't paused." end
  self:SendPauses()
  changed()
  if not began then return true, ("Pause called off before it began: every trade counts, for you and %s."):format(link.name) end
  return true, ("Resumed: trades from now on count again, for you and %s."):format(link.name)
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
  P:SendPauses()
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
  elseif kind == "H" or kind == "S" or kind == "E" or kind == "W" then
    if partner and link.state == "linked" then
      if kind == "H" then onHello(body)
      elseif kind == "S" then onStart(link, body)
      elseif kind == "E" then onEnd(link, body)
      else onPauses(link, body) end
    elseif not partner and kind ~= "E" and kind ~= "W" then
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
-- Which items the totals count. Empty means every item. Like the split it is kept
-- on your side only: the lists still show every trade, and nothing is sent.
-- ---------------------------------------------------------------------------
-- an item link ("|cff...|Hitem:...|h[Name]|h|r") or a typed name, as the ledger's name
local function itemName(s)
  s = tostring(s or "")
  s = s:match("%[(.-)%]") or s
  return (s:gsub("|", ""):match("^%s*(.-)%s*$"))
end

function P:Only()
  local d = self:Data()
  if d.only and next(d.only) == nil then d.only = nil end
  return d.only
end

-- Is this item counted in the totals?
function P:Counted(name)
  local only = self:Only()
  return not only or (name ~= nil and only[tostring(name):lower()] ~= nil)
end

-- The picked items, sorted
function P:OnlyList()
  local list = {}
  for _, name in pairs(self:Only() or {}) do list[#list + 1] = name end
  table.sort(list)
  return list
end

-- Adds an item to the counted ones, or takes it out again
function P:ToggleOnly(name)
  name = itemName(name)
  if name == "" then return false, "Usage: /goon partner only <item>  (again to take it out; /goon partner only clear counts every item)" end
  local d = self:Data()
  d.only = d.only or {}
  local key = name:lower()
  local msg
  if d.only[key] then
    d.only[key] = nil
    msg = next(d.only) and ("%s is no longer counted in the Ledger totals."):format(name)
      or ("%s taken out: the Ledger totals count every item again."):format(name)
  else
    d.only[key] = name
    msg = ("The Ledger totals now count only %s."):format(table.concat(self:OnlyList(), ", "))
  end
  self:Only()
  changed()
  return true, msg
end

function P:ClearOnly()
  if not self:Only() then return true, "The Ledger totals already count every item." end
  self:Data().only = nil
  changed()
  return true, "The Ledger totals count every item again."
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

-- Every AH purchase and sale since `since`: yours and, when linked, your partner's,
-- except those in a pause. The second result is how many a pause left out.
function P:Trades(since)
  since = since or 0
  local rows, paused = {}, 0
  local function add(e, mine, who)
    if e.t < since then return end
    if self:InPause(e.t) then paused = paused + 1 else rows[#rows + 1] = row(e, mine, who) end
  end
  for _, e in ipairs(FI.Ledger:Data().entries) do
    if shareable(e) then add(e, true, "You") end
  end
  local link = self:Link()
  if link and link.state == "linked" then
    for _, e in ipairs(link.entries or {}) do add(e, false, link.name) end
  end
  return rows, paused
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

-- { me, them, both }, each { spent, sold (before the AH cut), fees, net, buys, sales },
-- over the counted items only (P:Counted)
function P:Totals(rows)
  local t = { me = side(), them = side(), both = side() }
  for _, r in ipairs(rows) do
    if self:Counted(r.name) then
      count(r.mine and t.me or t.them, r)
      count(t.both, r)
    end
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

-- ---------------------------------------------------------------------------
-- Gold between the two of you: trade window gold, mailed gold and amounts you type.
-- Each side writes down what it sees itself (both see a trade; the sender sees a
-- mail go, the receiver sees its gold taken), so nothing about payments is sent.
-- Pauses and the item pick don't apply: a payment always settles.
-- ---------------------------------------------------------------------------
local PAID_MAX = 500

function P:AddPayment(dir, copper, via, t)
  local link = self:Link()
  if not link or link.state ~= "linked" then return false end
  copper = math.floor(tonumber(copper) or 0)
  if copper <= 0 or (dir ~= "out" and dir ~= "in") then return false end
  link.paid = link.paid or {}
  link.paid[#link.paid + 1] = { t = t or time(), d = dir, g = copper, via = via or "typed" }
  while #link.paid > PAID_MAX do table.remove(link.paid, 1) end
  changed()
  return true
end

-- The payments since `since`, oldest first, and what they add to what you owe:
-- gold you gave counts against it, gold you got adds to it
function P:Payments(since)
  local link = self:Link()
  local list, out, inn = {}, 0, 0
  if not link or link.state ~= "linked" then return list, 0, 0 end
  for _, p in ipairs(link.paid or {}) do
    if p.t >= (since or 0) then
      list[#list + 1] = p
      if p.d == "out" then out = out + p.g else inn = inn + p.g end
    end
  end
  return list, out, inn
end

-- Who owes whom so each ends up with their share of what you made together, after
-- the gold already passed between you. More than 0: you owe your partner that much;
-- less: they owe you.
function P:Settle(totals, pct, since)
  pct = pct or self:Split()
  local _, out, inn = self:Payments(since)
  return totals.me.net - totals.both.net * pct / 100 - out + inn
end

-- /goon partner paid 500g | got 500g: a payment the addon didn't see
function P:TypedPayment(dir, text)
  local link = self:Link()
  if not link or link.state ~= "linked" then return false, "You aren't linked with anyone." end
  local copper = FI.ParseMoney(text)
  if not copper or copper <= 0 then
    return false, ("Usage: /goon partner %s 500g  (gold you %s %s outside a trade or mail)"):format(dir == "out" and "paid" or "got", dir == "out" and "gave" or "got from", link.name)
  end
  self:AddPayment(dir, copper, "typed")
  return true, (dir == "out" and "Noted: you paid %s %s." or "Noted: %s paid you %s."):format(link.name, FI.Coins(copper))
end

function P:UndoPayment()
  local link = self:Link()
  local p = link and link.state == "linked" and link.paid and link.paid[#link.paid]
  if not p then return false, "No payments to take back." end
  table.remove(link.paid)
  changed()
  return true, ("Took back the last payment: %s %s %s on %s."):format(p.d == "out" and "you paid" or "you got", FI.Coins(p.g), p.d == "out" and "to " .. link.name or "from " .. link.name, date("%b %d %H:%M", p.t))
end

function P:PrintPayments()
  local link = self:Link()
  if not link or link.state ~= "linked" then return FI:Print("You aren't linked with anyone.") end
  local list, out, inn = self:Payments(0)
  if #list == 0 then
    return FI:Print("No gold between you and %s yet. Trades and mail with them are noted by themselves; /goon partner paid 500g notes one the addon didn't see.", link.name)
  end
  FI:Print("Gold between you and %s: you paid %s, you got %s.", link.name, FI.Coins(out), FI.Coins(inn))
  for i = math.max(1, #list - 9), #list do
    local p = list[i]
    FI:Print("  %s  %s %s  (%s)", date("%b %d %H:%M", p.t), p.d == "out" and "paid" or "got", FI.Coins(p.g), p.via)
  end
  FI:Print("/goon partner payments undo takes back the last one.")
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
    local only = self:OnlyList()
    if #only > 0 then FI:Print("The totals count only %s: /goon partner only clear counts every item.", table.concat(only, ", ")) end
    local open = self:Paused()
    if open then
      FI:Print("%s from %s: later trades don't count until /goon partner resume.", time() < open.a and "Pausing" or "Paused", date("%b %d %H:%M", open.a))
    end
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
  elseif word == "paid" then ok, msg = self:TypedPayment("out", arg)
  elseif word == "got" then ok, msg = self:TypedPayment("in", arg)
  elseif word == "payments" then
    if arg:lower() == "undo" then ok, msg = self:UndoPayment() else return self:PrintPayments() end
  elseif word == "pause" then ok, msg = self:Pause()
  elseif word == "resume" then ok, msg = self:Resume()
  elseif word == "only" then
    if arg:lower() == "clear" or arg:lower() == "all" then ok, msg = self:ClearOnly()
    elseif arg == "" then
      local only = self:OnlyList()
      msg = #only > 0 and ("The Ledger totals count only %s. /goon partner only <item> adds or takes one out; /goon partner only clear counts every item."):format(table.concat(only, ", "))
        or "The Ledger totals count every item. /goon partner only <item> counts only the items you pick (or click them on the Ledger tab's By item view)."
      ok = true
    else ok, msg = self:ToggleOnly(arg) end
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

-- Gold between partners, as it happens
-- The trade window: the amounts each side has put in, kept up to date while it's open,
-- written down when the game says the trade went through
local trade
local function readTrade()
  if not trade then return end
  trade.give = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
  trade.take = GetTargetTradeMoney and GetTargetTradeMoney() or 0
end
FI:On("TRADE_SHOW", function()
  local link = P:Link()
  local who = UnitName("NPC")
  trade = (link and link.state == "linked" and same(who, link.name)) and { give = 0, take = 0 } or nil
end)
FI:On("TRADE_MONEY_CHANGED", readTrade)
FI:On("TRADE_PLAYER_ITEM_CHANGED", readTrade)
FI:On("TRADE_TARGET_ITEM_CHANGED", readTrade)
FI:On("TRADE_ACCEPT_UPDATE", readTrade)
FI:On("UI_INFO_MESSAGE", function(_, kind, msg)
  if not trade then return end
  local done = (msg ~= nil and msg == _G.ERR_TRADE_COMPLETE)
    or (kind ~= nil and _G.LE_GAME_ERR_TRADE_COMPLETE ~= nil and kind == _G.LE_GAME_ERR_TRADE_COMPLETE)
  if not done then return end
  local t = trade
  trade = nil
  local name = P:Link() and P:Link().name or "your partner"
  if t.give > 0 and P:AddPayment("out", t.give, "trade") then
    FI:Print("Noted for Settling Up: you traded %s %s.", name, FI.Coins(t.give))
  end
  if t.take > 0 and P:AddPayment("in", t.take, "trade") then
    FI:Print("Noted for Settling Up: %s traded you %s.", name, FI.Coins(t.take))
  end
end)
-- (a trade that's cancelled never sends the complete message; the next window starts over)

-- Mail: gold you send them counts when the game says the mail went; gold from them
-- counts when you take it (a returned mail of yours counts as gold coming back)
local sending, lastSetMoney
if hooksecurefunc and _G.SetSendMailMoney then
  hooksecurefunc("SetSendMailMoney", function(m) lastSetMoney = tonumber(m) end)
end
if hooksecurefunc and _G.SendMail then
  hooksecurefunc("SendMail", function(to)
    local link = P:Link()
    -- (this runs after the send call: the amount set on the mail backs up the live one)
    local money = math.max(GetSendMailMoney and GetSendMailMoney() or 0, lastSetMoney or 0)
    lastSetMoney = nil
    local cod = GetSendMailCOD and GetSendMailCOD() or 0
    sending = (link and link.state == "linked" and money > 0 and cod == 0 and same(short(to), link.name)) and money or nil
  end)
end
FI:On("MAIL_SEND_SUCCESS", function()
  local money = sending
  sending = nil
  if money and P:AddPayment("out", money, "mail") then
    FI:Print("Noted for Settling Up: you mailed %s %s.", P:Link().name, FI.Coins(money))
  end
end)
FI:On("MAIL_FAILED", function() sending = nil end)

-- the inbox as last seen: this runs after the take call, when the mail may already
-- show no gold
local inbox, taken = {}, {}
local function header(index)
  local _, _, sender, subject, money, cod, daysLeft = GetInboxHeaderInfo(index)
  return { sender = sender, subject = subject, money = money or 0, cod = cod or 0, daysLeft = daysLeft or 0 }
end
FI:On("MAIL_INBOX_UPDATE", function()
  inbox = {}
  if not GetInboxNumItems or not GetInboxHeaderInfo then return end
  for i = 1, (GetInboxNumItems()) do inbox[i] = header(i) end
end)
local function taking(index)
  local link = P:Link()
  if not link or link.state ~= "linked" or not GetInboxHeaderInfo then return end
  local h = header(index)
  if h.money <= 0 and inbox[index] then h = inbox[index] end
  local sender, subject, money, cod, daysLeft = h.sender, h.subject, h.money, h.cod, h.daysLeft
  if not money or money <= 0 or (cod or 0) > 0 or not same(short(sender), link.name) then return end
  -- the same mail clicked twice before the game empties it is one payment
  local key = table.concat({ tostring(sender), tostring(subject), money, ("%.3f"):format(daysLeft or 0) }, "|")
  local now = GetTime()
  if taken[key] and now - taken[key] < 30 then return end
  taken[key] = now
  if P:AddPayment("in", money, "mail") then
    FI:Print("Noted for Settling Up: %s mailed you %s.", link.name, FI.Coins(money))
  end
end
if hooksecurefunc then
  if _G.TakeInboxMoney then hooksecurefunc("TakeInboxMoney", taking) end
  if _G.AutoLootMailItem then hooksecurefunc("AutoLootMailItem", taking) end
end
