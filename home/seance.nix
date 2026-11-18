{
  # Seance keyboard policy + appearance, declarative. NOTE: seance's Settings
  # window writes ~/.config/seance/config.toml via temp-file+rename, which
  # replaces this symlink with a plain file — GUI changes are NOT persistent
  # policy; make them in assets/seance/config.toml and nyx (seance also has
  # Ctrl+Shift+comma to live-reload its config).
  xdg.configFile."seance/config.toml".source = ../assets/seance/config.toml;
  # `force`: the clobbered plain file is throw-away GUI state (repo is the
  # source of truth by design), so re-link over it on every activation
  # instead of letting home-manager abort the switch with a clobber error.
  xdg.configFile."seance/config.toml".force = true;
}
