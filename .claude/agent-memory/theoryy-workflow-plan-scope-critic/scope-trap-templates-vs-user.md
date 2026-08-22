---
name: scope-trap-templates-vs-user
description: Recurring blast-radius trap — plans edit gitignored niri/user/* and forget the tracked niri/templates/* mirror, so the change never ships
metadata:
  type: feedback
---

When reviewing any plan that touches niri config, check whether it edits `niri/user/<file>.kdl`
without a matching edit to `niri/templates/<file>.kdl`.

**Why:** `.gitignore` line 2 is `niri/user/*` — the whole user dir is a per-machine, untracked copy
scaffolded via `cp -rn niri/templates/. niri/user/` (README.md:70-79). An edit landing only in
`user/` is invisible to git, lost on a fresh machine, and produces a half-migrated state: the
tracked half of the feature (e.g. a plugin enabled in `noctalia/misc.toml`, which IS tracked) ships
while its keybind does not, leaving the feature present but unreachable.

**How to apply:** Flag as a blast-radius finding, not a nitpick — the consequence is concrete and
silent. The fix is always the same: add the same edit to the `templates/` counterpart, and say
explicitly in the plan whether the template is meant to diverge. Note the asymmetry that makes this
easy to miss: `noctalia/` is tracked, `niri/user/` is not, and `niri/noctalia.kdl` is also ignored.

Related: [[scope-calibration-plugin-size]]
