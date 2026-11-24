# Per-host shell entry, sourced from ~/.bashrc.
#
# Only machine-specific values belong here; the shared launchers live in
# shell/ (box, nyx, agent sessions).
NYX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYX_HOST=nixos

# Host policy: terminal boxes can reach the local AI services at host-loopback
# 8088 (llama-embed), 8089 (llama-inkling) and 8090 (llama-vl). `box -p PORT`
# adds more; BOX_DEFAULT_PORTS= (per invocation) disables the defaults.
BOX_DEFAULT_PORTS=8088,8089,8090

. "$NYX_REPO/shell/box.sh"
. "$NYX_REPO/shell/nyx.sh"
. "$NYX_REPO/shell/agents.sh"

# Toggle the local llama.cpp services (llama-inkling, llama-embed, llama-vl);
# the command is installed by home/local-ai.nix.
alias ai='ai-toggle'

# Keep the machine awake for the current session (Ctrl-C to stop). Screen lock
# is unaffected; add the "Manually Block Sleep and Screen Locking" widget if
# the screen should stay unlocked too.
alias caffeinate='systemd-inhibit --what=idle:sleep:handle-lid-switch --why="away" sleep infinity'
