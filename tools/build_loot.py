#!/usr/bin/env python3
"""Build Loot/Data.lua (bundled dungeon loot tables) from Dungeon Codex.

Usage:
    git clone --depth 1 https://github.com/dldvlpr-addons-wow/dungeonCodex /tmp/dungeonCodex
    python tools/build_loot.py /tmp/dungeonCodex

Dungeon Codex (GPL-2.0) bundles WoW Forever dungeon loot: bosses and their items from
AtlasLootClassic (GPL-2.0), with Forever drop chances and new items from
foreverchanges.pro. Goonberg uses the bosses (creature IDs), their loot and the drop
chances; everything else in it (maps, tactics, quests) is left out.

Its tools/foreverchanges.json also has what Data.lua leaves out, and that's where
most rare Bind on Equip drops are: each dungeon's trash table, chests and other
objects, and a few bosses. Those are added too (quest items are not).
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


def norm(s):
    return re.sub(r"[^a-z]", "", s.lower())


SLUGS = {"ragefirechasm": "ragefire", "sunkentemple": "thetempleofatalhakkar",
         "stratholmemaingate": "stratholme", "stratholmeservicegate": "stratholme"}


def extras_from_site(src):
    """dungeon key (normalized) -> {"trash": {id: chance}, "sources": [(kind, name, {id: chance})]}"""
    path = os.path.join(src, "tools", "foreverchanges.json")
    if not os.path.exists(path):
        return {}
    import json
    out = {}
    for dg in json.load(open(path, encoding="utf-8")):
        key = SLUGS.get(norm(dg["slug"]), norm(dg["slug"]))
        e = out.setdefault(key, {"trash": {}, "sources": [], "bossItems": {}})
        for b in dg.get("bosses", []):
            items = {int(it["id"]): it.get("chance") for it in b.get("items", []) if it.get("id")}
            if not items:
                continue
            kind = b.get("kind")
            if kind == "trash":
                for i, c in items.items():
                    if i not in e["trash"] or (c and not e["trash"][i]):
                        e["trash"][i] = c
            elif kind in ("object", "boss", "rare"):
                e["sources"].append((kind, b.get("english") or b.get("name"), items))
    return out


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
        "-- Per boss: { creature ID, name, { items }, { [item] = drop % }, rare spawn, object }",
        "-- Per dungeon trash: trash = { { items }, { [item] = drop % per trash mob } }",
        "local _, FI = ...",
        "FI.LootData = {",
        "  built = %d," % int(time.time()),
        "  source = %s," % lua_str("Dungeon Codex " + commit),
        "  dungeons = {",
    ]
    n_d = n_b = n_i = n_c = n_x = n_t = 0
    extras = extras_from_site(src)
    trash_lines = []
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
        site = extras.get(norm(dg.key))
        if site:
            have_names = {norm(b.name) for b in dg.bosses.values()}
            have_items = set()
            for b in dg.bosses.values():
                if b["items"]:
                    have_items.update(int(i) for i in b["items"].values())
            for kind, name, items in site["sources"]:
                if kind == "boss" and norm(name) in have_names:
                    continue
                new = {i: c for i, c in items.items() if i not in have_items}
                if not new:
                    continue
                # no creature ID for these: 0 (chests and the like can't be "killed" anyway)
                bosses.append("      { 0, %s, { %s }, { %s }, %s }," % (
                    lua_str(name), ", ".join(str(i) for i in new),
                    ", ".join("[%d] = %s" % (i, num(c)) for i, c in sorted(new.items()) if c),
                    "false, true" if kind == "object" else "false"))
                n_x += len(new)
            if site["trash"]:
                trash_lines.append((dg.key, site["trash"]))
        if not bosses:
            continue
        lv = dg.levels
        levels = "{ %d, %d }" % (int(lv[2]), int(lv[3])) if lv else "nil"
        out.append("    { key = %s, name = %s, instance = %d, levels = %s, status = %s, bosses = {" % (
            lua_str(dg.key), lua_str(english(dg.key)), int(dg.instance or 0), levels, lua_str(dg.status or "")))
        out += bosses
        trash = dict(trash_lines).get(dg.key)
        if trash:
            out.append("    }, trash = { { %s }, { %s } } }," % (
                ", ".join(str(i) for i in sorted(trash)),
                ", ".join("[%d] = %s" % (i, num(c)) for i, c in sorted(trash.items()) if c)))
            n_t += len(trash)
        else:
            out.append("    } },")
        n_d += 1
    out += ["  },", "}", ""]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("Wrote %s: %d dungeons, %d bosses, %d items, %d drop chances, +%d chest/extra items, +%d trash items (%.0f KB)" % (
        os.path.normpath(OUT), n_d, n_b, n_i, n_c, n_x, n_t, os.path.getsize(OUT) / 1024))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
