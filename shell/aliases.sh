# Host-independent shell aliases. Shared across hosts.

# Toggle the local llama.cpp services (llama-inkling, llama-embed, llama-vl);
# the command is installed by home/local-ai.nix.
alias ai='ai-toggle'

# Keep the machine awake for the current session (Ctrl-C to stop). Screen lock
# is unaffected; add the "Manually Block Sleep and Screen Locking" widget if
# the screen should stay unlocked too.
alias caffeinate='systemd-inhibit --what=idle:sleep:handle-lid-switch --why="away" sleep infinity'
