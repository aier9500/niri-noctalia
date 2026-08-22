---
name: scope-calibration-plugin-size
description: Increment-size yardstick for noctalia-plugins/ — shipped plugins are ~130-230 LOC per Luau file; treat a proposed 1000+ LOC plugin as needing a phase split
metadata:
  type: feedback
---

Use the shipped plugins as the size yardstick when judging whether a proposed Noctalia plugin is one
increment or several. As of 2026-08, `power-control` and `char-picker` are the only two, and no
Luau file in either exceeds ~230 lines.

**Why:** There is no Luau test harness in this repo, so correctness rests on live smoke-testing.
That works at 200 LOC and stops working at 1500. A plan proposing a plugin an order of magnitude
larger than anything shipped is not just "bigger" — it crosses from verifiable-by-hand to not.

**How to apply:** Re-check the current sizes (`find noctalia-plugins -name '*.luau' | xargs wc -l`)
before citing the number; it goes stale. When a plan clears the bar by a lot, argue for a thin
vertical slice that exercises the whole path (parse -> edit -> emit -> validate) on a narrow field
set, rather than a horizontal split that leaves the feature unusable between phases.

**DMS-mirror calibration:** when a plan says "mirror DMS", the DMS window-rules feature alone is
~4900 LOC (1991 QML modal + 1097 QML tab + 1058 Go parser + 388 Go parser tests). "Mirror DMS"
sounds like a scoping decision but is a request to port a codebase larger than this entire repo's
plugin surface. Always cost it before accepting it.

Related: [[scope-trap-templates-vs-user]]
