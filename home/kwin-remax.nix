{ pkgs, ... }:
{
  # Login sweep enforcing maximized state for the REMAX app-id list in
  # assets/kwin-remax/remax.js (seance): Wayland session restore drops the
  # maximize flag, so seance arrives unmaximized out of place; windows that
  # DO arrive maximized may have geometry computed BEFORE the panel struts
  # (and our on-login kscreen scale change) exist, so they extend under the
  # left dock (upstream bug family 515323, 523995, 514225). Listed windows
  # are toggled maximized exactly once each; everything else is untouched.
  # Loaded via KWin's Scripting D-Bus API; the script sweeps immediately,
  # then every 2s for ~20s, then unloads itself — the unit itself is instant
  # (no sleeps here, measured: plain-JS timers need the interval PROPERTY +
  # start(); setInterval slot is not exposed to QJSEngine).
  systemd.user.services.kwin-remax = let
    script = ../assets/kwin-remax/remax.js;
    runner = pkgs.writeShellScript "kwin-remax-run" ''
      set -e
      q=${pkgs.kdePackages.qttools}/bin/qdbus
      id=$($q org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript ${script} kwin-remax)
      if [ "$id" = "-1" ]; then
        # a previous trigger is still sweeping: let it finish
        exit 0
      fi
      $q org.kde.KWin "/Scripting/Script''${id}" org.kde.kwin.Script.run
    '';
  in {
    Unit = {
      Description = "Enforce maximized state for REMAX app-ids at login (seance); strut-race geometry fixup";
      After = [ "graphical-session.target" "kscreen-scale.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${runner}";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
