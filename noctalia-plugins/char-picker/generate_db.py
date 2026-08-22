#!/usr/bin/env python3
# Regenerates database.json. Run after a python3 or noctalia update:
#   python3 generate_db.py
#
# Two sources, both guaranteed present with the host:
#   python3 unicodedata (stdlib UCD)         names for the symbol ranges below
#   /usr/share/noctalia/assets/emoji.json    noctalia's own emoji + keywords

import json
import unicodedata
from pathlib import Path

EMOJI_JSON = Path("/usr/share/noctalia/assets/emoji.json")
OUT = Path(__file__).parent / "database.json"

# Import only symbol ranges that are worth browsing
# Effectively filters out hundreds of thousands of CJK and historical glyphs
RANGES = [
    (0x0021, 0x002F),  # ASCII punctuation ! " # $ % & ' ( ) * + , - . /
    (0x003A, 0x0040),  # ASCII punctuation : ; < = > ? @
    (0x005B, 0x0060),  # ASCII punctuation [ \ ] ^ _ `
    (0x007B, 0x007E),  # ASCII punctuation { | } ~
    (0x00A1, 0x00FF),  # Latin-1 punctuation, symbols, accented letters
    (0x0370, 0x03FF),  # Greek and Coptic
    (0x2000, 0x206F),  # General Punctuation
    (0x2070, 0x209F),  # Super/Subscripts
    (0x20A0, 0x20BF),  # Currency
    (0x2100, 0x214F),  # Letterlike
    (0x2150, 0x218B),  # Number Forms
    (0x2190, 0x21FF),  # Arrows
    (0x2200, 0x22FF),  # Mathematical Operators
    (0x2300, 0x23FF),  # Misc Technical (keyboard keys, power)
    (0x2500, 0x259F),  # Box Drawing + Block Elements
    (0x25A0, 0x25FF),  # Geometric Shapes
    (0x2600, 0x26FF),  # Misc Symbols
    (0x2700, 0x27BF),  # Dingbats
    (0x27F0, 0x27FF),  # Supplemental Arrows-A
    (0x2900, 0x297F),  # Supplemental Arrows-B
    (0x2B00, 0x2BFF),  # Misc Symbols and Arrows
]

# Filter out invisible char categories. 
SKIP_GC = {"Cc", "Cf", "Zs", "Zl", "Zp", "Mn", "Me", "Mc"}

# Launcher-ready entry: n = search haystack (name + keywords + u+hex),
# t = display name, x = "U+XXXX" or "" (multi-codepoint emoji).
def entry(ch, name, keywords=()):
    hex_kw = f"u+{ord(ch):04x}" if len(ch) == 1 else ""
    kws = " ".join(w for w in keywords if w and w not in name.split())
    hay = " ".join(p for p in (name, kws, hex_kw) if p)
    return {"c": ch, "n": hay, "t": name, "x": hex_kw.upper()}


def main():
    emoji, taken = [], set()
    for e in json.loads(EMOJI_JSON.read_text()):
        ch = e["emoji"]
        taken.add(ch)
        taken.add(ch.replace("️", ""))
        emoji.append(entry(ch, e["name"].lower(), e.get("keywords", [])))

    symbols = []
    for lo, hi in RANGES:
        for cp in range(lo, hi + 1):
            ch = chr(cp)
            name = unicodedata.name(ch, "").lower()
            if not name or ch in taken or unicodedata.category(ch) in SKIP_GC:
                continue
            symbols.append(entry(ch, name))

    entries = symbols + emoji  # symbols first: primary use is character search
    OUT.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")))
    print(f"{len(symbols)} symbols + {len(emoji)} emoji, {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
