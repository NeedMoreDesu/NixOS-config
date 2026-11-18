{
  # KScreen owns per-output scaling (plasma-manager has no kscreen module),
  # so re-assert this machine's scale on every login. Host-specific: the
  # output name (HDMI-A-1) differs between machines.
  systemd.user.services.kscreen-scale = {
    description = "Force 200% scale on HDMI-A-1";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/kscreen-doctor output.HDMI-A-1.scale.2";
    };
  };
}
