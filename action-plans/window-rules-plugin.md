# Window-rules editor — Noctalia plugin

Goal: GUI editor for niri window rules, DMS-style, editing `niri/user/windowrules.kdl` in place
(live at `~/.config/niri/user/windowrules.kdl`), opened with `Mod+Shift+W`. No repo docs until the
user signs off the product.

Council 2026-08-22: four lenses, unanimous go-with-amendments; amendments folded in below.

## Packaging decision: Noctalia plugin

Noctalia v5 is a native C++ binary, zero Qt; plugins are Luau-only. DMS's editor is QML over a Go
CLI — its QML cannot run in Noctalia, and the `dms` CLI hardcodes its own target file
(`core/internal/windowrules/providers/niri_parser.go:659`), so it can never edit
`user/windowrules.kdl`. A standalone quickshell app would vendor DMS's `DankCommon` submodule +
theme + services and still hit the same CLI dead end. The Luau API (host plugin_api ≤ 23) covers
the need: unsandboxed `readFile`/`writeFile`, `runAsync` for `niri validate`/`niri msg`, form
primitives, floating panels, `require()`, and `noctalia msg panel-toggle` — the bind idiom
`binds.kdl` already uses.

Prior art: **NiriMod** (`srinivasr/nirimod`, GTK4 whole-config niri manager) already ships an
include-aware rules editor with validate-before-write. Rejected as the primary path — foreign GTK
window outside the shell, round-trips the entire 10-file config through its own writer, new
Python/uv runtime dep — but it is the cheap fallback if the plugin build stalls. User decides at
the gate whether to trial it first.

"Mirror DMS" = port its data model, output format, and UI structure; the reader is net-new (DMS
parses via the `kdl-go` library — there is nothing to port).

## Core design (council-amended)

- **Segment model.** The file parses into an ordered list of segments: `rule` | `opaque` |
  `comment/blank run`. Untouched segments re-emit **verbatim from their stored original text**;
  only rules the user creates or edits are serialized. Consequences: the hand-written header
  survives, rule order (semantically significant in niri — later wins) survives, and there is no
  wholesale "adoption" rewrite of the file.
- **Real tokenizer, not Lua patterns.** Character-scanning (~150 lines): string state incl.
  escapes and `r"raw"` strings, `//` and `/* */` comments, `/-` slashdash, `;` node terminators,
  brace depth tracked outside strings. Verified hostile corpus (all valid niri KDL): slashdashed
  rules, `{2,3}` regex braces inside strings, escaped quotes, one-line semicolon rules, block
  comments, raw strings.
- **Default-deny.** A rule containing any child node outside the managed set → opaque, shown
  read-only. Any construct the tokenizer cannot classify → whole file read-only for the session,
  editor still viewable. Every parser gap degrades safely instead of corrupting.
- **Tri-state booleans, explicit `false` emit.** DMS emits several bools only when true; niri
  accepts explicit `false`. Managed bools are unset/true/false and emit both values.
- **Identity.** Array index. `// @name=<name>` comment only on rules the user names; no `@id`
  (DMS needs ids for its cross-process CLI; this plugin holds the whole list in memory).
- **v1 field set** (covers 100% of the live file): matchers `app-id`, `title`; properties
  `open-floating`, `open-maximized`, `open-fullscreen`, `open-focused`, `open-on-workspace`,
  `open-on-output`, `opacity`, `default-column-width`, `default-window-height`, `block-out-from`.
  Everything else — tri-state match conditions, extra match blocks, excludes, background-effect,
  border/focus-ring, size constraints, floating position, the DMS conditions we'd exceed it on —
  stays opaque until the long-tail step. Deferral, not a cut: each later property = one parse
  case, one emit line, one widget.
- **Write pipeline** (order matters):
  1. Serialize candidate text in memory.
  2. `writeFile` it to `<pluginDataDir>/candidate/windowrules.kdl`; alongside it a one-line
     `candidate/config.kdl` containing `include "windowrules.kdl"`.
  3. `runAsync("niri validate -c <candidate config.kdl>")` — isolates validation from unrelated
     breakage elsewhere in the config; verified 19 ms, exit-code keyed (stderr has DEBUG noise
     even on success).
  4. Exit 0 → copy current file to `<pluginDataDir>/backups/windowrules-<timestamp>.kdl`
     (`readFile`+`writeFile`, never shell `cp`), then `writeFile` the real path. Non-zero →
     surface stderr, file untouched, form state kept.
  niri hot-reloads on the write and keeps last-good config on error; backups are paranoia, not a
  load-bearing restore path.
- **Concurrency/staleness.** `saveBusy` flag gates the pipeline (power-control's `modeBusy`
  idiom). Content hash captured at load, re-read + compare immediately before the real write;
  mismatch → refuse, offer reload.
- **UI.** Two screens in one floating panel (`keyboard_focus`; no `capture_keys` — it would
  swallow text input). List: cards (name, match summary, action chips), edit / delete / up-down
  reorder across the global segment order, Add + Add-for-focused. Edit: DMS's section order for
  the v1 fields. App-id picker from `niri msg -j windows`, degrading to free text on failure.
  Field state lives in a `draft` table; `onChange` writes to `draft` without re-render; `render()`
  only on structural change; `key =` on every dynamic list node (spike confirms the constraints).
- **Goldens.** Fixture files transcribed from DMS `niri_parser_test.go`
  (`TestNiriSetAndLoadDMSRules`, `TestFormatSizeProperty`,
  `TestNiriExcludesSurviveEditOfOtherRule`) — Go isn't installed, so the tests are the only
  runnable-free oracle for DMS's format.

## Deliverables

```
noctalia-plugins/window-rules/
  plugin.toml      # panel: floating, keyboard_focus; plugin_api 22
  rules.luau       # tokenizer, segment model, serializer, write pipeline
  panel.luau       # list + edit screens
  fixtures/        # golden KDL + hostile corpus (used by step-1 self-test)
niri/templates/binds.kdl  # tracked copy of the bind (niri/user/* is gitignored)
niri/user/binds.kdl       # Mod+Shift+W { spawn "noctalia" "msg" "panel-toggle" "aier9500/window-rules:panel"; }
noctalia/misc.toml        # + "aier9500/window-rules" in [plugins] enabled
```

`niri/templates/windowrules.kdl` stays hand-written; per-machine files convert nothing — the
segment model edits in place.

## Steps

Status 2026-08-22: 0–4a done + adversarial review (5 findings fixed; 67-assertion suite green;
one live save verified byte-identical with backup). Open: human click-through, user sign-off,
then docs + commit; 4b after sign-off.

| # | Step | Owner | Effort | Done when | Depends |
|---|---|---|---|---|---|
| 0 | UI spike: throwaway panel with `ui.input`/`ui.select`/`ui.toggle` in `ui.scroll`, `require()` of a second file, `writeFile`+`mkdirAll`; record working prop names; answer: does input A survive a render triggered by B? does `key=` preserve input identity? | task-executor-medium | medium | Both questions answered in writing; primitives confirmed on beta.8 | — |
| 1 | `rules.luau`: tokenizer, segment model, serializer, write pipeline | task-executor-high | high | Parse→emit of the untouched live file (on a copy) is byte-identical; hostile corpus round-trips byte-identical or degrades read-only; fixture rule matches golden; candidate-validate rejects a bogus property | — |
| 2 | `plugin.toml` + stub `panel.luau` (single label) + `misc.toml` enable + bind in both `binds.kdl` files | task-executor-medium | medium | `noctalia plugins lint` passes; plugin enabled in `noctalia msg plugins list`; `Mod+Shift+W` toggles the stub; template edit shows in `git status` | 0 |
| 3 | `panel.luau` list screen: cards, edit/delete/up-down, Add, Add-for-focused | task-executor-high | high | Live rules render as cards; delete and reorder rewrite only the affected segments; opaque rules show read-only | 1, 2 |
| 4a | `panel.luau` edit screen: v1 fields, app-id picker, draft-table state, save through pipeline | task-executor-high | high | Create/edit/save round-trips every v1 field; second save of unchanged rule is byte-identical | 3 |
| 4b | Long tail: remaining DMS-parity fields, section by section | task-executor-high | high | Deferred — starts only after user sign-off on v1 | 5 |
| 5 | Verify: lint, live smoke (bind → panel → add float rule for running app → niri applies → edit → delete), staleness guard demo, backup present | player-coach | medium | All checks pass live; diff of the live file across the session touches only intended lines | 4a |

Lint only checks settings declarations and entry-file existence — the real gates are the step-0
spike and step-5 smoke.

No ROADMAP/README updates until the user reviews and signs the product.

## Risks

- Parser bug class → neutralized by default-deny + verbatim segments: bugs degrade to read-only,
  never rewrite.
- `ui.*` prop drift docs(beta.9) vs host(beta.8) → step-0 spike is the gate; power-control is the
  idiom anchor.
- Re-render clobbering text input mid-typing → draft-table architecture; spike confirms.
- Panel size ceiling (manifest-fixed) → single `ui.scroll` root, ~500×600.
