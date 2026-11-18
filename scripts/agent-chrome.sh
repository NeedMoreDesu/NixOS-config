#!/usr/bin/env bash
# CDP-enabled Chromium launcher for agent-browser (wrapped into an
# executable by modules/packages.nix, which substitutes the store paths).
#
# Own profile dir + fixed port so the debug endpoint never exposes the normal
# browser's tabs. Port stays on 127.0.0.1. --no-startup-window matters: a
# normal launch starts with an NTP tab, and agent-browser then opens a SECOND
# tab on attach, so every restart left a stray about:blank. With no startup
# window, the first agent command creates the only tab. --auto-connect also
# opens its own blank tab on attach, so attach via the fixed --cdp port.
set -eu

port=9222
profile="$HOME/.local/share/agent-chrome"
state="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-browser"
real=@browser@
# `ab` sets this to attach to the host's already-running dedicated browser
# instead of launching one inside the box.
cdp="${AGENT_BROWSER_CDP:-}"
started=0

# Session name: needed for the tab binding and for disabling the per-session
# stream server afterwards.
sess="${AGENT_BROWSER_SESSION:-default}"
prev=0
for a in "$@"; do
  if [ "$prev" -eq 1 ]; then
    sess="$a"
    prev=0
    continue
  fi
  case "$a" in
    --session) prev=1 ;;
    --session=*) sess="${a#--session=}" ;;
  esac
done

if [ -z "$cdp" ]; then
  if ! (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    @setsid@ -f @chromium@ \
      --user-data-dir="$profile" \
      --remote-debugging-port="$port" \
      --no-startup-window \
      --no-first-run \
      --no-default-browser-check \
      >/dev/null 2>&1
    started=1
  fi

  i=0
  until (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 100 ]; then
      echo "agent-chrome: Chromium never opened CDP port $port" >&2
      exit 1
    fi
    sleep 0.1
  done

  if [ "$started" -eq 1 ]; then
    # Fresh browser: every previous tab binding is dead, so drop the stale
    # target files (the live daemons fall back on their own; no pin-tab).
    rm -f "$state"/*.target
  fi
fi

target="${cdp:-$port}"
if [ "$started" -eq 0 ] && [ ! -e "$state/$sess.target" ]; then
  # Already running (or attached): a session with no binding would
  # otherwise make `open` navigate whatever tab is active. Give it its own
  # tab.
  "$real" --session "$sess" --cdp "$target" tab new >/dev/null 2>&1 || true
fi

rc=0
"$real" --cdp "$target" "$@" || rc=$?
# Streaming only feeds the (unused) observability dashboard; disable the
# session's stream server after each command so no random localhost port
# lingers. This also re-disables daemons that restarted between commands.
"$real" --session "$sess" --cdp "$target" stream disable >/dev/null 2>&1 || true
exit "$rc"
