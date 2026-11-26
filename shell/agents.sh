# Agent session launchers. Shared across hosts.

# System-mode opencode in the repo with the short_summary prompt.
# Goes through oc, so its flags work here too (e.g. `nyvibe -l` selects the
# local Inkling model); anything after the first unrecognised arg is passed
# to opencode, then the prompt is appended.
# Host default ports already include 8088 (llama-embed), 8089
# (llama-inkling) and 8090 (llama-vl); the explicit -p 8088 is deduped.
nyvibe() {
  ( cd "$NYX_REPO" && oc -s -p 8088 "$@" --prompt "read short_summary.md" )
}

# opencode in a box. Parses the box flags -s/--system, -x/--relaxed,
# -n/--network, -d/--dir and -p/--port, plus oc's -l/--local and -h/--help,
# before the command; everything after `--` (or the first other argument)
# goes to opencode. `oc -s` is system mode: host root read-only with the
# system allowlists (~/models ro, /dev/kfd) plus any -p holes. `oc -x` is
# relaxed system mode (host namespaces/devices/journal, HOME still masked).
# `oc -l` selects the local Inkling model. Use `oc -- -s SESSION` to reach
# opencode's own -s/--session flag.
oc_help() {
  cat <<'EOF'
oc: opencode in a box (project mode by default)

Usage: oc [box flags] [-l] [--] [opencode args]

Box flags:
  -s, --system     system mode (host root read-only, ~/models ro, /dev/kfd)
  -x, --relaxed    relaxed system mode (host namespaces/devices/journal,
                   /run/user; $HOME still masked)
  -n, --network    keep the host network namespace (agent-browser CDP)
  -d, --dir DIR    read-write-bind host DIR (repeatable; relative to ~)
  -p, --port PORT  forward host-loopback TCP PORT (repeatable)

oc flags:
  -l, --local      use the local Inkling model (-m inkling/inkling-2-mini)
  -h, --help       show this help and opencode's help

Everything after -- (or the first unrecognised argument) goes to opencode,
e.g. `oc -- -s SESSION`.
EOF
}

oc() {
  local -a box_flags=() oc_flags=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -s|--system|-x|--relaxed|-n|--network)
        box_flags+=("$1")
        shift
        ;;
      -d|--dir|-p|--port)
        if [ "$#" -lt 2 ]; then
          printf 'oc: %s needs a value\n' "$1" >&2
          return 2
        fi
        box_flags+=("$1" "$2")
        shift 2
        ;;
      -l|--local)
        oc_flags+=(-m inkling/inkling-2-mini)
        shift
        ;;
      -h|--help)
        oc_help
        printf '\n'
        opencode --help
        return
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done
  box "${box_flags[@]}" opencode "${oc_flags[@]}" "$@"
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
