# iOS-websrv

Serve a folder from the iOS **Files** app through a local web server running in
[iSH](https://ish.app), and browse it in Safari on the same device.

- **Read-only.** Uses [darkhttpd](https://github.com/emikulic/darkhttpd), a single
  small static-file server with directory listings.
- **This device only.** Listens on `127.0.0.1`, so other devices on your Wi‑Fi
  can't reach it.
- **One POSIX `sh` script** (`serve.sh`), no other dependencies.

## Quick start

In iSH:

```sh
apk add git
git clone <this repo's URL> ~/iOS-websrv
cd ~/iOS-websrv

./serve.sh setup     # installs darkhttpd if needed, opens the iOS folder picker, asks your preferences
./serve.sh start
```

Then open <http://127.0.0.1:8080/> in Safari.

## Commands

| Command  | What it does |
|----------|--------------|
| `setup`  | Installs darkhttpd if missing, mounts the iOS folder you pick, asks about keepalive and logging, and saves your answers. Run it again to pick a different folder. |
| `start`  | Starts the server. If the folder isn't mounted (e.g. after iSH restarted), it opens the folder picker first. |
| `stop`   | Stops the server and the keepalive. Leaves the folder mounted. |
| `status` | Shows the server, mount, keepalive and autostart state. |
| `autostart on\|off` | Adds or removes a line in `~/.profile` that runs `start` whenever iSH opens. |

## Starting from iOS Shortcuts / Siri

See [SHORTCUTS.md](SHORTCUTS.md). In short: `./serve.sh autostart on`, then
make a Shortcut that opens iSH, waits a few seconds, and opens the URL in
Safari. An optional SSH-based setup adds stop/status Shortcuts.

## Flags

`setup` **saves** these flags. `start` uses them **for that run only**.
Any choice you pass as a flag to `setup` is not asked again.

| Flag | Default | Meaning |
|------|---------|---------|
| `--root DIR` | `/mnt/www` | Where the iOS folder is mounted inside iSH |
| `--port N` | `8080` | Port to listen on |
| `--keepalive` / `--no-keepalive` | on | Keep iSH running in the background (see below) |
| `--log` / `--no-log` | off | Write an access log to `~/.local/state/ish-websrv/access.log` |

Examples:

```sh
./serve.sh setup --root /mnt/site --no-log   # only asks about keepalive
./serve.sh start --port 9000 --log           # one-off overrides
```

## How it works / things to know

- **Keepalive.** iOS suspends iSH when it's not in the foreground, and that
  includes while you're using Safari. A suspended iSH means requests just hang.
  The keepalive runs `cat /dev/location > /dev/null` in the background, which
  iOS treats as a reason to keep iSH running. iOS asks for location permission
  the first time. It costs some battery; `./serve.sh stop` ends it. On an iPad,
  Split View with iSH and Safari side by side also works without it.
- **The mount doesn't survive restarting iSH.** iOS needs you to pick the
  folder again by hand, so `start` opens the picker if the folder isn't mounted.
- **Files.** Settings are in `~/.config/ish-websrv.conf` as plain
  `KEY=value` lines. The script parses this file rather than running it, so
  only known keys are used. Pidfiles and the log are in
  `~/.local/state/ish-websrv/`.
- **Bind address.** `ADDR=127.0.0.1` is deliberate. Changing it in the config
  makes the server reachable by anyone on your network, and the script warns
  you if you do.

## Troubleshooting

- **Safari hangs:** check `./serve.sh status`. If keepalive is stopped, location
  permission may have been denied (iOS Settings → iSH → Location).
- **The server won't start:** run it in the foreground to see darkhttpd's own
  error, e.g.
  `darkhttpd /mnt/www --addr 127.0.0.1 --port 8080`.
- **Listing is empty:** run `ls /mnt/www`. If that's empty too, the mount
  didn't take. Re-run `./serve.sh setup` and choose "y" to pick the folder
  again.

## Versioning and releasing

The version is in `VERSION=` near the top of `serve.sh` and follows
[Semantic Versioning](https://semver.org): bump **PATCH** for fixes,
**MINOR** for new features that don't change how existing commands behave,
and **MAJOR** for changes that do (e.g. renamed flags or a config format
change). While the version starts with `0.`, expect things to change.

Check the installed version with `./serve.sh --version`; it's also the first
line of `./serve.sh status`.

To release, by hand:

1. Change `VERSION=` in `serve.sh`.
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`
   and add a new empty `## [Unreleased]` above it.
3. Commit, then tag the commit and push the tag:

   ```sh
   git commit -am "Release vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

Tag the commit on the main branch after merging. A tag on a feature branch
points at the wrong commit if the branch is later squash-merged or rebased.
