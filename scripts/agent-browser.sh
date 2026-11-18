#!/usr/bin/env bash
# Lazy front door for agent-browser (wrapped into an executable by
# modules/packages.nix, which substitutes the store paths).
#
# Starts agent-chrome on the first browser command, then hands off. Commands
# that never touch a page (skills/session/dashboard/install/close/...) skip
# the launch; an explicit --cdp/--auto-connect/connect means the caller
# manages the browser. AGENT_BROWSER_CDP (set by shell/agents.sh `ab`) is
# handled in agent-chrome: attach, don't launch.
set -eu

real=@browser@

sub=""
skip_value=0
direct=0
no_browser=0

for a in "$@"; do
  if [ "$skip_value" -eq 1 ]; then
    skip_value=0
    continue
  fi
  case "$a" in
    --cdp|--cdp=*|--auto-connect|--no-auto-connect|connect)
      direct=1
      ;;
    --help|-h|--version|-V)
      no_browser=1
      ;;
    --session|--profile|--headers|--executable-path|--args|--user-agent|--proxy|--proxy-bypass|--name|-n|--color-scheme|--provider|-p|--cdp-headers)
      skip_value=1
      ;;
    -*)
      ;;
    *)
      [ -z "$sub" ] && sub="$a"
      ;;
  esac
done

if [ "$direct" -eq 1 ] || [ "$no_browser" -eq 1 ]; then
  exec "$real" "$@"
fi

case "$sub" in
  ""|skills|session|dashboard|install|upgrade|doctor|close|stream)
    exec "$real" "$@"
    ;;
esac

exec @agent_chrome@ "$@"
