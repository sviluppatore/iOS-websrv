#!/bin/sh
# serve.sh - serve a folder from the iOS Files app inside iSH, read-only,
# reachable only from this device (127.0.0.1), using darkhttpd.
#
# Settings are resolved in this order (later wins):
#   built-in defaults  ->  config file written by `setup`  ->  command-line flags
set -eu

# Semantic version (MAJOR.MINOR.PATCH). Bump by hand when releasing; see
# "Releasing" in README.md.
VERSION=0.1.0

CONF_FILE="$HOME/.config/ish-websrv.conf"
STATE_DIR="$HOME/.local/state/ish-websrv"
HTTPD_PID="$STATE_DIR/darkhttpd.pid"
KEEPALIVE_PID="$STATE_DIR/keepalive.pid"
URL_FILE="$STATE_DIR/url"
LOCATION_DEV=/dev/location
PROFILE="$HOME/.profile"
AUTOSTART_TAG='# ish-websrv autostart'

# Defaults
WEB_ROOT=/mnt/www
PORT=8080
ADDR=127.0.0.1
KEEPALIVE=yes
LOG=no
LOG_FILE="$STATE_DIR/access.log"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

usage() {
	cat <<EOF
serve.sh $VERSION

Usage: serve.sh <command> [flags]

Commands:
  setup    Pick the iOS folder to serve and save your preferences
  start    Start the server (mounts the folder first if needed)
  stop     Stop the server and the background keepalive
  status   Show what is running
  autostart on|off
           Add or remove a line in ~/.profile that runs 'start' whenever
           iSH opens (used by the iOS Shortcut; see SHORTCUTS.md)
  version  Print the version

Flags (setup saves them; start uses them for this run only):
  --root DIR       Mount point inside iSH (default: /mnt/www)
  --port N         Port to listen on (default: 8080)
  --keepalive      Keep iSH running in the background (uses location access)
  --no-keepalive
  --log            Write an access log to $LOG_FILE
  --no-log
EOF
}

# Read KEY=value lines. We parse instead of sourcing the file so that the
# config can only set known values, never run code.
load_config() {
	[ -f "$CONF_FILE" ] || return 0
	while IFS='=' read -r key value; do
		case $key in
			WEB_ROOT)  WEB_ROOT=$value ;;
			PORT)      PORT=$value ;;
			ADDR)      ADDR=$value ;;
			KEEPALIVE) KEEPALIVE=$value ;;
			LOG)       LOG=$value ;;
			'' | \#*)  ;;
			*)         warn "ignoring unknown setting '$key' in $CONF_FILE" ;;
		esac
	done <"$CONF_FILE"
}

# The *_SET variables record which choices came from flags, so setup
# only prompts for the ones you didn't pass.
parse_flags() {
	while [ $# -gt 0 ]; do
		case $1 in
			--root)
				[ $# -ge 2 ] || die "--root needs a directory"
				WEB_ROOT=$2; ROOT_SET=1; shift ;;
			--port)
				[ $# -ge 2 ] || die "--port needs a number"
				PORT=$2; shift ;;
			--keepalive)    KEEPALIVE=yes; KEEPALIVE_SET=1 ;;
			--no-keepalive) KEEPALIVE=no;  KEEPALIVE_SET=1 ;;
			--log)          LOG=yes; LOG_SET=1 ;;
			--no-log)       LOG=no;  LOG_SET=1 ;;
			-h | --help)    usage; exit 0 ;;
			*)              die "unknown flag: $1 (try --help)" ;;
		esac
		shift
	done
}

validate() {
	case $PORT in
		'' | *[!0-9]* | ??????*) die "port must be a number from 1 to 65535: $PORT" ;;
	esac
	if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
		die "port must be from 1 to 65535: $PORT"
	fi
	case $WEB_ROOT in
		/*) ;;
		*) die "root must be an absolute path: $WEB_ROOT" ;;
	esac
	case $KEEPALIVE in yes | no) ;; *) die "KEEPALIVE must be yes or no" ;; esac
	case $LOG in yes | no) ;; *) die "LOG must be yes or no" ;; esac
	[ "$ADDR" = 127.0.0.1 ] ||
		warn "listening on $ADDR, not 127.0.0.1: other devices may be able to reach this server"
}

# ask_yn "question" default  ->  prints yes or no
ask_yn() {
	if [ "$2" = yes ]; then hint='Y/n'; else hint='y/N'; fi
	printf '%s [%s] ' "$1" "$hint" >&2
	read -r reply || reply=
	case $reply in
		[Yy]*) echo yes ;;
		[Nn]*) echo no ;;
		*)     echo "$2" ;;
	esac
}

# running_pid PIDFILE PATTERN  ->  prints the PID and succeeds if that process
# is alive AND its command line contains PATTERN. The command-line check stops
# a stale pidfile (e.g. after iSH restarts and reuses PIDs) from matching an
# unrelated process.
running_pid() {
	[ -f "$1" ] || return 1
	pid=$(cat "$1")
	case $pid in '' | *[!0-9]*) return 1 ;; esac
	[ -r "/proc/$pid/cmdline" ] || return 1
	tr '\0' ' ' <"/proc/$pid/cmdline" | grep -qF -- "$2" || return 1
	echo "$pid"
}

# In iSH, `mount -t ios` ignores the source argument and opens the iOS
# folder picker instead.
mount_folder() {
	mkdir -p "$WEB_ROOT"
	echo "Choose the folder to serve in the iOS picker..."
	mount -t ios . "$WEB_ROOT" || die "mount failed (was the picker cancelled?)"
	mountpoint -q "$WEB_ROOT" || die "$WEB_ROOT is still not a mount point after mounting"
	echo "Mounted at $WEB_ROOT"
}

# Reading /dev/location keeps iOS from suspending iSH while it's in the
# background (e.g. while you're in Safari). iOS asks for location permission
# the first time.
start_keepalive() {
	running_pid "$KEEPALIVE_PID" "$LOCATION_DEV" >/dev/null && return 0
	if [ ! -e "$LOCATION_DEV" ]; then
		warn "$LOCATION_DEV not found (not running in iSH?); skipping keepalive"
		return 0
	fi
	nohup cat "$LOCATION_DEV" >/dev/null 2>&1 &
	echo $! >"$KEEPALIVE_PID"
	echo "Keepalive started (pid $!)"
}

stop_pid() { # PIDFILE PATTERN LABEL
	if pid=$(running_pid "$1" "$2"); then
		kill "$pid"
		echo "Stopped $3 (pid $pid)"
	else
		echo "$3 was not running"
	fi
	rm -f "$1"
}

save_config() {
	mkdir -p "$(dirname "$CONF_FILE")"
	cat >"$CONF_FILE.tmp" <<EOF
# Written by serve.sh setup. Edit by hand or re-run setup.
WEB_ROOT=$WEB_ROOT
PORT=$PORT
ADDR=$ADDR
KEEPALIVE=$KEEPALIVE
LOG=$LOG
EOF
	mv "$CONF_FILE.tmp" "$CONF_FILE"
}

cmd_setup() {
	if running_pid "$HTTPD_PID" darkhttpd >/dev/null; then
		die "the server is running; run 'serve.sh stop' first"
	fi

	if ! command -v darkhttpd >/dev/null 2>&1; then
		[ "$(ask_yn 'darkhttpd is not installed. Install it now with apk?' yes)" = yes ] ||
			die "darkhttpd is required"
		apk add darkhttpd
	fi

	if [ -z "${ROOT_SET:-}" ]; then
		printf 'Mount point inside iSH [%s]: ' "$WEB_ROOT" >&2
		read -r reply || reply=
		WEB_ROOT=${reply:-$WEB_ROOT}
	fi
	validate

	if mountpoint -q "$WEB_ROOT"; then
		if [ "$(ask_yn "$WEB_ROOT is already mounted. Pick a different iOS folder?" no)" = yes ]; then
			umount "$WEB_ROOT"
			mount_folder
		fi
	else
		mount_folder
	fi

	[ -n "${KEEPALIVE_SET:-}" ] ||
		KEEPALIVE=$(ask_yn "Keep iSH running in the background? (needs location permission, uses more battery)" "$KEEPALIVE")
	[ -n "${LOG_SET:-}" ] ||
		LOG=$(ask_yn "Write an access log to $LOG_FILE?" "$LOG")

	save_config
	echo "Saved settings to $CONF_FILE"
	echo "Run 'serve.sh start' to start the server."
}

cmd_start() {
	validate
	command -v darkhttpd >/dev/null 2>&1 ||
		die "darkhttpd not found; run 'serve.sh setup' (or 'apk add darkhttpd')"

	if pid=$(running_pid "$HTTPD_PID" darkhttpd); then
		echo "Already running (pid $pid) at $(cat "$URL_FILE" 2>/dev/null)"
		return 0
	fi

	mountpoint -q "$WEB_ROOT" || mount_folder
	if [ ! -r "$WEB_ROOT" ] || [ ! -x "$WEB_ROOT" ]; then
		die "cannot read $WEB_ROOT"
	fi

	mkdir -p "$STATE_DIR"
	rm -f "$HTTPD_PID" # stale: we just checked it isn't running
	if [ "$KEEPALIVE" = yes ]; then start_keepalive; fi

	set -- "$WEB_ROOT" --addr "$ADDR" --port "$PORT" --daemon --pidfile "$HTTPD_PID"
	if [ "$LOG" = yes ]; then set -- "$@" --log "$LOG_FILE"; fi
	darkhttpd "$@" || die "darkhttpd failed to start (is port $PORT already in use?)"

	# iSH is emulated and slow, so give the daemon a moment to write its pidfile.
	tries=0
	until pid=$(running_pid "$HTTPD_PID" darkhttpd); do
		tries=$((tries + 1))
		[ "$tries" -lt 5 ] || die "darkhttpd did not start; try running it in the foreground to see errors"
		sleep 1
	done

	echo "http://$ADDR:$PORT/" >"$URL_FILE"
	echo "Serving $WEB_ROOT at http://$ADDR:$PORT/ (pid $pid)"
	if [ "$LOG" = yes ]; then echo "Access log: $LOG_FILE"; fi
}

cmd_stop() {
	stop_pid "$HTTPD_PID" darkhttpd "server"
	stop_pid "$KEEPALIVE_PID" "$LOCATION_DEV" "keepalive"
	rm -f "$URL_FILE"
}

# Absolute path to this script, so the .profile line works from any directory.
script_path() (
	cd "$(dirname "$0")" && printf '%s/%s\n' "$(pwd)" "$(basename "$0")"
)

# Rewrite ~/.profile without our tagged line. `cat >` (not mv) keeps the
# file's permissions and any symlink intact.
remove_autostart_line() {
	[ -f "$PROFILE" ] || return 0
	grep -vF "$AUTOSTART_TAG" "$PROFILE" >"$PROFILE.tmp" || [ $? -eq 1 ]
	cat "$PROFILE.tmp" >"$PROFILE"
	rm -f "$PROFILE.tmp"
}

cmd_autostart() {
	case ${1:-} in
		on)
			path=$(script_path)
			case $path in
				*[\"\$\`\\]*) die "script path has characters unsafe for .profile: $path" ;;
			esac
			remove_autostart_line # avoid duplicates; refreshes the path if the repo moved
			printf '"%s" start %s\n' "$path" "$AUTOSTART_TAG" >>"$PROFILE"
			echo "Autostart on: iSH will run '$path start' when it opens."
			[ "$KEEPALIVE" = yes ] ||
				warn "keepalive is off, so the server stops answering once you leave iSH (run 'serve.sh setup' to change)"
			;;
		off)
			remove_autostart_line
			echo "Autostart off."
			;;
		*) die "usage: serve.sh autostart on|off" ;;
	esac
}

cmd_status() {
	echo "version:   $VERSION"
	if pid=$(running_pid "$HTTPD_PID" darkhttpd); then
		echo "server:    running (pid $pid) at $(cat "$URL_FILE" 2>/dev/null)"
	else
		echo "server:    stopped"
	fi
	if mountpoint -q "$WEB_ROOT"; then
		echo "folder:    mounted at $WEB_ROOT"
	else
		echo "folder:    not mounted ($WEB_ROOT)"
	fi
	if pid=$(running_pid "$KEEPALIVE_PID" "$LOCATION_DEV"); then
		echo "keepalive: running (pid $pid)"
	else
		echo "keepalive: stopped"
	fi
	if grep -qsF "$AUTOSTART_TAG" "$PROFILE"; then
		echo "autostart: on (~/.profile)"
	else
		echo "autostart: off"
	fi
	echo "saved settings: port=$PORT keepalive=$KEEPALIVE log=$LOG"
}

cmd=${1:-}
if [ $# -gt 0 ]; then shift; fi
load_config

case $cmd in
	setup)  parse_flags "$@"; cmd_setup ;;
	start)  parse_flags "$@"; cmd_start ;;
	stop)   [ $# -eq 0 ] || die "stop takes no flags"; cmd_stop ;;
	status) [ $# -eq 0 ] || die "status takes no flags"; cmd_status ;;
	autostart) [ $# -eq 1 ] || die "usage: serve.sh autostart on|off"; cmd_autostart "$1" ;;
	version | --version | -V) echo "$VERSION" ;;
	-h | --help | help) usage ;;
	*)      usage >&2; exit 2 ;;
esac
