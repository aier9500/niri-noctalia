---
name: noctalia-runasync-api
description: noctalia.runAsync has two call shapes with very different return types -- easy to conflate and a real bug source
metadata:
  type: reference
---

`noctalia.runAsync(cmd)` (no callback) returns a BOOL and runs detached --
no stdout/stderr/exitCode captured. `noctalia.runAsync(cmd, cb)` captures
output and calls `cb(result)` with `{exitCode, stdout, stderr}` once the
command finishes.

Treating the one-arg return as a result table (`result.exitCode`) is a
real crash: seen live in `~/.cache/noctalia/noctalia.log` as `attempt to
index boolean with 'exitCode'` in aier9500/window-rules before the fix
(2026-08-22), see [[window-rules-adversarial-fixes]].

`writeFile`/`mkdirAll` return `bool` (+ optional error string) -- also
easy to assume they throw instead of returning falsy.

Callback idiom reference implementation: `noctalia-plugins/power-control/panel.luau`.
