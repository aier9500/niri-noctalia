# ROADMAP

**Status: live (third attempt, 2026-08-17).** System swapped to Noctalia v5.0.0-beta.8:
`~/.config/niri` + `~/.config/noctalia` point here, `dms.service` disabled, daemon running.
Port-only policy this round — native modules/features only, no custom scripts or plugins.
No README until the setup stabilises.

## TODO

- [ ] App theming templates (GTK/Qt/Ghostty/Zen/VSCode) — deferred; remind user.
- [ ] screen-toolkit: install `wl-screenrec` (or `wf-recorder`) for region recording;
  fullscreen already works via gpu-screen-recorder.
- [ ] Verify gaze unlock after reboot (env set live but PAM stack untested).
- [ ] Maybe: simple custom Luau plugin — dGPU status (`cardwire get/set`) + ASUS battery
  charge threshold (advanced tweaks stay in rog-control-center).
- [ ] Remove DMS leftovers when confident: `dms` package, `~/.config/DankMaterialShell`.

## Change log

- 2026-08-17 — Blur behind open panels via niri layer-rule on `noctalia-panel-click-shield`
  (fullscreen shield surface). No dim: Noctalia has no scrim key, niri no dim effect —
  blur-only focus treatment. Git history wiped, repo re-committed fresh.

- 2026-08-17 — Config reorganized: theme.toml = all appearance ([theme], [shell] fonts,
  [shell.panel], wallpaper+backdrop, notification/OSD/lockscreen looks), misc.toml = behavior
  only, wallpaper.toml deleted, bar.toml standalone. Restored `open_near_click_control_center`
  (not a default, unlike the other deleted lines). screen_recorder traces purged (settings
  block, state dir, cache); catalog listing remains — no uninstall subcommand exists.

- 2026-08-17 — Panels glass→soft (glass was far more transparent than bar/OSD), opacities
  unified at 0.7, bar scale 0.9 (no font-size key exists), battery_rate removed (rate display
  deferred to power-control plugin), media title_scroll on_hover folded from GUI, media OSD
  toast off, lock_and_suspend gets 3s countdown (lock stays instant). GUI overrides pruned.

- 2026-08-17 — Power pill (battery % + aliased `battery_rate` widget showing draw/charge rate),
  session countdown 3s on logout/reboot/shutdown (no native hold-to-confirm), bar + OSD opacity
  0.8, placement rule simplified: only control-center (qs icons) attached, clipboard now
  centered + dropped from utilities pill.

- 2026-08-17 — Media widget hidden when nothing plays (`hide_when_no_media`). Panel placement
  split (finishing user's theme.toml experiment): bar-triggered panels (clipboard,
  control-center) attached + near-click; keybind-only panels (launcher, wallpaper, session)
  floating + screen-centered. No per-open-source switch exists in beta.8 — per-panel split
  is the equivalent given the current bar layout.

- 2026-08-17 — screen-toolkit live: replaces screen_recorder (disabled) in utilities pill
  (`alexander/screen-toolkit:widget`) and on Mod+Shift+R (`service all toggle` = open panel /
  stop recording). OCR/QR/color-picker/annotate now available from the panel.

- 2026-08-17 — Fixed "Unknown group": GUI bar-edit had written an end-lane override into
  settings.toml with the stale `group:quicksettings` name, masking the file config; override
  pruned. Lesson: GUI bar edits fork the whole lane into settings.toml — avoid GUI bar editor,
  or re-prune after. Screen-toolkit swap next (replaces screen_recorder, adds OCR).

- 2026-08-17 — Gaze unlock live (`/etc/pam.d/noctalia-lock` + `NOCTALIA_PAM_SERVICE`, daemon
  restarted with env). Groups renamed: `qs` (quick settings), new `utilities` island between
  tray and battery (clipboard, screen_recorder, voxtype status widget). Battery warning 20%,
  nightlight on by default. Voxtype community plugin enabled by user.

- 2026-08-17 — GUI settings folded into config files (user request: files = source of truth):
  bar end lane (tools island dropped, battery left of quicksettings, caffeine in pill),
  taskbar only_active_workspace, notification bottom_right 0.8, OSD bottom_center, lockscreen
  allow_empty_password + tint 0. settings.toml pruned to runtime state only (wallpaper
  selection/favorites, lockscreen widget layout, plugin registry). User moved bar to bottom.

- 2026-08-17 — Binds pass: Mod+N → notes panel (`panel-toggle noctalia/notes:panel`),
  Mod+Shift+R → recording toggle (`plugin noctalia/screen_recorder:service all toggle`, per
  plugin README); reset-window-height moved to Mod+Ctrl+R. Battery pill moved left of clock.

- 2026-08-17 — Bar pass 2: uniform 8px island gap, clock "%Y-%m-%d · %H:%M", tools pill
  (screen_recorder + notes plugin widgets), battery split out as own pill with percent (right of
  quick + clock), Mod+Period → launcher /emo (character search). Tooltips: no disable key in
  beta.8 (validator-probed; `interactive=false` would kill clicks too) — accepted for now.

- 2026-08-17 — Bar visual pass: floating long island (margin_edge 8, margin_ends 24), bar-wide
  capsules, quick-settings capsule group (network/bt/volume/brightness/battery, icons only)
  replaces control-center owl, workspaces dots (no numbers), clock ISO 24h.

- 2026-08-17 — Revived + swapped live: added `bar.toml` (DMS layout mirror: workspaces+taskbar |
  media | tray/control-center/clock/notifications, opacity 0.7), `[shell.panel]` glass mode +
  all panels attached + open-near-click. Symlinks re-pointed, dms.service disabled, noctalia
  daemon started, niri config reloaded. All bind IPC ids smoke-tested ok. PAM env commented out
  (file absent — ROADMAP leftover note was wrong). voxtype untouched (plain `~/.config/voxtype`).
- 2026-08-16 — Simplified into a standalone repo: `scripts/` + `noctalia/hooks.toml` +
  MIGRATION.md removed, DMS/niri-dms references purged from configs and docs (successor note
  stays), voxtype guide inlined into README, cleanup.sh DMS-overlay capture dropped.
- 2026-08-16 — First live attempt reverted after user testing; system re-pointed to niri-dms.
- 2026-08-16 — Repo built from niri-dms: binds rewritten to `noctalia msg`, shell-generated KDL
  folded into static user files, Noctalia v5 TOML configs written. `niri validate` passes.
- 2026-08-16 — Researched Noctalia v5: v4 (Quickshell) is dead-ended, v5 (native rewrite, beta.8)
  is the target; Noctalia manages no niri config, so all shell-side KDL is user-owned.
