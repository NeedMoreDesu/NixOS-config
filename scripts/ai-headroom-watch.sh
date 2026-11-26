#!/usr/bin/env bash
set -euo pipefail

# Raise llama-inkling's GPU headroom while a tracked GPU app is running.
# Started by llama-inkling.service via Wants= (no boot autostart) and stopped
# with it via PartOf=. The server must be started with --props.

url=${AI_HEADROOM_URL:-http://127.0.0.1:8089}
apps=${AI_HEADROOM_APPS:-godot:godot4:krita}
apps=${apps//:/ }
pct=${AI_HEADROOM_PCT:-40}
interval=${AI_HEADROOM_INTERVAL:-2}

# Wait for the server to become reachable; it may still be loading weights.
until curl -fsS --max-time 2 "$url/health" >/dev/null 2>&1; do
  sleep 2
done

set_headroom() {
  local value=$1
  if curl -fsS --max-time 2 -X POST "$url/props" \
      -H 'Content-Type: application/json' \
      -d "{\"gpu_headroom\":$value}" >/dev/null 2>&1; then
    echo "ai-headroom-watch: gpu_headroom=$value%"
    return 0
  fi
  echo "ai-headroom-watch: failed to set gpu_headroom=$value%" >&2
  return 1
}

running_app() {
  local app
  for app in $apps; do
    if pgrep -i -x "$app" >/dev/null 2>&1; then
      echo "$app"
      return 0
    fi
  done
  return 1
}

last=""
while true; do
  if app=$(running_app); then
    want=$pct
  else
    app=none
    want=0
  fi

  if [[ $want != "$last" ]]; then
    echo "ai-headroom-watch: $app running -> gpu_headroom=$want%"
    if set_headroom "$want"; then
      last=$want
    fi
  fi

  sleep "$interval"
done
