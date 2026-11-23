{ pkgs, ... }:
let
  # XKB groups are session-global: kscreenlocker's password field inherits the
  # active layout, so locking while ua(unicode) is selected types the password
  # in Cyrillic. Force the English layout when the session locks. This is a
  # heuristic: polkit/sudo prompts are not covered. See docs/keyboard.md.
  #
  # Use KWin's KeyboardLayouts D-Bus interface directly instead of invoking the
  # KGlobalAccel action: the action lives in KWin and only fires while its
  # shortcut plumbing is up. setLayout() switches the compositor's XKB group
  # unconditionally. The layout order is pinned in modules/desktop.nix as
  # "gb-mac-grave,ua", so index 0 is the English layout.
  forceEnglish = pkgs.writeShellScript "lock-layout-force-english" ''
    set -eu
    qdbus org.kde.keyboard /Layouts org.kde.KeyboardLayouts.setLayout 0
  '';

  runner = pkgs.writeShellScript "lock-layout-watch" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.dbus pkgs.coreutils pkgs.kdePackages.qttools ]}

    # stdbuf: dbus-monitor block-buffers stdout when piped, which would delay
    # the signal until the pipe fills.
    #
    # AboutToLock fires before kscreenlocker starts the greeter, so the
    # setLayout() call lands early; ActiveChanged(true) is the fallback for
    # lock paths that only emit the freedesktop signal.
    stdbuf -oL -eL dbus-monitor --session \
      "type='signal',interface='org.kde.screensaver',member='AboutToLock'" \
      "type='signal',interface='org.freedesktop.ScreenSaver',member='ActiveChanged'" \
    | while IFS= read -r line; do
        case "$line" in
          *"member=AboutToLock"* | *"boolean true"*) ${forceEnglish} ;;
        esac
      done
  '';
in
{
  systemd.user.services.lock-layout = {
    Unit = {
      Description = "Force the English XKB layout when the Plasma session locks";
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${runner}";
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
