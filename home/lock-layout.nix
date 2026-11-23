{ pkgs, ... }:
let
  # XKB groups are session-global: kscreenlocker's password field inherits the
  # active layout, so locking while ua(unicode) is selected types the password
  # in Cyrillic. Force the English layout when the session locks. This is a
  # heuristic: polkit/sudo prompts are not covered. See docs/keyboard.md.
  forceEnglish = pkgs.writeShellScript "lock-layout-force-english" ''
    set -eu

    # The component name contains spaces, so it is not a valid D-Bus object
    # path; ask kglobalaccel for the real path instead of guessing
    # /component/<name>.
    path=$(qdbus org.kde.kglobalaccel /kglobalaccel \
      org.kde.KGlobalAccel.getComponent "KDE Keyboard Layout Switcher") || exit 0
    case "$path" in
      /component/*) ;;
      *)
        echo "lock-layout: unexpected component path: $path" >&2
        exit 0
        ;;
    esac

    qdbus org.kde.kglobalaccel "$path" \
      org.kde.kglobalaccel.Component.invokeShortcut \
      "Switch keyboard layout to English (UK, Macintosh) with grave"
  '';

  runner = pkgs.writeShellScript "lock-layout-watch" ''
    export PATH=${pkgs.lib.makeBinPath [ pkgs.dbus pkgs.coreutils pkgs.kdePackages.qttools ]}

    # stdbuf: dbus-monitor block-buffers stdout when piped, which would delay
    # the signal until the pipe fills.
    #
    # AboutToLock fires before kscreenlocker blocks global shortcuts, so the
    # invokeShortcut below still lands; ActiveChanged(true) is the fallback if
    # that race is lost (the call is then a no-op rather than a failure).
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
