"""Shared helpers: read WoW's Lua SavedVariables and read/write Goonberg seed files."""
import os
import re

DAY = 86400

# --- a small reader for the Lua tables WoW writes ---------------------------------
TOKEN = re.compile(r'''
    \s+ | --\[\[.*?\]\] | --[^\n]* |
    (?P<str>"(?:\\.|[^"\\])*") |
    (?P<num>-?(?:0x[0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+)) |
    (?P<name>[A-Za-z_][A-Za-z0-9_]*) |
    (?P<op>[{}\[\]=,;])
''', re.S | re.X)

ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def unquote(s):
    out, i = [], 1
    while i < len(s) - 1:
        c = s[i]
        if c == "\\":
            n = s[i + 1]
            if n.isdigit():
                j = i + 1
                while j < i + 4 and s[j].isdigit():
                    j += 1
                out.append(chr(int(s[i + 1:j])))
                i = j
                continue
            out.append(ESC.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def tokens(text):
    pos = 0
    for m in TOKEN.finditer(text):
        if m.start() != pos:
            raise ValueError("unexpected text at %d: %r" % (pos, text[pos:pos + 20]))
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)
    if pos != len(text):
        raise ValueError("unexpected text at %d" % pos)


class Reader:
    def __init__(self, text):
        self.toks = list(tokens(text))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, value=None):
        t = self.peek()
        if value is not None and t[1] != value:
            raise ValueError("expected %s, got %s" % (value, t[1]))
        self.i += 1
        return t

    def value(self):
        kind, v = self.take()
        if kind == "str":
            return unquote(v)
        if kind == "num":
            return int(v, 16) if v.lower().startswith(("0x", "-0x")) else (float(v) if any(c in v for c in ".eE") else int(v))
        if kind == "name":
            return {"true": True, "false": False, "nil": None}[v]
        if v == "{":
            return self.table()
        raise ValueError("unexpected " + str(v))

    def table(self):
        t, n = {}, 1
        while self.peek()[1] != "}":
            if self.peek()[1] == "[":
                self.take("[")
                k = self.value()
                self.take("]")
                self.take("=")
                t[k] = self.value()
            elif self.peek()[0] == "name" and self.toks[self.i + 1][1] == "=":
                k = self.take()[1]
                self.take("=")
                t[k] = self.value()
            else:
                t[n] = self.value()
                n += 1
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        return t


def read_saved(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    r = Reader(text)
    out = {}
    while r.peek()[0]:
        name = r.take()[1]
        r.take("=")
        out[name] = r.value()
    return out.get("GoonbergTerminalDB") or {}


def arr(t):
    """Lua array table -> Python list"""
    if isinstance(t, list):
        return t
    return [t[i] for i in range(1, len(t) + 1)] if isinstance(t, dict) else []


# --- base36 ---------------------------------------------------------------------
DIG = "0123456789abcdefghijklmnopqrstuvwxyz"


def b36(n):
    n = int(n)
    if n == 0:
        return "0"
    s = ""
    while n:
        n, r = divmod(n, 36)
        s = DIG[r] + s
    return s


# --- reading seed files ----------------------------------------------------------
def read_seed(path):
    """-> {realm: {item: {day: (price, qty)}}}"""
    if not os.path.exists(path):
        return {}
    r = Reader(open(path, encoding="utf-8").read())
    seed = None
    while r.peek()[0]:
        name = r.take()[1]
        r.take("=")
        v = r.value()
        if name == "GoonbergSeed":
            seed = v
    out = {}
    if not seed:
        return out
    for realm, data in (seed.get("realms") or {}).items():
        base = data["base"]
        items = out.setdefault(realm, {})
        for item, s in data["items"].items():
            days = items.setdefault(int(item), {})
            for e in s.split(";"):
                if not e:
                    continue
                d, p, q = (e.split(",") + ["", ""])[:3]
                days[base + int(d, 36)] = (int(p, 36), int(q, 36) if q else 0)
    return out



def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_seed(path, markets, built, keep_from_day, min_days=2, header=None):
    """markets: {key: {item: {day: (price, qty)}}} -> Lua file. Returns (items, points)."""
    lines = list(header or [
        "-- Shared price history for Goonberg Terminal.",
        "-- Daily market price and quantity listed, per market. Format per item: day,price,qty;...",
        "-- (base36, day counted from `base`)",
    ])
    lines += ["GoonbergSeed = {", "  built = %d," % built, "  realms = {"]
    total_items = total_points = 0
    for key in sorted(markets):
        items = {i: {d: v for d, v in days.items() if d >= keep_from_day} for i, days in markets[key].items()}
        items = {i: days for i, days in items.items() if len(days) >= min_days}
        if not items:
            continue
        all_days = sorted({d for days in items.values() for d in days})
        base = all_days[0]
        lines.append("    [%s] = {" % lua_str(key))
        lines.append("      base = %d," % base)
        lines.append('      days = "%s",' % " ".join(b36(d - base) for d in all_days))
        lines.append("      items = {")
        for item in sorted(items):
            days = items[item]
            body = ";".join("%s,%s,%s" % (b36(d - base), b36(p), b36(q)) for d, (p, q) in sorted(days.items()))
            lines.append('        [%d] = "%s",' % (item, body))
            total_items += 1
            total_points += len(days)
        lines.append("      },")
        lines.append("    },")
    lines += ["  },", "}", ""]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return total_items, total_points
