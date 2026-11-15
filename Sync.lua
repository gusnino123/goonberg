-- Goonberg Terminal: guild sync
-- Your scans go to guildmates running Goonberg, and theirs come to you, through the
-- game's addon messages (guild channel). Only your own scans are sent; prices you
-- received are never passed on, so nothing loops. Newcomers with little history ask
-- once at login and one guildmate whispers them up to 21 days of daily prices.
-- At login everyone also asks for the guild's newest scan, so Deals can fill without
-- waiting for someone to open the AH.
---@type string, GoonbergTerminal
local _, FI = ...
---@class GT.Sync
local Y = { peers = {}, sessions = {}, sent = {}, greeted = {} }
FI.Sync = Y
local PREFIX = "GoonbergSync"
local PROTO = "1"
-- Kept deliberately light (Blizzard's addon policy: no harm to realm performance):
local MAX_ITEMS = 600          -- per broadcast scan, busiest first, changed items only
local RESEND_AFTER = 2 * 3600  -- unchanged items are re-sent at most every 2 hours
local HISTORY_ITEMS = 250      -- items sent to a newcomer
local HISTORY_DAYS = 21
local MSG_MAX = 250
local H

local CI = C_ChatInfo
local function canSync()
  return Y.ready and CI and CI.SendAddonMessage and FI.settings and FI.settings.guildSync ~= false and IsInGuild()
end

-- ---------------------------------------------------------------------------
-- Compact numbers: base 36 keeps messages short
-- ---------------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(n or 0)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = DIGITS:sub(r + 1, r + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end
local function n36(s) return s and tonumber(s, 36) end
Y.b36, Y.n36 = b36, n36

-- ---------------------------------------------------------------------------
-- Sending: a queue drained gently (the game throttles addon messages)
-- ---------------------------------------------------------------------------
local queue, tokens = {}, 8
-- Whispers (history and catch-up answers go to one guildmate) must stop the moment
-- that guildmate logs off: every whisper to someone offline makes the game print
-- "No player named ... is currently playing", so a half-sent answer used to spam it.
local gone = {}      -- name -> true: offline, don't whisper them
local whispered = {} -- name -> time of our last addon whisper to them
local function baseName(full) return full and (full:match("^([^%-]+)") or full) end
function Y:DropWhispers(name)
  name = baseName(name)
  if not name then return 0 end
  local n = 0
  for i = #queue, 1, -1 do
    if queue[i][2] == "WHISPER" and baseName(queue[i][3]) == name then table.remove(queue, i); n = n + 1 end
  end
  return n
end
-- the guild roster, when the game has it: is this guildmate online?
local function offlineInGuild(name)
  if not (IsInGuild and IsInGuild()) or not GetNumGuildMembers or not GetGuildRosterInfo then return false end
  local total = GetNumGuildMembers()
  if not total or total == 0 then return false end
  for i = 1, total do
    local full, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if full and baseName(full) == name then return not online end
  end
  return false -- not in the roster we have: let the game decide
end
local sender = CreateFrame("Frame")
sender:Hide()
sender.acc = 0
sender:SetScript("OnUpdate", function(self, e)
  self.acc = self.acc + e
  if self.acc >= 1 then
    tokens = math.min(8, tokens + math.floor(self.acc))
    self.acc = self.acc % 1
  end
  while tokens >= 1 and queue[1] do
    local m = table.remove(queue, 1)
    local to = m[2] == "WHISPER" and baseName(m[3])
    if to and (gone[to] or offlineInGuild(to)) then
      gone[to] = true
      Y:DropWhispers(to) -- they left: drop the rest of their answer, send nothing
    else
      tokens = tokens - 1
      if to then whispered[to] = GetTime() end
      CI.SendAddonMessage(PREFIX, m[1], m[2], m[3])
    end
  end
  if not queue[1] then self:Hide() end
end)

-- "X has gone offline." (guild) / "No player named 'X' is currently playing."
local function sysPattern(fmt)
  if not fmt then return nil end
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)")
  return "^" .. p .. "$"
end
local OFFLINE = sysPattern(_G.ERR_FRIEND_OFFLINE_S or "%s has gone offline.")
local NOT_FOUND = sysPattern(_G.ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.")
local ONLINE = sysPattern(_G.ERR_FRIEND_ONLINE_S or "%s has come online.")
local function strip(name) return baseName((name or ""):gsub("|H.-|h%[?(.-)%]?|h", "%1")) end
FI:On("CHAT_MSG_SYSTEM", function(_, msg)
  if type(msg) ~= "string" then return end
  local who = OFFLINE and msg:match(OFFLINE)
  if not who and NOT_FOUND then who = msg:match(NOT_FOUND) end
  if who then
    who = strip(who)
    gone[who] = true
    Y:DropWhispers(who)
    return
  end
  local back = ONLINE and msg:match(ONLINE)
  if back then gone[strip(back)] = nil end
end)
-- Hide "No player named ..." when it's about our own addon whispers (a few seconds
-- after we sent them one); for your own typed whispers it still shows.
if ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    local who = NOT_FOUND and type(msg) == "string" and msg:match(NOT_FOUND)
    who = who and strip(who)
    if who and whispered[who] and GetTime() - whispered[who] < 10 then return true end
    return false
  end)
end

local function send(msg, channel, target, tag)
  queue[#queue + 1] = { msg, channel or "GUILD", target, tag }
  sender:Show()
end

function Y:QueueLength() return #queue end

-- Packs "entry;entry;..." into messages under the size limit
local function packed(head, entries, channel, target, tag)
  local cur = head
  for _, e in ipairs(entries) do
    if #cur + #e + 1 > MSG_MAX then
      send(cur, channel, target, tag)
      cur = head
    end
    cur = (cur == head) and (cur .. e) or (cur .. ";" .. e)
  end
  if cur ~= head then send(cur, channel, target, tag) end
end

-- ---------------------------------------------------------------------------
-- Broadcasting your scan
-- ---------------------------------------------------------------------------
-- Guildmates running Goonberg we've heard from in the last day
function Y:ActivePeers()
  local n, now = 0, time()
  for _, t in pairs(self.peers) do if now - t < 86400 then n = n + 1 end end
  return n
end

-- Has this item changed enough since we last sent it to be worth sending again?
local function changed(id, it, t)
  local last = Y.sent[id]
  if not last or t - last.t >= RESEND_AFTER then return true end
  if last.mkt > 0 and math.abs(it.mkt - last.mkt) / last.mkt >= 0.02 then return true end
  return math.abs((it.qty or 0) - last.qty) >= math.max(2, last.qty * 0.10)
end

-- The items of scan t worth sending, busiest first. Each comes back as the entry
-- to send and the item ID. `keep` filters further (nil = all of them).
local function scanEntries(t, keep)
  local list = {}
  for id, it in pairs(FI:Realm().items) do
    if it.seen == t and it.mkt and (it.qty or 0) > 0 and (not keep or keep(id, it)) then list[#list + 1] = { id, it } end
  end
  table.sort(list, function(a, b) return a[2].mkt * a[2].qty > b[2].mkt * b[2].qty end)
  local entries, ids = {}, {}
  for i = 1, math.min(MAX_ITEMS, #list) do
    local id, it = list[i][1], list[i][2]
    entries[i] = table.concat({ b36(id), b36(it.mkt), b36(it.min or it.mkt), b36(it.qty), b36(it.cnt or 1) }, ",")
    ids[i] = id
  end
  return entries, ids
end

local function sendScan(t, entries, channel, target, tag)
  local tt = b36(t)
  send("S" .. PROTO .. ":" .. tt .. ":" .. b36(#entries), channel, target, tag)
  packed("B" .. tt .. ":", entries, channel, target, tag)
  send("E" .. tt, channel, target, tag)
end

function Y:BroadcastScan(t)
  if not canSync() then return end
  -- nobody in the guild runs Goonberg: send nothing at all
  if self:ActivePeers() == 0 then return end
  local realm = FI:Realm()
  local entries, ids = scanEntries(t, function(id, it) return changed(id, it, t) end)
  for _, id in ipairs(ids) do
    local it = realm.items[id]
    self.sent[id] = { mkt = it.mkt, qty = it.qty or 0, t = t }
  end
  if #entries == 0 then return end
  -- a newer scan replaces one that's still going out
  for i = #queue, 1, -1 do if queue[i][4] == "scan" then table.remove(queue, i) end end
  sendScan(t, entries, "GUILD", nil, "scan")
  self.lastSent = t
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
local function snapshot(realm)
  local prev = {}
  for id, it in pairs(realm.items) do
    if it.mkt and it.seen == realm.lastScan then prev[id] = it.mkt end
  end
  return prev
end

-- The newest scan we hold listings for. A catch-up moves lastScan but brings no
-- listings, so it doesn't count. (Saved data from before liveScan existed: lastScan,
-- if its items still have listings.)
local function hasListings(realm, t)
  for _, it in pairs(realm.items) do
    if it.seen == t and it.min and (it.qty or 0) > 0 then return true end
  end
  return false
end

local function liveScan(realm)
  if realm.liveScan then return realm.liveScan end
  local t = realm.lastScan or 0
  return hasListings(realm, t) and t or 0
end
Y.LiveScan = liveScan

-- A scan arrives as S (start), B (batches), E (end). `key` tells sessions apart;
-- `reply` marks the scan we asked for at login (whispered, see below).
local function onStart(key, rest, reply)
  local proto, tt = rest:match("^(%d+):(%w+)")
  if proto ~= PROTO then return end
  local t = n36(tt)
  local realm = FI:Realm()
  -- ignore scans older than what we already have. A login catch-up may already have
  -- brought this scan's prices (but not its listings), so the reply is judged by
  -- the listings we hold.
  local have = reply and liveScan(realm) or (realm.lastScan or 0)
  if not t or t <= have or t > time() + 300 then return end
  Y.sessions[key] = { t = t, prev = snapshot(realm), items = 0, reply = reply }
end

local function onBatch(key, rest)
  local tt, body = rest:match("^(%w+):(.*)$")
  local s = Y.sessions[key]
  if not s or not tt or n36(tt) ~= s.t then return end
  local realm = FI:Realm()
  for entry in body:gmatch("[^;]+") do
    local a, b, c, d, e = entry:match("^(%w+),(%w+),(%w+),(%w+),(%w+)$")
    local id, mkt, mn, qty, cnt = n36(a), n36(b), n36(c), n36(d), n36(e)
    if id and mkt and mkt > 0 and qty then
      local ok = H.RecordShared(realm, id, s.t, mkt, mn, qty, cnt)
      local it = realm.items[id]
      if not ok and s.reply and it and (it.seen or 0) <= s.t then
        -- the catch-up got here first with this point: add the listings it lacked
        it.mkt, it.min, it.qty, it.cnt, it.seen, it.shared, it.src = mkt, mn, qty, cnt, s.t, true, nil
        ok = true
      end
      if ok then s.items = s.items + 1 end
    end
  end
end

local function onEnd(key, from, rest)
  local s = Y.sessions[key]
  Y.sessions[key] = nil
  if not s or n36(rest) ~= s.t or s.items == 0 then return end
  local realm = FI:Realm()
  local newer = s.t > (realm.lastScan or 0)
  if newer then
    realm.lastScan = s.t
    realm.scans = (realm.scans or 0) + 1
    realm.scanDays = realm.scanDays or {}
    realm.scanDays[math.floor(s.t / 86400)] = true
    H.UpdateIndex(realm, s.prev, s.t)
  end
  if newer or s.reply then
    realm.lastShared = { from = from, t = s.t, items = s.items }
    H.cache = nil
    if s.reply then Y.wantScan = false end
    FI:Fire("FI_SCAN_DONE", s.t, from)
  end
end

-- ---------------------------------------------------------------------------
-- Newest scan at login: whoever holds the guild's newest scan whispers it to you
-- ---------------------------------------------------------------------------
function Y:RequestScan(manual)
  if not canSync() then
    if manual then FI:Print("Guild sync needs a guild (and /goon sync on).") end
    return
  end
  self.wantScan = true
  send("N" .. PROTO .. ":" .. b36(liveScan(FI:Realm())))
  if manual then FI:Print("Asked your guild for its newest scan...") end
end

-- ---------------------------------------------------------------------------
-- History for newcomers
-- ---------------------------------------------------------------------------
-- How much history we have: number of items with at least 3 days of data
local function historyDepth()
  local realm, now, n = FI:Realm(), time(), 0
  for _, it in pairs(realm.items) do
    local h = it.h
    if h and h[1] and now - h[1] > 3 * 86400 then n = n + 1 end
  end
  return n
end

function Y:RequestHistory(manual)
  if not canSync() then
    if manual then FI:Print("Guild sync needs a guild (and /goon sync on).") end
    return
  end
  self.wantHistory = true
  send("Q" .. PROTO)
  if manual then FI:Print("Asked your guild for price history...") end
end

-- Daily closes of our busiest items, one message per item
local function sendHistory(target)
  local realm, now = FI:Realm(), time()
  local list = {}
  for id, it in pairs(realm.items) do
    if it.mkt and it.h and it.h[1] then list[#list + 1] = { id, it } end
  end
  table.sort(list, function(a, b) return a[2].mkt * (a[2].qty or 0) > b[2].mkt * (b[2].qty or 0) end)
  local sent = 0
  for i = 1, math.min(HISTORY_ITEMS, #list) do
    local id, it = list[i][1], list[i][2]
    local days, h = {}, it.h
    for k = 1, #h, 4 do
      if h[k + 1] > 0 and now - h[k] <= HISTORY_DAYS * 86400 then
        days[math.floor(h[k] / 86400)] = { h[k + 1], h[k + 2] } -- last point of each day wins
      end
    end
    local entries = {}
    for d, v in pairs(days) do entries[#entries + 1] = b36(d) .. "," .. b36(v[1]) .. "," .. b36(v[2]) end
    if #entries > 0 then
      table.sort(entries)
      packed("H" .. b36(id) .. ":", entries, "WHISPER", target)
      sent = sent + 1
    end
  end
  send("F" .. b36(sent), "WHISPER", target)
end

-- One guildmate answers each request: everyone who could waits a moment, the one
-- whose wait ends first says so ("R"), and the others stand down. Fresher data
-- means a shorter wait, so the best-informed guildmate usually answers.
local responding = {}
local function answer(kind, from, fn, age)
  local key = kind .. ":" .. from
  responding[key] = false
  age = age or (time() - (FI:Realm().lastScan or 0))
  local wait = 1 + math.min(5, age / 3600) + math.random() * 0.5
  C_Timer.After(wait, function()
    if responding[key] == false then
      responding[key] = true
      send("R" .. key)
      fn()
    end
  end)
end

local function onRequest(from)
  if historyDepth() < 5 then return end
  answer("h", from, function() sendHistory(from) end)
end

local function onResponding(rest)
  -- someone else is already answering this request
  if responding[rest] == false then responding[rest] = nil end
end

-- Someone logged in and wants the newest scan: send ours if it's newer than theirs.
-- Whoever scanned it answers before guildmates who only received it.
local function onScanRequest(from, rest)
  local proto, h36 = rest:match("^(%d+):(%w+)$")
  local have = n36(h36)
  if proto ~= PROTO or not have then return end
  local realm = FI:Realm()
  local t = liveScan(realm)
  if t <= have or not hasListings(realm, t) then return end
  local relayed = realm.lastShared and realm.lastShared.t == t
  answer("n", from, function()
    sendScan(t, (scanEntries(t, function(_, it) return it.min end)), "WHISPER", from, "reply")
  end, time() - t + (relayed and 1800 or 0))
end

-- ---------------------------------------------------------------------------
-- Catch-up: everything the guild saw since you logged off
-- ---------------------------------------------------------------------------
local CATCHUP_ITEMS, CATCHUP_POINTS = 250, 12

function Y:RequestCatchup(since, manual)
  if not canSync() then return end
  self.wantCatchup = true
  self.catchSince = since
  send("C" .. PROTO .. ":" .. b36(since))
  if manual then FI:Print("Asked your guild for prices since %s.", FI.Ago(since)) end
end

-- Points newer than `since` for our busiest items, at most 24 per item
local function sendCatchup(target, since)
  local realm = FI:Realm()
  local list = {}
  for id, it in pairs(realm.items) do
    if it.mkt and it.seen and it.seen > since then list[#list + 1] = { id, it } end
  end
  table.sort(list, function(a, b) return a[2].mkt * (a[2].qty or 0) > b[2].mkt * (b[2].qty or 0) end)
  local sent = 0
  for i = 1, math.min(CATCHUP_ITEMS, #list) do
    local id, h = list[i][1], list[i][2].h
    local pts = {}
    for k = 1, #h, 4 do
      if h[k] > since and h[k + 1] > 0 then pts[#pts + 1] = { h[k], h[k + 1], h[k + 2] } end
    end
    if #pts > 0 then
      -- thin to one point per slot so long absences stay a few messages per item
      local span = pts[#pts][1] - since
      local width = math.max(3600, span / CATCHUP_POINTS)
      local keep, lastSlot = {}, nil
      for _, p in ipairs(pts) do
        local slot = math.floor((p[1] - since) / width)
        if slot == lastSlot then keep[#keep] = p else keep[#keep + 1] = p end
        lastSlot = slot
      end
      local entries = {}
      for _, p in ipairs(keep) do entries[#entries + 1] = b36(p[1]) .. "," .. b36(p[2]) .. "," .. b36(p[3]) end
      packed("K" .. b36(id) .. ":", entries, "WHISPER", target)
      sent = sent + 1
    end
  end
  send("G" .. b36(sent), "WHISPER", target)
end

local function onCatchupRequest(from, rest)
  local proto, s36 = rest:match("^(%d+):(%w+)$")
  local since = n36(s36)
  if proto ~= PROTO or not since then return end
  -- only answer if we actually saw something after they left
  if (FI:Realm().lastScan or 0) <= since then return end
  answer("c", from, function() sendCatchup(from, since) end)
end

local function onCatchup(from, rest)
  if not Y.wantCatchup then return end
  local id36, body = rest:match("^(%w+):(.*)$")
  local id = n36(id36)
  if not id then return end
  local points = {}
  for entry in body:gmatch("[^;]+") do
    local t, p, q = entry:match("^(%w+),(%w+),(%w+)$")
    t, p, q = n36(t), n36(p), n36(q)
    -- only the gap we asked about, and nothing from the future
    if t and p and p > 0 and t > (Y.catchSince or 0) and t <= time() + 300 then points[#points + 1] = { t, p, q } end
  end
  table.sort(points, function(a, b) return a[1] < b[1] end)
  local realm = FI:Realm()
  local added = H.Merge(realm, id, points, { fine = true })
  if added > 0 then
    Y.catchItems = (Y.catchItems or 0) + 1
    Y.catchPoints = (Y.catchPoints or 0) + added
    local newest = points[#points][1]
    if newest > (Y.catchNewest or 0) then Y.catchNewest = newest end
  end
end

local function onCatchupDone(from)
  if not Y.wantCatchup then return end
  Y.wantCatchup = false
  local realm = FI:Realm()
  if (Y.catchItems or 0) > 0 then
    if (Y.catchNewest or 0) > (realm.lastScan or 0) then
      realm.lastScan = Y.catchNewest
      realm.lastShared = { from = from, t = Y.catchNewest, items = Y.catchItems }
    end
    H.cache = nil
    FI:Print("Caught up: %s price points for %s items from %s, covering the time you were away.",
      FI.Number(Y.catchPoints), FI.Number(Y.catchItems), from)
    FI:Fire("FI_DATA_MERGED", from)
  end
  Y.catchItems, Y.catchPoints, Y.catchNewest = 0, 0, 0
end

local function onHistory(from, rest)
  if not Y.wantHistory then return end
  local id36, body = rest:match("^(%w+):(.*)$")
  local id = n36(id36)
  if not id then return end
  local points = {}
  for entry in body:gmatch("[^;]+") do
    local d, p, q = entry:match("^(%w+),(%w+),(%w+)$")
    d, p, q = n36(d), n36(p), n36(q)
    if d and p and p > 0 then points[#points + 1] = { d * 86400 + 43200, p, q } end
  end
  table.sort(points, function(a, b) return a[1] < b[1] end)
  local added = H.Merge(FI:Realm(), id, points, { source = "guild history" })
  Y.histItems = (Y.histItems or 0) + (added > 0 and 1 or 0)
  Y.histPoints = (Y.histPoints or 0) + added
  Y.histFrom = from
end

local function onHistoryDone(from)
  if not Y.wantHistory then return end
  Y.wantHistory = false
  H.cache = nil
  FI:Print("Got %s days of price history for %s items from %s.", FI.Number(Y.histPoints or 0), FI.Number(Y.histItems or 0), from)
  Y.histPoints, Y.histItems = 0, 0
  FI:Fire("FI_DATA_MERGED", from)
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function me()
  local name = UnitName("player")
  return name
end

-- ---------------------------------------------------------------------------
-- Dungeon loot: one short message per boss kill, so everyone's drop chances
-- learn from the whole guild's kills. The corpse's ID means a kill looted by five
-- guildmates still counts once.
-- ---------------------------------------------------------------------------
function Y:ShareKill(guid, instance, key, boss, items)
  if not canSync() or self:ActivePeers() == 0 then return end
  local ids = {}
  for _, id in ipairs(items) do ids[#ids + 1] = b36(id) end
  local msg = table.concat({ "L" .. guid, key, boss or "", instance or "", table.concat(ids, ",") }, "^")
  if #msg > MSG_MAX then msg = msg:sub(1, MSG_MAX):gsub(",[^,]*$", "") end
  send(msg, "GUILD", nil, "loot")
end

local function onKill(rest)
  local guid, key, boss, instance, ids = strsplit("^", rest)
  if not guid or not key or key == "" then return end
  local items = {}
  for v in (ids or ""):gmatch("[^,]+") do
    local id = n36(v)
    if id and id > 0 then items[#items + 1] = id end
  end
  local L = FI.Loot
  if not L then return end
  local d = L.DB()
  local npc = L.NpcFromGUID(guid)
  if npc and not d.bossNpc[npc] then d.bossNpc[npc] = { key = key, name = boss, instance = instance } end
  L:Record(guid, instance ~= "" and instance or nil, key, boss ~= "" and boss or nil, items)
end

local function shortName(full)
  return (full and full:match("^([^%-]+)")) or full
end

FI:On("CHAT_MSG_ADDON", function(_, prefix, text, channel, from)
  if prefix ~= PREFIX or not text or FI.settings.guildSync == false then return end
  local who = shortName(from)
  if who == me() then return end
  if channel ~= "GUILD" and channel ~= "WHISPER" then return end
  H = H or FI.History
  local kind, rest = text:sub(1, 1), text:sub(2)
  Y.peers[who] = time()
  gone[who] = nil -- they're online
  if channel == "GUILD" then
    if kind == "S" then onStart(who, rest)
    elseif kind == "B" then onBatch(who, rest)
    elseif kind == "E" then onEnd(who, who, rest)
    elseif kind == "Q" then if rest == PROTO then onRequest(who) end
    elseif kind == "N" then onScanRequest(who, rest)
    elseif kind == "C" then onCatchupRequest(who, rest)
    elseif kind == "R" then onResponding(rest)
    elseif kind == "L" then onKill(rest)
    elseif kind == "V" then
      -- hello: say hello back (once a day per person) so both sides know
      if not Y.greeted[who] or time() - Y.greeted[who] > 86400 then
        Y.greeted[who] = time()
        send("W" .. (FI.version or ""), "WHISPER", who)
      end
    end
  else
    if kind == "H" then onHistory(who, rest)
    elseif kind == "F" then onHistoryDone(who)
    -- the newest scan we asked for at login
    elseif kind == "S" then if Y.wantScan then onStart("@" .. who, rest, true) end
    elseif kind == "B" then onBatch("@" .. who, rest)
    elseif kind == "E" then onEnd("@" .. who, who, rest)
    elseif kind == "K" then onCatchup(who, rest)
    elseif kind == "G" then onCatchupDone(who) end
  end
end)

FI:On("FI_SCAN_DONE", function(_, t, from)
  local realm = FI:Realm()
  if t > (realm.liveScan or 0) then realm.liveScan = t end
  -- only our own scans are broadcast (shared ones carry a sender)
  if from == nil and FI.Scanner and FI.Scanner.lastFinished == t then Y:BroadcastScan(t) end
end)

-- When we were last online (to know what to ask for at the next login)
local clock = CreateFrame("Frame")
clock.acc = 0
clock:SetScript("OnUpdate", function(self, e)
  self.acc = self.acc + e
  if self.acc >= 60 and FI.db then
    self.acc = 0
    FI:Realm().lastOnline = time()
  end
end)
FI:On("PLAYER_LOGOUT", function() if FI.db then FI:Realm().lastOnline = time() end end)

FI:On("PLAYER_LOGIN", function()
  H = FI.History
  if FI.settings.guildSync == nil then FI.settings.guildSync = true end
  if CI and CI.RegisterAddonMessagePrefix then CI.RegisterAddonMessagePrefix(PREFIX) end
  Y.ready = true
  local realm = FI:Realm()
  local offlineSince = realm.lastOnline
  realm.lastOnline = time()
  C_Timer.After(15, function()
    if not canSync() then return end
    send("V" .. (FI.version or ""))
    Y:RequestScan()
    if historyDepth() < 200 then
      Y:RequestHistory(false)
    elseif offlineSince and time() - offlineSince > 20 * 60 then
      Y:RequestCatchup(offlineSince, false)
    end
  end)
end)

-- Status for /goon sync
function Y:Status()
  local now, n = time(), 0
  local names = {}
  for who, t in pairs(self.peers) do
    if now - t < 86400 then n = n + 1; names[#names + 1] = who end
  end
  table.sort(names)
  local realm = FI:Realm()
  FI:Print("Guild sync is %s. %d guildmate%s with Goonberg seen today%s.",
    FI.settings.guildSync == false and "off" or "on", n, n == 1 and "" or "s",
    n > 0 and (": " .. table.concat(names, ", ", 1, math.min(#names, 10))) or "")
  if realm.lastShared then
    FI:Print("Last guild scan: %s items from %s, %s.", FI.Number(realm.lastShared.items), realm.lastShared.from, FI.Ago(realm.lastShared.t))
  end
  if #queue > 0 then FI:Print("Sending your last scan: %d messages to go.", #queue) end
end
