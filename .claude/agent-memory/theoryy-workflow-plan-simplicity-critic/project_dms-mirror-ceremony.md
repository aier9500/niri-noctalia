---
name: dms-mirror-ceremony
description: Plans that "mirror DMS" tend to import DMS's cross-process architecture ceremony that a single-process Luau plugin does not need
metadata:
  type: project
---

When a plan in this repo says "mirror DMS", separate DMS's *product* decisions (which fields,
which UI sections) from its *architecture* decisions. DMS is a QML frontend talking to a
stateless Go CLI over RPC, so it needs stable rule IDs (`// @id=` comments), a full KDL
library parse, and byte-stable output. A Noctalia Luau plugin is one process holding one Lua
table — array index is identity, and the emitter is the only reader of its own output.

**Why:** the window-rules-plugin plan (2026-08-22) proposed porting `niri_parser.go`
(1058 lines) plus a 1991-line QML modal into two Luau files; roughly a third of that weight was
RPC-shaped ceremony with no in-plugin consumer.

**How to apply:** when reviewing a DMS-mirroring plan, ask of each mechanism "what would break
in a single process if this were dropped?" Flag stable-ID generation, byte-exact-output
done-conditions, and whole-block opaque preservation. See [[niri-feature-baseline]].
