#!/usr/bin/env python3
"""Build Seed/Data.lua: shared daily price history that ships with Goonberg Terminal.

Usage:
    python tools/build_seed.py GoonbergTerminal.lua [more.lua ...]

Each argument is a GoonbergTerminal.lua SavedVariables file, found at
    World of Warcraft/_classic_/WTF/Account/<ACCOUNT>/SavedVariables/GoonbergTerminal.lua

Only prices leave the file: for every realm, item and day, the median market price
and the average quantity listed. Character names, your P&L, alerts, watch lists and
settings are never read into the output. Days already in Seed/Data.lua are kept, so
running it again with a newer file (or someone else's) only adds to the history.
Several files are combined by taking the median per day.
"""
import os
import sys
import time
from statistics import median

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from seedlib import DAY, arr, read_saved, read_seed, write_seed  # noqa: E402

KEEP_DAYS = 60
MIN_DAYS = 2  # an item needs at least this many days to be worth shipping
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Seed", "Data.lua")


def main(files):
    now = int(time.time())
    first_day = now // DAY - KEEP_DAYS
    seed = read_seed(OUT)
    # realm -> item -> day -> list of (price, qty) from the new files
    fresh = {}
    for path in files:
        db = read_saved(path)
        for realm, r in (db.get("realms") or {}).items():
            items = (r or {}).get("items") or {}
            n = 0
            for item, it in items.items():
                h = arr((it or {}).get("h") or {})
                byday = {}
                for i in range(0, len(h) - 3, 4):
                    t, mkt, qty = h[i], h[i + 1], h[i + 2]
                    if not mkt or mkt <= 0:
                        continue
                    d = int(t) // DAY
                    if d >= first_day:
                        byday.setdefault(d, []).append((mkt, qty or 0))
                if byday:
                    n += 1
                    tgt = fresh.setdefault(realm, {}).setdefault(int(item), {})
                    for d, pts in byday.items():
                        tgt.setdefault(d, []).append((median(p for p, _ in pts), sum(q for _, q in pts) / len(pts)))
            print("  %s: %d items from %s" % (realm, n, os.path.basename(path)))

    # combine: new files win over what was already in the seed for the same day
    for realm, items in fresh.items():
        tgt = seed.setdefault(realm, {})
        for item, days in items.items():
            dst = tgt.setdefault(item, {})
            for d, vals in days.items():
                dst[d] = (round(median(p for p, _ in vals)), round(sum(q for _, q in vals) / len(vals)))

    total_items, total_points = write_seed(OUT, seed, now, first_day, MIN_DAYS)
    size = os.path.getsize(OUT)
    print("Wrote %s: %d items, %d days of prices, %.1f MB" % (os.path.normpath(OUT), total_items, total_points, size / 1e6))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1:])
