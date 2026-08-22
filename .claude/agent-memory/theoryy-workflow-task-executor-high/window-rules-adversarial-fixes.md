---
name: window-rules-adversarial-fixes
description: aier9500/window-rules plugin's save pipeline was reworked 2026-08-22 to fix 5 adversarial-review findings -- async save, generation-guard, validation gaps
metadata:
  type: project
---

`noctalia-plugins/window-rules/` (rules.luau parser/serializer, panel.luau
UI, test_rules.lua suite) had 5 adversarial-review findings fixed
2026-08-22:

1. `M.save` treated `runAsync`'s bool return as a result table -- hard
   crash on every save (confirmed live in noctalia.log before the fix, see
   [[noctalia-runasync-api]]). Reworked to
   `M.save(pluginDataDir, realPath, segments, previousHash, callback)`
   using the two-arg callback form.
2. No write-result checking; a failed backup write could still overwrite
   the real file. Now every write/mkdir step is checked, backup failure
   aborts before the real file is touched.
3. Saving a rule with both App ID and Title blank produced a matchless
   `window-rule` block (parses back as opaque/uneditable, may match every
   window). `validateDraft` now requires at least one of the two.
4. `checkSize`'s fixed-pixel input had no ceiling (huge values silently
   wrapped via `string.format("%d")` overflow). Capped at `n < 2^31`;
   proportion capped to `(0, 1]`.
5. `onFocusedRuleClicked`'s async niri-msg callback unconditionally
   entered the edit screen, clobbering whatever the user opened meanwhile.

Fix for 1 and 5 shares one mechanism: a `generation` counter in
panel.luau, bumped on panel open/close and every screen switch, captured
before each async dispatch (`M.save`, the focused-window fetch), checked
in the callback before touching UI state.

Test suite grew from 55 to 67 assertions -- added write-pipeline coverage
under a stub `noctalia` global (installed before `dofile` in
test_rules.lua, since `rules.luau` only defines `M.save` when `noctalia`
is truthy at module-load time).

Live-verified on this host: plugin disable/enable cycle, panel open/close,
and one real `M.save` call (temporary debug branch in `onOpen`, removed
after) -- `~/.config/niri/user/windowrules.kdl` came out byte-identical,
one backup landed in
`~/.local/state/noctalia/plugins/data/aier9500/window-rules/backups/`, log
clean after the fix (the exact pre-fix crash string is visible earlier in
the same log, from before this session's fix).
