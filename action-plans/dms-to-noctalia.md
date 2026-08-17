# DMS → Noctalia migration

Goal: replace DankMaterialShell with Noctalia on niri for better shell eyecandy, porting the
working DMS setup from `~/.dotfiles/niri-dms`. Window-level blur/animations already live in niri
(`user/theme.kdl`) and carry over untouched — the gain is in shell surfaces.

## Target version decision

**Noctalia v5** (`noctalia` 5.0.0-beta.8, Terra repo; beta.7 already in Fedora updates).
v4 (`noctalia-shell`/`noctalia-legacy` 4.7.7, Quickshell) is feature-frozen and dead-ended.
v5 = native C++/OpenGL ES rewrite: GLSL shaders, wallpaper transition effects, backdrop
blur layer for niri overview, per-surface blur via niri ≥ 26.04 layer rules (installed: 26.04).
Risk: beta churn — known regression: corner-radius customization bar-only (issue #2666).
Rollback: DMS stays installed; `dms.service` re-enable restores old shell.

## Architecture change

DMS writes niri config includes (`dms/*.kdl`) and manages them via GUI. Noctalia writes nothing
into niri config — all KDL becomes user-owned static files. Config: hand-written TOML in
`~/.config/noctalia/` (split files, alphabetically merged), GUI writes go to
`~/.local/state/noctalia/settings.toml`. Symlink-safe — dotfiles-friendly by design.

## Port map

### Direct ports (IPC binds, `user/binds.kdl`)

| DMS bind | Noctalia replacement |
|---|---|
| `clipboard toggle` (Mod+V) | `noctalia msg panel-toggle clipboard` |
| `settings focusOrToggle` (Mod+I) | `noctalia msg settings-toggle` |
| `dankdash wallpaper` (Mod+Y) | `noctalia msg panel-toggle wallpaper` |
| `control-center toggle` (Mod+S) | `noctalia msg panel-toggle control-center` |
| `notifications toggle` (Mod+M) | `noctalia msg panel-open <notifications-id>` — verify panel id post-install |
| `spotlight toggle` (Mod+A) | `noctalia msg panel-toggle launcher` |
| `powermenu toggle` (Ctrl+Alt+Del) | `noctalia msg panel-toggle session` |
| `lock lock` (Mod+L) | `noctalia msg session lock` |
| `audio increment/decrement/mute/micmute` | `volume-up/down/mute`, `mic-mute` |
| `mpris playPause/next/previous` | `media toggle/next/previous` |
| `brightness increment/decrement` | `brightness-up/down` |

### Settings ports (settings.json → TOML)

- Bar: same widget layout (workspaces + running apps | media | tray, control center, clock,
  notifications), transparency 0.7, top position.
- Theme: wallpaper source + tonal-spot algorithm (built-in M3 generator, no matugen dep),
  dark/light auto, IBM Plex Sans/Mono, corner radius 12.
- App theming: Noctalia templates cover GTK/Qt/Ghostty/Zen/Firefox/VSCode/Vesktop via
  community templates + `templates-apply`; `colors_changed` hook can run matugen for leftovers.
- Idle: `[idle.behavior.*]` — lock 15m, screen off 30m, suspend 1h; `lock_before_suspend = true`;
  fade grace via `pre_action_fade_seconds`.
- Night light: built-in scheduled nightlight replaces DMS gamma control.
- Wallpaper: repo `wallpapers/` dir, per-monitor + theme-mode dirs, blurred backdrop layer
  replaces DMS `wpblur.kdl` (niri `layer-rule` on `^noctalia-backdrop`).
- Lock + gaze: keep `pam_gaze` — new `/etc/pam.d/noctalia-lock` + `NOCTALIA_PAM_SERVICE` env
  (Noctalia defaults to `/etc/pam.d/login`).
- Alt-tab: `noctalia msg window-switcher` overlay; niri `recent-windows` highlight stays
  in `user/theme.kdl`.

### DMS-written KDL → static user KDL

| DMS file | Fate |
|---|---|
| `dms/colors.kdl` | `colors_changed` hook writes niri border colors from palette, or static colors |
| `dms/cursor.kdl` | static cursor block (Bibata-Original-Ice, 24) |
| `dms/windowrules.kdl` | copy 4 existing rules into `user/windowrules.kdl`, hand-edit henceforth |
| `dms/wpblur.kdl` | `noctalia-backdrop` layer rule |
| `dms/alttab.kdl` | dropped — highlight config already in `user/theme.kdl` |
| `dms/outputs.kdl` | empty today; outputs stay manual |

New: `user/noctalia.kdl` — `spawn-at-startup "noctalia"`, shell-surface blur layer rules
(`^noctalia-(bar|notification|dock|panel)`), float rule `app-id="dev.noctalia.Noctalia"`,
`honor-xdg-activation-with-invalid-serial` for notification actions.

## Cannot port (accepted losses + workarounds)

1. **Window-rules GUI** (Mod+Shift+W) — hand-edit `user/windowrules.kdl` instead.
2. **Display/output GUI** — niri `outputs` config by hand.
3. **AC-vs-battery idle profiles** — Noctalia has one idle profile; workaround: power-event hook
   rewrites idle TOML (hot-reloads), or accept the AC profile everywhere.
4. **dGPU sleep monitor widget** (cardwire) — no equivalent; `custom_button`/`text` widget
   polling cardwire, or Luau plugin later.
5. **ASUS control center widget** — use `rog-control-center` in system tray instead (asusctl).
6. **Battery alerts plugin** — emulate: `battery_percentage_changed` hook + `notification-show`.
7. **OCR scanner widget** — script bind: niri screenshot → tesseract → wl-copy.
8. **Voxtype bar overlay** — voxtype itself unaffected (systemd unit); only the bar indicator
   lost. Luau plugin candidate.
9. **Notepad** (Mod+N) — dropped; external app.
10. **MPRIS per-player volume keys** (Ctrl+Vol±) — no `media` volume IPC; rebind or drop.
11. **v5 beta regressions** — corner radius beyond bar not yet configurable.

## Steps

1. **Install** — `sudo dnf install noctalia`. Done: `noctalia --version` runs.
2. **Scaffold repo** — copy `niri/` from niri-dms (config.kdl minus `dms/` includes, keep
   `template/` + `user/` pattern), add `noctalia/` TOML dir, copy `wallpapers/`, `voxtype/`.
   Done: repo tree complete, nothing symlinked yet.
3. **Write Noctalia TOML** — bar, theme, idle, nightlight, wallpaper, hooks. Done: TOMLs lint
   (`noctalia msg config-reload` clean once running).
4. **Rewrite niri KDL** — binds (table above), `user/noctalia.kdl`, static
   cursor/windowrules/colors. Done: `niri validate` passes.
5. **Swap symlinks + services** — `systemctl --user disable dms.service`; re-point
   `~/.config/niri` and `~/.config/noctalia` to this repo; re-point voxtype links; relogin.
   Done: Noctalia bar up, DMS down.
6. **PAM + gaze** — write `/etc/pam.d/noctalia-lock`, export `NOCTALIA_PAM_SERVICE`.
   Done: lock unlocks via face.
7. **Hooks + workarounds** — battery-alert script, OCR bind, optional matugen hook.
   Done: each fires on trigger.
8. **Docs** — README (install walkthrough, style of niri-dms README), SHORTCUTS.md port,
   ROADMAP update. Done: fresh-machine instructions complete.

Steps 1 + 5 + 6 touch system state (dnf, systemd, /etc) — user go-ahead required before executing.
