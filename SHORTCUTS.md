# Niri Shortcut Cheatsheet

Source: `user/binds.kdl`

## The mental model

Every bind is `[modifiers] + [key]`. The **modifiers say what kind of action**, the **key says the target**. Learn the four modifier "verbs" and most binds become guessable.

| Modifier stack         | Meaning (the "verb")                           | Muscle-memory hook                 |
| ---------------------- | ---------------------------------------------- | ---------------------------------- |
| **Mod**                | Focus / act / launch — the everyday layer      | "just do it"                       |
| **Mod + Shift**        | Move / amplify the Mod action                  | Shift = "with force" (carry, grow) |
| **Mod + Ctrl**         | Aim at a bigger container (monitor, workspace) | Ctrl = "one level up"              |
| **Mod + Ctrl + Shift** | Move window into that bigger container         | Ctrl (target) + Shift (move)       |
| **Mod + Alt**          | Merge / split columns (consume · expel)        | Alt = "sideways special"           |

Two consistent axes underneath:

- **Shift added to any Mod bind = "and take the window with me."** Focus left → move left. Focus workspace → move-to workspace. Grow column → grow window (the other dimension).
- **Ctrl escalates the target.** Mod+Arrow focuses a _window_; Mod+Ctrl+Arrow focuses a _monitor_ / _workspace_.

Everything below is the same table sorted by that logic.

---

## Layer 1 — Mod (focus / launch / act)

### Launchers & apps

| Action                   | Bind             |
| ------------------------ | ---------------- |
| App Launcher (spotlight) | Mod+A            |
| Files (nautilus)         | Mod+E            |
| Zen Browser              | Mod+B            |
| Terminal (ghostty)       | Mod+Return       |
| Obsidian                 | Mod+Shift+Return |
| Clipboard Manager        | Mod+V            |
| Notifications            | Mod+M            |
| Settings                 | Mod+I            |
| Quick Settings           | Mod+S            |
| Browse Wallpapers        | Mod+Y            |
| Lock Screen              | Mod+L            |

### Dictation (voxtype)

Alt-based, independent of the Mod layers.

| Action           | Bind            |
| ---------------- | --------------- |
| Toggle dictation | Alt+Space       |
| Cancel dictation | Alt+Shift+Space |

### Window basics

| Action                     | Bind    | Alt bind |
| -------------------------- | ------- | -------- |
| Toggle overview            | Mod+Tab |          |
| Close window               | Mod+Q   | Alt+F4   |
| Maximize column            | Mod+F   |          |
| Toggle floating            | Mod+T   |          |
| Switch preset column width | Mod+R   |          |
| Center column              | Mod+C   |          |

Mod+T toggles float. When floating, it centres resizes window to 50% × 70%; when tiling, it resizes to 66.667% (Mod+R's third preset) and centres.

### Focus — window (Arrows) · column ends (Home/End)

| Action             | Bind      |
| ------------------ | --------- |
| Focus column left  | Mod+Left  |
| Focus window down  | Mod+Down  |
| Focus window up    | Mod+Up    |
| Focus column right | Mod+Right |
| Focus first column | Mod+Home  |
| Focus last column  | Mod+End   |

### Size — grow/shrink column width

| Action            | Bind      |
| ----------------- | --------- |
| Column width +10% | Mod+Equal |
| Column width -10% | Mod+Minus |

### Workspaces — jump by number

| Action              | Bind           |
| ------------------- | -------------- |
| Focus workspace 1-9 | Mod+1 .. Mod+9 |

### Mouse wheel (Mod held)

| Action               | Bind                 |
| -------------------- | -------------------- |
| Focus workspace down | Mod+WheelScrollDown  |
| Focus workspace up   | Mod+WheelScrollUp    |
| Focus column right   | Mod+WheelScrollRight |
| Focus column left    | Mod+WheelScrollLeft  |

---

## Layer 2 — Mod + Shift (move the window / amplify)

Same keys as Layer 1, one meaning: **carry the focused window, or push the action to the other dimension.**

### Move window / column

| Action            | Bind            | (Layer-1 pair) |
| ----------------- | --------------- | -------------- |
| Move column left  | Mod+Shift+Left  | focus left     |
| Move window down  | Mod+Shift+Down  | focus down     |
| Move window up    | Mod+Shift+Up    | focus up       |
| Move column right | Mod+Shift+Right | focus right    |

### Move column → workspace by number

| Action                       | Bind                       |
| ---------------------------- | -------------------------- |
| Move column to workspace 1-9 | Mod+Shift+1 .. Mod+Shift+9 |

### Amplified window ops (Shift flips the dimension)

| Key | Mod (width / column)       | Mod+Shift (height / window)    |
| --- | -------------------------- | ------------------------------ |
| F   | Maximize column            | Fullscreen window              |
| T   | Toggle floating (resizes)  | Switch focus floating ↔ tiling |
| R   | Switch preset column width | Reset window height            |
| C   | Center column              | Center visible columns         |
| =   | Column width +10%          | Window height +10%             |
| -   | Column width -10%          | Window height -10%             |

### Other Mod+Shift

| Action              | Bind            |
| ------------------- | --------------- |
| Show hotkey overlay | Mod+Shift+Slash |
| Screenshot region   | Mod+Shift+S     |

Window rules: hand-edit `niri/user/windowrules.kdl`.

---

## Layer 3 — Mod + Ctrl (aim at monitor / workspace)

Ctrl = "one container level up." Arrows now move between **monitors**; up/down moves between **workspaces**.

### Focus monitor

| Action              | Bind           |
| ------------------- | -------------- |
| Focus monitor left  | Mod+Ctrl+Left  |
| Focus monitor right | Mod+Ctrl+Right |

### Focus workspace by direction

| Action               | Bind          | Alt bind                           |
| -------------------- | ------------- | ---------------------------------- |
| Focus workspace down | Mod+Ctrl+Down | Mod+Page_Down, Mod+WheelScrollDown |
| Focus workspace up   | Mod+Ctrl+Up   | Mod+Page_Up, Mod+WheelScrollUp     |

---

## Layer 4 — Mod + Ctrl + Shift (move window to monitor / workspace)

Add Shift to Layer 3 = **carry the window into that monitor or workspace** (the same "Shift = take it with me" rule).

### Move column → monitor

| Action                       | Bind                 |
| ---------------------------- | -------------------- |
| Move column to monitor left  | Mod+Ctrl+Shift+Left  |
| Move column to monitor right | Mod+Ctrl+Shift+Right |

### Move column → workspace by direction

| Action                        | Bind                | Alt bind            |
| ----------------------------- | ------------------- | ------------------- |
| Move column to workspace up   | Mod+Ctrl+Shift+Up   | Mod+Shift+Page_Up   |
| Move column to workspace down | Mod+Ctrl+Shift+Down | Mod+Shift+Page_Down |

---

## Layer 5 — Mod + Alt (merge / split columns)

Alt is the odd-one-out modifier reserved for column consume/expel.

| Action                     | Bind          |
| -------------------------- | ------------- |
| Consume/expel window left  | Mod+Alt+Left  |
| Consume/expel window right | Mod+Alt+Right |

---

## Odds & ends

### Reorder workspaces (Mod + Bracket)

| Action              | Bind             |
| ------------------- | ---------------- |
| Move workspace up   | Mod+BracketLeft  |
| Move workspace down | Mod+BracketRight |

### Session / system

| Action                   | Bind              |
| ------------------------ | ----------------- |
| Power Menu               | Ctrl+Alt+Delete   |
| Exit niri                | Mod+F4            |
| System Monitor           | Ctrl+Shift+Escape |
| Shortcuts inhibit toggle | Mod+Escape        |

---

## Hardware keys (no Mod — media / brightness / screenshot)

These live on dedicated `XF86*` / `Print` keys, independent of the Mod layers.

### Screenshots

| Action            | Bind       | Alt bind                 |
| ----------------- | ---------- | ------------------------ |
| Screenshot region | Print      | XF86Launch1, Mod+Shift+S |
| Screenshot screen | Ctrl+Print | Ctrl+XF86Launch1         |
| Screenshot window | Alt+Print  | Alt+XF86Launch1          |

### Audio

| Action           | Bind                      | Alt bind      |
| ---------------- | ------------------------- | ------------- |
| Volume +3        | XF86AudioRaiseVolume      |               |
| Volume -3        | XF86AudioLowerVolume      |               |
| Mute             | XF86AudioMute             |               |
| Mic mute         | XF86AudioMicMute          |               |
| Play/pause media | XF86AudioPause            | XF86AudioPlay |
| Previous track   | XF86AudioPrev             |               |
| Next track       | XF86AudioNext             |               |

### Brightness

| Action        | Bind                  |
| ------------- | --------------------- |
| Brightness +5 | XF86MonBrightnessUp   |
| Brightness -5 | XF86MonBrightnessDown |
