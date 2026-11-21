# Per-host shell entry, sourced from ~/.bashrc.
#
# Only machine-specific values belong here; the shared launchers live in
# shell/ (box, nyx, agent sessions).
NYX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYX_HOST=nixos

# Host policy: llama-embed runs in every session, so every terminal box gets
# host-loopback 8088 by default. `box -p PORT` adds more; BOX_DEFAULT_PORTS=
# (per invocation) disables the default.
BOX_DEFAULT_PORTS=8088

. "$NYX_REPO/shell/box.sh"
. "$NYX_REPO/shell/nyx.sh"
. "$NYX_REPO/shell/agents.sh"
