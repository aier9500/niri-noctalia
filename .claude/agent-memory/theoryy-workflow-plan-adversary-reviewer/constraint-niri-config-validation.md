---
name: constraint-niri-config-validation
description: Verified niri 26.04 config/validate semantics on this host — isolated-include validation trick, exit codes, KDL dialect quirks that break naive parsers
metadata:
  type: project
---

Any plan that writes `~/.config/niri/*.kdl` programmatically must validate a candidate
in isolation before touching the real file.

**Verified on this host (niri 26.04, 2026-08-22):**
- `niri validate` with no `-c` validates `$XDG_CONFIG_HOME/niri/config.kdl` and *does*
  resolve `include` directives into `user/*.kdl`. Exit 1 on failure, 0 on success.
  DEBUG lines go to stderr even on success — key on exit code, never on stderr being empty.
- Isolation trick: a temp dir with `config.kdl` containing only `include "candidate.kdl"`
  validates window-rule content with the same detection power as the full config, in ~19 ms.
  `open-on-workspace` / `open-on-output` are *not* cross-checked against other files, so
  nothing is lost by isolating.
- niri uses KDL **v1** booleans: `open-floating true` is valid, `#true` is a parse error.
- Constructs that are valid niri KDL and break Lua-pattern / line-oriented parsers:
  `/-window-rule { }` (slashdash-disabled — a naive parser silently re-enables it),
  `title="^Foo{2,3}bar$"` (braces inside a string defeat `%b{}`), `app-id="^has\"quote$"`
  (escaped quote defeats `"([^"]*)"`), one-line `window-rule { match ...; open-floating true; }`,
  `/* block comments */`, `r"raw strings"`.

**Why:** validating the whole config after writing is wrong — `noctalia.kdl` is machine-rewritten
by Noctalia on wallpaper change, so an unrelated transient error would trigger a spurious rollback
of the user's edit. Validate-before-write also removes the hot-reload truncated-read race.

**How to apply:** reject any plan using write → validate → restore-on-failure; require
render-candidate → validate-isolated → write. Require a negative-test corpus of the six
constructs above before accepting any hand-rolled KDL parser. See
[[constraint-noctalia-plugin-api-beta8]].
