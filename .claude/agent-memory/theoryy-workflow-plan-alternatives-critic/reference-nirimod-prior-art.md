---
name: reference-nirimod-prior-art
description: NiriMod (srinivasr/nirimod) is the standing reuse answer for niri config GUI editing — GTK4 app with a window-rules page, include-aware write-back, symlink-following saves
metadata:
  type: reference
---

`srinivasr/nirimod` — GTK4/libadwaita Python config manager for niri. MIT, ~380 stars,
actively maintained (last push 2026-08-02). Install: `curl -sSL
https://raw.githubusercontent.com/srinivasr/nirimod/main/install.sh | bash`. Fedora
supported; only `uv` was missing locally.

Why it matters for this repo: it resolves `include` directives up to depth 5, tracks each
node's `source_file`, and writes each setting back to its file of origin
(`kdl_parser.py:save_niri_config_multi`), following symlinks. This repo's
`~/.config/niri` is a symlink into the dotfiles tree with 9 `include "user/*.kdl"` lines,
so NiriMod edits land as reviewable `git diff` in the repo. README names Noctalia and DMS
multi-file setups as explicitly supported.

Window-rules coverage (`nirimod/pages/window_rules.py`, ~1177 lines, has tests): match/
exclude, app-id, title, is-floating/is-active/is-focused, at-startup, opacity, open-
floating/maximized/fullscreen/focused, open-on-output/workspace, default-column-width,
default-window-height, default-column-display, block-out-from, geometry-corner-radius,
clip-to-geometry, min/max width/height, draw-border-with-background, background-effect,
default-floating-position, plus layer-rule.
Known gaps vs full niri set: variable-refresh-rate, scroll-factor, tiled-state,
is-active-in-column, is-window-cast-target, is-urgent, border/focus-ring off.
No CLI arg to deep-link to a page — it opens on the last-used page.

**How to apply:** Before planning any hand-built niri config editor (window rules,
keybinds, outputs, animations), check whether NiriMod already covers it. Verify the gap
list above is still current — it was measured 2026-08-22 and the project ships often.
See [[reference-dms-windowrules-cli-fixed-path]] for why the DMS CLI is not the reuse
answer here.
