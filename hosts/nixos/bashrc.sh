# Per-host shell entry, sourced from ~/.bashrc.
#
# Only machine-specific values belong here; the shared launchers and aliases
# live in shell/ (box, nyx, agent sessions, aliases).
NYX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYX_HOST=nixos

# Host policy: terminal boxes can reach the local AI services at host-loopback
# 8088 (llama-embed), 8089 (llama-inkling) and 8090 (llama-vl). `box -p PORT`
# adds more; BOX_DEFAULT_PORTS= (per invocation) disables the defaults.
BOX_DEFAULT_PORTS=8088,8089,8090

. "$NYX_REPO/shell/box.sh"
. "$NYX_REPO/shell/nyx.sh"
. "$NYX_REPO/shell/agents.sh"
. "$NYX_REPO/shell/aliases.sh"
