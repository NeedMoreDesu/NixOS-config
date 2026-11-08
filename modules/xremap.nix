{
  # xremap: app-aware key remapping at the evdev layer (below XKB — see
  # xremap.yml for the policy + layering notes).
  services.xremap = {
    enable = true;

    # withKDE (KDE Wayland app-tracking for per-app rules) requires the
    # upstream KDE client, which cannot run as root. User service mode:
    # adds mika to input+uinput groups, uinput enabled, no root anywhere.
    serviceMode = "user";
    withKDE = true;
    userName = "mika";

    # Start with the graphical session; --watch picks up hotplugged
    # keyboards (the BT one reconnects later than boot).
    watch = true;

    # One file in the repo, not an attrset — easier to iterate by hand and
    # xremap can't live-reload anyway (restart the unit after edits).
    yamlConfig = builtins.readFile ./xremap.yml;
  };
}
