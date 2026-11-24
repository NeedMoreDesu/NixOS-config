# nyx: rebuild this machine's flake host. NYX_REPO and NYX_HOST are set by
# the per-host entry (hosts/<host>/bashrc.sh).
nyx() { sudo bash "$NYX_REPO/rebuild.sh" --host "$NYX_HOST" "$@"; }

# kde-restart: push the current Plasma config into the live session (the
# `nyx -k` path) without rebuilding. No sudo needed; the script finds the
# user manager itself if it is run as root anyway.
kde-restart() { bash "$NYX_REPO/scripts/kde_restart.sh" "$@"; }
