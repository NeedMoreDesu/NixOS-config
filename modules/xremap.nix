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

    # Chain: hardware -> keyd (switcher hold-layer only) -> xremap -> KWin.
    # Grab ONLY keyd's virtual device; keyd owns the hardware (evdev grab is
    # exclusive). watch stays on so a keyd restart/reconnect re-attaches.
    deviceNames = [ "keyd" ];
    # Mark xremap's own output device as "virtual" (keyd skips vendor 0x0fac,
    # the same way it skips its own device) — without this keyd would grab it
    # and the two remappers would loop on each other's output.
    extraArgs = [ "--vendor" "0x0fac" ];
    watch = true;

    # One file in the repo, not an attrset — easier to iterate by hand and
    # xremap can't live-reload anyway (restart the unit after edits).
    yamlConfig = builtins.readFile ./xremap.yml;
  };
}
