#!/usr/bin/env python3
"""Build Loot/Data.lua (bundled dungeon loot tables) from Dungeon Codex.

Usage:
    git clone --depth 1 https://github.com/dldvlpr-addons-wow/dungeonCodex /tmp/dungeonCodex
    python tools/build_loot.py /tmp/dungeonCodex

Dungeon Codex (GPL-2.0) bundles WoW Forever dungeon loot: bosses and their items from
AtlasLootClassic (GPL-2.0), with Forever drop chances and new items from
foreverchanges.pro. Goonberg uses the bosses (creature IDs), their loot and the drop
chances; everything else in it (maps, tactics, quests) is left out.
Requires: pip install lupa
"""
import os
import re
import subprocess
import sys
import time

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Loot", "Data.lua")
SPECIAL = {"Ragefire": "Ragefire Chasm", "Deadmines": "The Deadmines", "Stockade": "The Stockade",
           "Gnomeregan": "Gnomeregan", "Uldaman": "Uldaman", "Maraudon": "Maraudon",
           "Scholomance": "Scholomance", "Stratholme": "Stratholme"}


def english(key):
    if key in SPECIAL:
        return SPECIAL[key]
    words = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", key).split(" ")
    small = {"Of", "The", "And"}
    return " ".join(w.lower() if i > 0 and w in small else w for i, w in enumerate(words))


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    v = float(v)
    return ("%d" % v) if v == int(v) else ("%.2f" % v).rstrip("0").rstrip(".")


def main(src):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    code = open(os.path.join(src, "Data.lua"), encoding="utf-8").read()
    NS = L.table()
    L.execute("return function(code, ns) local f = assert(loadstring(code, '@Data.lua')); f('DungeonCodex', ns) end")(code, NS)
    try:
        commit = subprocess.check_output(["git", "-C", src, "log", "-1", "--format=%h %cs"], text=True).strip()
    except Exception:
        commit = "unknown"
    out = [
        "-- Goonberg Terminal: bundled WoW Forever dungeon loot. Built by tools/build_loot.py, do not edit.",
        "-- From Dungeon Codex (GPL-2.0, github.com/dldvlpr-addons-wow/dungeonCodex, %s):" % commit,
        "-- bosses and loot from AtlasLootClassic (GPL-2.0), Forever drop chances and items from foreverchanges.pro.",
        "-- Per boss: { creature ID, name, { items }, { [item] = drop % }, rare spawn }",
        "local _, FI = ...",
        "FI.LootData = {",
        "  built = %d," % int(time.time()),
        "  source = %s," % lua_str("Dungeon Codex " + commit),
        "  dungeons = {",
    ]
    n_d = n_b = n_i = n_c = 0
    for dg in NS.Dungeons.values():
        if dg.upcoming or not dg.bosses:
            continue
        bosses = []
        for b in dg.bosses.values():
            items = [int(i) for i in (b["items"] or {}).values()] if b["items"] else []
            drops = {int(k): float(v) for k, v in (b.drops.items() if b.drops else [])}
            if not items and not drops:
                continue
            for i in drops:
                if i not in items:
                    items.append(i)
            bosses.append("      { %d, %s, { %s }, { %s }%s }," % (
                int(b.npc), lua_str(b.name), ", ".join(str(i) for i in items),
                ", ".join("[%d] = %s" % (i, num(c)) for i, c in sorted(drops.items())),
                ", true" if b.rare else ""))
            n_b += 1
            n_i += len(items)
            n_c += len(drops)
        if not bosses:
            continue
        lv = dg.levels
        levels = "{ %d, %d }" % (int(lv[2]), int(lv[3])) if lv else "nil"
        out.append("    { key = %s, name = %s, instance = %d, levels = %s, status = %s, bosses = {" % (
            lua_str(dg.key), lua_str(english(dg.key)), int(dg.instance or 0), levels, lua_str(dg.status or "")))
        out += bosses
        out.append("    } },")
        n_d += 1
    out += ["  },", "}", ""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("Wrote %s: %d dungeons, %d bosses, %d items, %d drop chances (%.0f KB)" % (
        os.path.normpath(OUT), n_d, n_b, n_i, n_c, os.path.getsize(OUT) / 1024))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
