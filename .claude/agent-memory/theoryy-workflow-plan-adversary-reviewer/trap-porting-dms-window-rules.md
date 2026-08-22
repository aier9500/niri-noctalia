---
name: trap-porting-dms-window-rules
description: DMS's window-rules code is lossy by design because DMS owns its own generated file — porting it to edit the user's hand-written config turns that into data loss
metadata:
  type: project
---

DankMaterialShell (DMS) is the reference for the niri window-rules editor, but two of its design
choices are only safe *because DMS writes its own file* (`~/.config/niri/dms/windowrules.kdl`,
header "Do not edit manually"). Reusing them against the user's hand-written
`niri/user/windowrules.kdl` converts them into silent data loss.

1. **Its reader is not portable.** DMS calls `kdl.Parse()` from `github.com/sblinch/kdl-go`.
   There is no parser to "port" — a Luau version means writing a KDL tokenizer from scratch.
2. **Its writer is deliberately lossy.** The parser's switch covers ~27 properties with no
   `default:` branch, so unknown nodes are dropped. The writer emits several booleans only when
   true (`open-maximized`, `clip-to-geometry`, `tiled-state`, `variable-refresh-rate`), so an
   explicit `false` disappears. It models `border`/`focus-ring` as only off/active-color.
   niri 26.04 additionally accepts `shadow { }`, `tab-indicator { }`, `baba-is-float`,
   `border { on; width; inactive-color; active-gradient }` — all verified valid, none modelled.

**Why:** the loss happens *inside* a rule the parser believes it fully claimed, so block-level
"preserve unparseable blocks verbatim" does not catch it, and the result still passes
`niri validate` — nothing downstream flags it.

**How to apply:** require property-granularity classification (any unmapped child node makes the
whole rule opaque and read-only) plus a parse→emit byte-identity invariant on untouched input.
Prefer "only manage rules the plugin created" over adopting hand-written rules. Reference source
lives at `core/internal/windowrules/providers/niri_parser.go` (note the `providers/` segment —
plans often cite the path without it); its `niri_parser_test.go` has 12 tests with literal
expected KDL, usable as goldens since Go is not installed here.
See [[constraint-niri-config-validation]].
