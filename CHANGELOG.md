# Changelog

Notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Add new entries under **Unreleased** as you go; they move into a version
section when you release (see "Releasing" in the README).

## [Unreleased]

## [0.1.1] - 2026-11-27

First fixes from testing on a device (iSH with BusyBox 1.33.1, darkhttpd 1.13).

### Fixed
- `setup` and `start` failed with "still not a mount point" even though the
  iOS folder was mounted. BusyBox `mountpoint` can't see iSH's iOS mounts (they
  have the same device ID as their parent directory), so the script now checks
  `/proc/mounts` for a mount of type `ios`.
- Every failed `start` opened the picker and mounted the folder again on top of
  the previous mount. Picking the folder again in `setup` now removes all
  stacked mounts, and `status` reports when there's more than one.
- Typing something that isn't a valid directory at setup's mount point prompt
  (e.g. `./serve.sh start`) ended setup without saving anything. It now
  explains why and asks again.

### Changed
- The mount point may only contain letters, digits, `.`, `_`, `-` and `/`,
  so it can be matched exactly in `/proc/mounts`.

## [0.1.0] - 2026-11-27

First version. Tested with stand-ins for darkhttpd and iSH; not yet tested on
a device.

### Added
- `serve.sh` with `setup`, `start`, `stop` and `status`. Serves a folder
  mounted from the iOS Files app with darkhttpd, read-only, on `127.0.0.1`.
- `setup` mounts the folder you pick in iOS and saves your keepalive and
  logging choices; `--root`, `--port`, `--keepalive`/`--no-keepalive` and
  `--log`/`--no-log` override them.
- `autostart on|off` adds or removes a line in `~/.profile` so the server
  starts when iSH opens.
- `version` / `--version` / `-V`.
- `SHORTCUTS.md`: start the server from iOS Shortcuts or Siri, plus an
  optional SSH-based setup for start/stop/status Shortcuts.
