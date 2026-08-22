# Character Picker

Find special characters and emoji you can't type (e.g. "→", "¥", "∬", "😂") via the launcher.

1. Open the Noctalia launcher and type `/char` (or press `Mod+.`).
2. Type what you're looking for: "dollar", "arrow", "pizza" or a code like `u+2192`.
3. Press Enter on a result to copy.

## Files

- `char.luau` — answers launcher searches; runs inside Noctalia.
- `database.json` — the ~4000 searchable characters.
- `generate_db.py` — rebuilds `database.json` from the system's Unicode data and Noctalia's emoji list. Run `python3 generate_db.py` after a Noctalia or Python update; not needed day-to-day.
