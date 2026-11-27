# Host-independent shell aliases. Shared across hosts.

# Toggle the local llama.cpp services (llama-inkling, llama-embed, llama-vl);
# the command is installed by home/local-ai.nix.
alias ai='ai-toggle'

# Keep the machine awake for the current session (Ctrl-C to stop). Screen lock
# is unaffected; add the "Manually Block Sleep and Screen Locking" widget if
# the screen should stay unlocked too.
alias caffeinate='systemd-inhibit --what=idle:sleep:handle-lid-switch --why="away" sleep infinity'

# Reload xremap's config (it can't live-reload): restart the session user
# service. nyx does the same as root after a switch; this is for hand edits.
alias xremap-reset='systemctl --user restart xremap'

# AOC AGON AG326UD Pixel Refresh over DDC/CI. See docs/aoc_agon_monitor.md.
alias agon='bash "$NYX_REPO/scripts/aoc-pixel-refresh.sh"'
