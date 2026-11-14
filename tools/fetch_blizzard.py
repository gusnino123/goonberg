#!/usr/bin/env python3
"""Daily WoW Forever prices from Blizzard's Game Data API -> one data addon per market.

Run by .github/workflows/blizzard-prices.yml once a day. Needs a free Blizzard API
client (https://develop.battle.net/access/clients) in two environment variables:
    BLIZZARD_CLIENT_ID, BLIZZARD_CLIENT_SECRET
Optional: REGIONS (default "us"), OUT_DIR (default ./Markets).

Forever has no realms: each region has one mega-realm per ruleset (PvP, Normal,
Roleplay, Roleplay PvP), each with an Alliance, Horde and Blackwater (neutral) AH.
Blizzard's Forever API is undocumented, so this script is defensive and prints what
it finds. For each faction AH it records, per item and day, the same "market price"
the addon uses (average of the cheapest 15% of units) and the quantity listed, keeps
the last 60 days, and writes Markets/GoonbergData_<REGION>_<Ruleset>_<Faction>/,
a load-on-demand addon that Goonberg Terminal loads only for the player's own market.
"""
import base64
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from seedlib import DAY, read_seed, write_seed  # noqa: E402

KEEP_DAYS = 60
MIN_DAYS = 1
INTERFACE = "16001"
FACTIONS = ("Alliance", "Horde")  # the neutral Blackwater AH isn't tracked by the addon


def log(*a):
    print(*a, flush=True)


def http_json(url, token=None, data=None, auth=None, tries=4):
    for attempt in range(tries):
        req = urllib.request.Request(url, data=data)
        if token:
            req.add_header("Authorization", "Bearer " + token)
        if auth:
            req.add_header("Authorization", "Basic " + auth)
        req.add_header("Accept-Encoding", "identity")
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (404, 403):
                return None
            if attempt == tries - 1:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == tries - 1:
                raise
        time.sleep(2 ** attempt * 3)  # 429 and 5xx: back off and retry


def get_token(cid, secret):
    auth = base64.b64encode(("%s:%s" % (cid, secret)).encode()).decode()
    r = http_json("https://oauth.battle.net/token", data=b"grant_type=client_credentials", auth=auth)
    if not r or "access_token" not in r:
        raise SystemExit("Could not get a Blizzard API token: check BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET")
    return r["access_token"]


def api(region, path, token, **params):
    q = {"namespace": "dynamic-forever-" + region, "locale": "en_US"}
    q.update(params)
    url = "https://%s.api.blizzard.com%s?%s" % (region, path, urllib.parse.urlencode(q))
    return http_json(url, token=token)


def find_list(obj, *keys):
    """The first list of dicts under any of `keys` (the API's field names aren't documented)."""
    if isinstance(obj, dict):
        for k in keys:
            if isinstance(obj.get(k), list):
                return obj[k]
    return []


def name_of(x):
    if isinstance(x, dict):
        n = x.get("name")
        if isinstance(n, dict):  # localized names come as {"en_US": ...} without locale=
            n = n.get("en_US") or next(iter(n.values()), None)
        return n
    return x


def slug(s):
    return re.sub(r"[^A-Za-z0-9]", "", s or "")


def faction_of(house_name):
    for f in FACTIONS + ("Blackwater",):
        if f.lower() in (house_name or "").lower():
            return f
    return None


def market_price(units):
    """units: list of (unit_price, qty). Same rule as History.MarketPrice in the addon."""
    units.sort()
    total = sum(q for _, q in units)
    want = max(1, math.ceil(total * 0.15))
    got = s = 0
    for p, q in units:
        take = min(q, want - got)
        s += p * take
        got += take
        if got >= want:
            break
    return (round(s / got) if got else 0), total


def collect(entries, units_by_item, price_field):
    for a in entries or []:
        item = a.get("item")
        item_id = item.get("id") if isinstance(item, dict) else item
        qty = a.get("quantity") or 0
        if not item_id or qty <= 0:
            continue
        if price_field == "unit_price":
            unit = a.get("unit_price")
        else:
            buyout = a.get("buyout")
            unit = buyout / qty if buyout else None
        if unit and unit > 0:
            units_by_item.setdefault(int(item_id), []).append((unit, qty))


def fetch_region(region, token):
    rs = api(region, "/data/wow/ruleset/index", token)
    rulesets = find_list(rs, "rulesets", "results")
    if not rulesets:
        log("  %s: no rulesets returned (%s)" % (region, json.dumps(rs)[:300] if rs else "404/403"))
        return {}
    names = {r.get("id"): name_of(r) for r in rulesets}
    log("  %s rulesets: %s" % (region, ", ".join("%s=%s" % kv for kv in names.items())))

    # Every ruleset lists the same houses (the API doesn't filter by ruleset), so read
    # the house list once and learn each house's ruleset from the house itself.
    houses, seen = [], set()
    for rid in names:
        idx = api(region, "/data/wow/ruleset/%d/auctions/" % rid, token)
        for h in find_list(idx, "auctions", "auction_houses", "houses"):
            if h.get("id") not in seen:
                seen.add(h.get("id"))
                houses.append((rid, h))
    log("  %s: %d auction houses" % (region, len(houses)))

    out = {}
    for rid, h in houses:
        hid = h.get("id")
        data = api(region, "/data/wow/ruleset/%d/auctions/%d" % (rid, hid), token)
        if not data:
            log("    house %s: no data" % hid)
            continue
        hname = name_of(data) or name_of(h)
        faction = faction_of(hname)
        rset = data.get("ruleset")
        rname = name_of(rset) if isinstance(rset, dict) else names.get(rset)
        if not rname and isinstance(rset, dict):
            rname = names.get(rset.get("id"))
        units = {}
        collect(data.get("auctions") if isinstance(data.get("auctions"), list) else [], units, "buyout")
        com = data.get("commodities")
        if isinstance(com, list):
            collect(com, units, "unit_price")
        elif com is not None:
            c = api(region, "/data/wow/ruleset/%d/auctions/%d/commodities" % (rid, hid), token)
            collect(find_list(c, "auctions"), units, "unit_price")
        log("    house %s %r: ruleset=%r faction=%s, %d items" % (hid, hname, rname, faction, len(units)))
        if faction not in FACTIONS or not rname or not units:
            continue
        key = "%s %s - %s" % (region.upper(), rname, faction)
        tgt = out.setdefault(key, {})
        for item, us in units.items():
            # two houses for the same market (shouldn't happen): keep the deeper one
            p, q = market_price(us)
            if p > 0 and (item not in tgt or q > tgt[item][1]):
                tgt[item] = (p, q)
    return out


def addon_name(key):
    # "US Roleplay PvP - Horde" -> GoonbergData_US_RoleplayPvP_Horde
    left, faction = key.rsplit(" - ", 1)
    region, ruleset = left.split(" ", 1)
    return "GoonbergData_%s_%s_%s" % (region, slug(ruleset), faction)


def write_market(out_dir, key, items_by_day, now):
    name = addon_name(key)
    folder = os.path.join(out_dir, name)
    os.makedirs(folder, exist_ok=True)
    first_day = now // DAY - KEEP_DAYS
    n_items, n_points = write_seed(os.path.join(folder, "Data.lua"), {key: items_by_day}, now, first_day, MIN_DAYS, header=[
        "-- Goonberg Terminal market data for %s, from Blizzard's auction house API." % key,
        "-- Built daily by tools/fetch_blizzard.py. Loaded on demand by Goonberg Terminal.",
    ])
    with open(os.path.join(folder, name + ".toc"), "w", newline="\n") as f:
        f.write("\n".join([
            "## Interface: " + INTERFACE,
            "## Title: Goonberg Terminal Data |cff8b95a3(%s)|r" % key,
            "## Notes: Daily Auction House prices for Goonberg Terminal. Loaded only on this market.",
            "## Author: Goonberg Terminal",
            "## LoadOnDemand: 1",
            "## Dependencies: GoonbergTerminal",
            "## X-Goonberg-Market: " + key,
            "## X-Goonberg-Built: %d" % now,
            "",
            "Data.lua",
            "",
        ]))
    return name, n_items, n_points


def main():
    cid, secret = os.environ.get("BLIZZARD_CLIENT_ID"), os.environ.get("BLIZZARD_CLIENT_SECRET")
    if not cid or not secret:
        log("BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET aren't set: nothing to do.")
        return 0
    out_dir = os.environ.get("OUT_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Markets")
    regions = [r.strip().lower() for r in (os.environ.get("REGIONS") or "us").split(",") if r.strip()]
    now = int(time.time())
    today = now // DAY
    token = get_token(cid, secret)
    written = 0
    for region in regions:
        log("Fetching %s..." % region.upper())
        markets = fetch_region(region, token)
        for key, today_items in sorted(markets.items()):
            path = os.path.join(out_dir, addon_name(key), "Data.lua")
            history = read_seed(path).get(key, {})
            for item, (p, q) in today_items.items():
                history.setdefault(item, {})[today] = (p, q)  # a rerun the same day replaces it
            name, n_items, n_points = write_market(out_dir, key, history, now)
            size = os.path.getsize(os.path.join(out_dir, name, "Data.lua")) / 1e6
            log("  %s: %d items today, %d items / %d days in history, %.1f MB" % (name, len(today_items), n_items, n_points, size))
            written += 1
    if not written:
        log("No markets were written. Blizzard's Forever API may have changed: see the log above.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
