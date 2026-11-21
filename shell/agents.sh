# Agent session launchers. Shared across hosts.

# System-mode opencode in the repo with the short_summary prompt.
# BOX_HOST_PORT defaults to 8088 so the box can use the llama-embed
# service on host loopback; set it empty to disable or to another port.
nyvibe() {
  ( cd "$NYX_REPO" && BOX_HOST_PORT="${BOX_HOST_PORT-8088}" box -s opencode --prompt "read short_summary.md" "$@" )
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
