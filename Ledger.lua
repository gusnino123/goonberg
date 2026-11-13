-- Goonberg Terminal: profit and loss from Auction House mail invoices
-- Every AH sale and purchase arrives as mail with an invoice. When the mailbox is
-- open we read those invoices once each and keep a ledger per character.
local _, FI = ...
local L = {}
FI.Ledger = L
local DAY = 86400
local MAIL_DAYS = 30 -- AH mail lasts 30 days, so daysLeft tells us roughly when it was sent

function L:Data()
  local realm = FI:Realm()
  local who = UnitName("player") or "?"
  realm.ledger = realm.ledger or {}
  local d = realm.ledger[who]
  if not d then
    d = { entries = {}, inbox = {} }
    realm.ledger[who] = d
  end
  return d
end

-- entries: flat list of { t, kind ("sale"|"buy"), item, qty, gross, fee }
local function add(d, t, kind, item, qty, gross, fee)
  d.entries[#d.entries + 1] = { t = t, k = kind, i = item, q = qty or 1, g = gross or 0, f = fee or 0 }
end

function L:ReadInbox()
  if not GetInboxNumItems or not GetInboxInvoiceInfo then return end
  local d = self:Data()
  local now = time()
  local counts, info = {}, {}
  for i = 1, GetInboxNumItems() do
    local invoiceType, itemName, playerName, bid, _, deposit, consignment, _, _, count = GetInboxInvoiceInfo(i)
    if invoiceType == "seller" or invoiceType == "buyer" then
      local _, _, _, _, _, _, daysLeft = GetInboxHeaderInfo(i)
      local key = table.concat({ invoiceType, itemName or "?", playerName or "?", bid or 0, deposit or 0, consignment or 0 }, "|")
      counts[key] = (counts[key] or 0) + 1
      info[key] = { invoiceType, itemName, bid or 0, consignment or 0, count, daysLeft }
    end
  end
  -- Mail we've already counted stays in the inbox; only new copies are added.
  local added = 0
  for key, n in pairs(counts) do
    local seen = d.inbox[key] or 0
    if n > seen then
      local inv = info[key]
      local sent = now - math.max(0, MAIL_DAYS - (inv[6] or MAIL_DAYS)) * DAY
      for _ = 1, n - seen do
        if inv[1] == "seller" then
          add(d, sent, "sale", inv[2], inv[5], inv[3], inv[4])
        else
          add(d, sent, "buy", inv[2], inv[5], inv[3], 0)
        end
        added = added + 1
      end
    end
    d.inbox[key] = n
  end
  -- Mail that was taken: forget it so an identical sale later still counts
  for key in pairs(d.inbox) do
    if not counts[key] then d.inbox[key] = nil end
  end
  if added > 0 then FI:Fire("FI_LEDGER_CHANGED") end
end

FI:On("MAIL_INBOX_UPDATE", function()
  FI:Debounce("ledger", 0.5, function() L:ReadInbox() end)
end)
FI:On("MAIL_SHOW", function() L:ReadInbox() end)

-- Totals since `since` (a time), for this character
function L:Summary(since)
  local d = self:Data()
  local s = { income = 0, fees = 0, spent = 0, sales = 0, buys = 0, items = {} }
  for _, e in ipairs(d.entries) do
    if e.t >= since then
      local per = s.items[e.i] or { net = 0 }
      s.items[e.i] = per
      if e.k == "sale" then
        s.income = s.income + e.g
        s.fees = s.fees + e.f
        s.sales = s.sales + 1
        per.net = per.net + e.g - e.f
      else
        s.spent = s.spent + e.g
        s.buys = s.buys + 1
        per.net = per.net - e.g
      end
    end
  end
  s.net = s.income - s.fees - s.spent
  -- ROI only means something when you mostly flip (buy to resell). For farmers,
  -- whose sales cost nothing on the AH, it would be a silly 500%+.
  if s.spent > 0 and s.spent >= (s.income - s.fees) * 0.25 then s.roi = s.net / s.spent * 100 end
  for name, per in pairs(s.items) do
    if not s.best or per.net > s.best.net then s.best = { name = name, net = per.net } end
  end
  return s
end

-- What your bags would fetch at market price right now (not yet sold, so "unrealized")
function L:BagValue()
  if not C_Container or not C_Container.GetContainerNumSlots then return 0 end
  local realm = FI:Realm()
  local total = 0
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isBound then
        local it = realm.items[info.itemID]
        if it and it.mkt then total = total + it.mkt * (info.stackCount or 1) end
      end
    end
  end
  return total
end
