---
name: niri-feature-baseline
description: This machine runs niri 26.04 with background-effect support; verify niri feature claims before calling a plan's field list speculative
metadata:
  type: project
---

`niri --version` here is 26.04 (verified 2026-08-22) and it supports `background-effect`
(blur/xray/noise/saturation) — already used in `niri/user/theme.kdl` and
`niri/user/noctalia-integration.kdl`. `noctalia.json.decode` exists in the plugin API
(see `noctalia-plugins/char-picker/char.luau`), so parsing `niri msg -j ...` is cheap, not
machinery.

**Why:** almost flagged `background-effect` support and JSON handling as speculative
over-build in a plan review; both are real and in use.

**How to apply:** before arguing a niri property or plugin-API call is YAGNI, grep
`niri/` and the existing plugins for it. Absence from the current config is not absence from
the compositor. Re-check the version after a system update. See [[dms-mirror-ceremony]].
