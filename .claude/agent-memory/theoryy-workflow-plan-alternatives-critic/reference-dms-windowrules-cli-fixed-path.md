---
name: reference-dms-windowrules-cli-fixed-path
description: DMS's `dms config windowrules` CLI hardcodes its niri write target to ~/.config/niri/dms/windowrules.kdl — it cannot be reused as a storage backend for a user-owned rules file
metadata:
  type: reference
---

DMS (AvengeMedia/DankMaterialShell) exposes `dms config windowrules
list|add|update|remove|reorder` — a complete JSON CRUD backend over niri window rules,
tempting as a way to avoid writing a KDL parser.

It does not work as a backend for a user-owned rules file. The niri writable provider
derives its override path as `filepath.Join(configDir, "dms", "windowrules.kdl")` with
`configDir` fixed to `XDGConfigHome()/niri` — no flag, no env override
(`core/internal/windowrules/providers/niri_parser.go:659`,
`core/cmd/dms/commands_windowrules.go:347`). It *reads* rules from included files but can
only *write* `dms/windowrules.kdl`; foreign rules come back tagged with a different
`Source` and are effectively read-only.

Also: DMS's Go core is a separate module (`core/go.mod`) that would need a Go toolchain
built from source — `golang` is not installed on this machine.

**Why:** Evaluated 2026-08-22 as the "reuse over rebuild" candidate for a window-rules
editor that had to write `niri/user/windowrules.kdl`. Failed the primary requirement.

**How to apply:** Do not propose the `dms` CLI as a storage backend when the target file
is user-chosen. It is still useful as a *format oracle* — `niri_parser.go` (~1058 lines)
is the reference KDL emitter, and its output can be generated for comparison by running
the built binary under a scratch `XDG_CONFIG_HOME`. For actual reuse, see
[[reference-nirimod-prior-art]].
