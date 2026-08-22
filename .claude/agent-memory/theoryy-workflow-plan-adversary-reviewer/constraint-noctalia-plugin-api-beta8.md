---
name: constraint-noctalia-plugin-api-beta8
description: What the Noctalia v5 Luau plugin API is actually proven to do on this host vs. what plans assume — retained UI re-render clobbers widget state
metadata:
  type: project
---

Noctalia v5.0.0-beta.8 on this host; docs track beta.9, so plans citing docs are citing an
unshipped version. Plugin API surface is only *locally proven* for what the two working plugins
(`noctalia-plugins/char-picker`, `noctalia-plugins/power-control`) actually exercise.

- Proven: `ui.column/row/label/button/glyph/slider/separator`, `noctalia.readFile`,
  `noctalia.runAsync` (shell-string form; argv form needs api 24), `noctalia.state.get/set/watch`,
  `noctalia.notifyError`, `panel.render` / `panel.close`, string-name and closure callbacks.
- **Unproven locally:** `ui.input`, `ui.select`, `ui.toggle`, `ui.scroll`, `require()`,
  `writeFile`, `mkdirAll`, manifest `keyboard_focus` / `capture_keys`.
- The UI is retained but re-rendered as a whole tree via `panel.render(tree)`. Widget value props
  appear authoritative on re-render: power-control keeps a `draggedLimit` local override so a
  slider tracks a drag and clears it once the real value catches up. Expect the same to clobber
  text and cursor in `ui.input` on any re-render.
- `noctalia plugins lint` only cross-checks declared settings against `getConfig()` calls and
  flags entries pointing at a missing file. It does **not** check `ui.*` prop names, Luau
  semantics, or api-level compatibility.

**Why:** plans repeatedly cite "power-control is the proven local idiom" as a mitigation for
`ui.*` prop drift, but power-control proves none of the form primitives, and "lint passes" is
treated as a quality gate it cannot be.

**How to apply:** for any plan with a form-shaped panel, require a cheap throwaway spike that
renders the unproven primitives and answers whether a `render()` triggered by field B clobbers
in-progress typing in field A — *before* any high-effort UI step. Architecture follows the answer:
if it clobbers, all field state lives in one Luau draft table and `render()` fires only on
structural change. See [[trap-porting-dms-window-rules]].
