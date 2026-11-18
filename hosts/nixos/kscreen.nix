{
  # KScreen owns per-output scaling (plasma-manager has no kscreen module),
  # so re-assert this machine's scale on every login. Host-specific: the
  # output name (HDMI-A-1) differs between machines.
  systemd.user.services.kscreen-scale = {
    Unit = {
      Description = "Force 200% scale on HDMI-A-1";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/kscreen-doctor output.HDMI-A-1.scale.2";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
