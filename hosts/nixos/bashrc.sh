# Per-host shell entry, sourced from ~/.bashrc.
#
# Only machine-specific values belong here; the shared launchers live in
# shell/ (box, nyx, agent sessions).
NYX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYX_HOST=nixos

# Host policy: terminal boxes can reach the local AI services at host-loopback
# 8088 (llama-embed) and 8089 (llama-inkling). `box -p PORT` adds more;
# BOX_DEFAULT_PORTS= (per invocation) disables the defaults.
BOX_DEFAULT_PORTS=8088,8089

. "$NYX_REPO/shell/box.sh"
. "$NYX_REPO/shell/nyx.sh"
. "$NYX_REPO/shell/agents.sh"

# Toggle the local llama.cpp services (llama-inkling, llama-embed); the
# command is installed by home/local-ai.nix.
alias ai='ai-toggle'
