# nyx: rebuild this machine's flake host. NYX_REPO and NYX_HOST are set by
# the per-host entry (hosts/<host>/bashrc.sh).
nyx() { sudo bash "$NYX_REPO/rebuild.sh" --host "$NYX_HOST" "$@"; }
