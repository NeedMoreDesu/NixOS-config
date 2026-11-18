# Per-host shell entry, sourced from ~/.bashrc.
#
# Only machine-specific values belong here; the shared launchers live in
# shell/ (box, nyx, agent sessions).
NYX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NYX_HOST=nixos

. "$NYX_REPO/shell/box.sh"
. "$NYX_REPO/shell/nyx.sh"
. "$NYX_REPO/shell/agents.sh"
