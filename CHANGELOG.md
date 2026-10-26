# Changelog

## 2.0.3 — 2026-10-26

- **Security:** sync snapshots no longer follow a destination symlink. The sync
  folder is shared, so a peer could point the snapshot name at an owner-writable
  file outside it and have the next refresh overwrite that file. Snapshots are
  now written by `scripts/opencode_usage_snapshot.py`, which writes a new file
  next to the destination, fsyncs it, and renames it over the destination entry,
  leaving any symlink target untouched.
- Fixed the bounded sync scan introduced in 2.0.2. Its generated shell script was
  invalid, so the scan silently read nothing; snapshots are merged again. A new
  regression test rebuilds the script from `Main.qml`, lints it, and checks the
  per-file, file-count, and total-byte limits.
- Replaced `preview.png` with a current 1200×675 screenshot and linked it from
  the README.

## 2.0.2 — 2026-10-24

- Bounded synced aggregation input. Snapshot files over 1 MiB are skipped, at
  most 64 files and 16 MiB total are read, and each file is read to its
  measured size, so a shared sync folder cannot exhaust the shell's memory.
- Every panel text element now uses `Text.PlainText`, so model names, status
  strings, and synced snapshot data are never interpreted as rich text.

## 2.0.1 — 2026-10-22

- Removed the custom in-panel update checker. Plugin updates use Omarchy's
  standard `omarchy plugin update` flow, which shows the diff, validates the
  manifest, and rescans.
- Removed the panel's version/update footer and the plugin-specific update IPC
  methods.

## 2.0.0 — 2026-10-22

- **Breaking:** renamed the plugin ID from `markbusai.opencode-usage` to
  `zaheen4.opencode-usage` and moved it to its own repository,
  `zaheen4/opencode-usage`.
- Omarchy has no in-place plugin rename. Existing installs must remove the old
  plugin and add this one as a new plugin; settings are not migrated
  automatically.
- Added explicit upstream attribution for the original
  `markbus-ai/omarchy-opencode-usage` project. The original MIT copyright is
  preserved, and fork modifications are copyright Mir Zaheen Waseet.

## 1.1.0 — 2026-10-22

- Read OpenCode v2 databases (`session_v2` / `session_message`) as well as the
  legacy `session` / `message` layout.
- Made refreshes event-driven: inotify on the OpenCode database with a
  configurable throttle and an hourly safety fallback.
- Sped up the scanner with one token-subtree extraction per message, a cached
  result file, and separate quick/full passes.
- Added a manual **Check for updates** action to the panel, with a one-click
  fast-forward through Omarchy's validated plugin updater. Nothing polls for
  updates in the background.

## 1.0.0

- Initial release.
