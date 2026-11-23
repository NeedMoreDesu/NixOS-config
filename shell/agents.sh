# Agent session launchers. Shared across hosts.

# System-mode opencode in the repo with the short_summary prompt.
# Host default ports already include 8088 (llama-embed) and 8089
# (llama-inkling); the explicit -p 8088 is deduped.
nyvibe() {
  ( cd "$NYX_REPO" && box -s -p 8088 opencode --prompt "read short_summary.md" "$@" )
}

# opencode in a box. Parses the box flags -s/--system, -n/--network and
# -p/--port before the command; everything after `--` (or the first other
# argument) goes to opencode. `oc -s` is system mode: host root read-only
# with the system allowlists (~/models ro, /dev/kfd) plus any -p holes.
# Use `oc -- -s SESSION` to reach opencode's own -s/--session flag.
oc() {
  local -a box_flags=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -s|--system|-n|--network)
        box_flags+=("$1")
        shift
        ;;
      -p|--port)
        if [ "$#" -lt 2 ]; then
          printf 'oc: %s needs a port\n' "$1" >&2
          return 2
        fi
        box_flags+=("$1" "$2")
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  box "${box_flags[@]}" opencode "$@"
}

# Agent-browser session: project-mode opencode with the host network so the
# agent-browser skill can drive the host's dedicated Chromium (CDP 9222).
# Results live in a stable workspace outside the repo. Remaining args are the
# first prompt (joined); no args starts the TUI without one.
ab() {
  local dir="$HOME/ab_workspace" prompt="$*"
  mkdir -p "$dir" || return 1
  # Ensure the dedicated host Chromium is up, then drop the helper session:
  # the browser is externally owned and stays, but the daemon (and its tab)
  # do not linger. The wrapper disables the stream server on the way out.
  agent-browser --session ab tab list >/dev/null 2>&1 || true
  agent-browser --session ab close >/dev/null 2>&1 || true
  local -a oc=(opencode)
  [ -n "$prompt" ] && oc+=(--prompt "$prompt")
  ( cd "$dir" && AGENT_BROWSER_CDP=9222 box -n bash -c '
      mkdir -p -m 700 "$HOME/.run" || exit 1
      export XDG_RUNTIME_DIR="$HOME/.run"
      exec "$@"
    ' ab "${oc[@]}" )
}
