{ plasma-manager, ... }:
{
  imports = [ plasma-manager.homeModules.plasma-manager ];

  programs.plasma = {
    enable = true;

    # Direct keyboard-layout selection (KWin's global shortcut actions, named
    # after the xkb layout descriptions: extraLayouts.description / evdev.xml).
    # Meta+Alt+N is free; Super rides the physical Ctrl key (xremap
    # Control_L->Super_L), so this is the Mac "Option+Cmd+N" muscle-memory
    # version. Alt+Space cycles (xkb option), and
    # Meta+Alt+K / Meta+Alt+L (next / last-used) are KWin defaults.
    shortcuts = {
      "KDE Keyboard Layout Switcher" = {
        "Switch keyboard layout to English (UK, Macintosh) with grave" = "Meta+Alt+1";
        "Switch keyboard layout to Ukrainian" = "Meta+Alt+2";
      };
      # kwin section keys = kglobalshortcutsrc action names.
      "kwin" = {
        "Switch One Desktop to the Left" = "Meta+Left";
        "Switch One Desktop to the Right" = "Meta+Right";
        "Window Maximize" = "Meta+Up";
        "Window Restore" = "Meta+Down";
        "Overview" = "Meta+Tab";
        # Meta+Tab is a DEFAULT secondary binding of the window switcher;
        # re-assert single bindings here so Overview owns Meta+Tab /
        # Meta+Shift+Tab exclusively.
        "Walk Through Windows" = "Alt+Tab";
        "Walk Through Windows (Reverse)" = "Alt+Shift+Tab";
        # KWin 6.5+ quick-tile actions DEFAULT-bind Meta+Up/Down/Left/Right,
        # colliding with the four above (Meta+Down fired Quick Tile Bottom,
        # not Window Restore). "none" in the custom field kills the default;
        # corners/bottom-left/right have no arrow defaults.
        "Window Quick Tile Top" = "none";
        "Window Quick Tile Bottom" = "none";
        "Window Quick Tile Left" = "none";
        "Window Quick Tile Right" = "none";
      };
    };

    # Idle policy: lock at 20m, panel power-off at 25m, suspend at 40m
    # (kwinrc/kcfg defaults were 5m/10m). Journal proof that powerdevil used
    # to auto-suspend unasked (Nov 8 16:40, Nov 9 01:47, 16:14) - now an
    # explicit, declared policy.
    powerdevil.AC = {
      turnOffDisplay.idleTimeout = 25 * 60;
      autoSuspend = {
        action = "sleep";
        idleTimeout = 40 * 60;
      };
    };

    configFile = {
      "kwinrc"."Xwayland"."Scale" = 2.0;
      # Klipper clipboard auto-mirror was tested and rejected (2026-11-07,
      # see the pasteboard branch's DESIGN.md §12); pinned false so
      # re-enabling it via the KCM doesn't silently become policy.
      "klipperrc"."General"."SyncClipboards" = false;
      # kscreenlocker Daemon.Timeout is in MINUTES (kcfg Double), Autolock
      # default true; LockGrace default 5s.
      "kscreenlockerrc"."Daemon"."Timeout" = 20;
      # All 8 legacy screen edges/corners pinned to None (Overview moved
      # to Meta+Tab); GUI-configured corners would otherwise drift. These
      # only cover the built-in actions (Show Desktop, KRunner, ...) -
      # effect-registered borders are separate, see Effect-overview below.
      "kwinrc"."ElectricBorders" = {
        Top = "None";
        TopRight = "None";
        Right = "None";
        BottomRight = "None";
        Bottom = "None";
        BottomLeft = "None";
        Left = "None";
        TopLeft = "None";
      };
      # The Overview effect registers its OWN screen edge: its kcfg
      # defaults BorderActivate to ElectricTopLeft, so the top-left corner
      # opened Overview even with every [ElectricBorders] entry None.
      # ElectricNone is the enum sentinel (9, what the Screen Edges KCM
      # writes for "No Action") and reserves no edge.
      "kwinrc"."Effect-overview"."BorderActivate" = "9";
    };

    # Mirrors ~/.config/plasma-org.kde.plasma.desktop-appletsrc:
    # left-edge panel with stock widget order.
    panels = [
      {
        location = "left";
        floating = true;
        opacity = "translucent";
        # plasma-manager has no option for this one yet; stored as
        # floatingApplets in the containment's [General] group.
        extraSettings = "panel.floatingApplets = true;";
        widgets = [
          {
            kickoff = { };
          }
          {
            iconTasks = {
              # Dock pins; list order = dock order. GUI pin/drag edits are
              # wiped by the next nyx (the declared section is rewritten).
              launchers = [
                "applications:com.seance.app.desktop"
                "applications:librewolf.desktop"
                "applications:SourceGit.desktop"
              ];
              # Global dock: running windows stay visible regardless of the
              # current virtual desktop/activity (defaults filter per desktop).
              behavior.showTasks.onlyInCurrentDesktop = false;
              behavior.showTasks.onlyInCurrentActivity = false;
            };
          }
          "org.kde.plasma.marginsseparator"
          # Keyboard layout indicator: standalone widget, NOT a tray item —
          # plasma-manager cannot configure widgets nested in the tray
          # (items.configs is upstream dead code, nix-community/plasma-manager#504),
          # and as its own widget it can pin displayStyle=flag (country-flag
          # emoji, rendered via KCountryFlagEmojiIconEngine + Noto Color Emoji).
          {
            keyboardLayout.displayStyle = "flag";
          }
          {
            systemTray = {
              items = {
                shown = [ ];
                # Plasmashell's PlasmoidRegistry auto-nests EVERY applet whose
                # metadata says X-Plasma-NotificationAreaCategory +
                # EnabledByDefault (keyboardlayout = Hardware/default-true),
                # so exclusion must be declared here, not just via GUI removal.
                # keyboardlayout is the standalone flag widget above; the
                # tray-nested clone is the duplicate this kills.
                extra = [
                  "org.kde.plasma.devicenotifier"
                  "org.kde.plasma.cameraindicator"
                  "org.kde.plasma.notifications"
                  "org.kde.plasma.manage-inputmethod"
                  "org.kde.plasma.clipboard"
                  "org.kde.plasma.mediacontroller"
                  "org.kde.plasma.brightness"
                  "org.kde.kscreen"
                  "org.kde.plasma.networkmanagement"
                  "org.kde.plasma.bluetooth"
                  "org.kde.plasma.printmanager"
                  "org.kde.plasma.volume"
                  "org.kde.plasma.battery"
                  "org.kde.plasma.weather"
                  "org.kde.plasma.dwellclicker"
                  "org.kde.plasma.keyboardindicator"
                  "org.kde.merkuro.contact.applet"
                ];
              };
            };
          }
          "org.kde.plasma.showdesktop"
          {
            pager = {
              general.displayedText = "desktopNumber";
            };
          }
        ];
      }

      # Thin top bar: one systemmonitor widget in a custom "textonly"-style
      # face (assets/plasma/ksysguard/sensorfaces/org.kde.mika.mutedtextonly)
      # shows related stats as grouped rows, then a separator and the
      # Bluetooth charge widget, then a spacer and the clock at the right
      # end. Why custom: the stock textonly face hard-codes the theme's
      # bright text color, and ksystemstats only publishes instantaneous
      # 500ms rates. The fork draws label+value in muted gray, rolls a 10s
      # average for the network/disk RATE rows (download/upload/read/write),
      # groups related sensors into one row, and renders used/total pairs
      # (RAM, VRAM) as "used / total". Labels via SensorLabels; sensor IDs
      # verified live against ksystemstats:
      # `qdbus --literal org.kde.ksystemstats1 /org/kde/ksystemstats1 allSensors`.
      # On this host gpu0 is the discrete Navi 48 (RX 9070) and gpu1 is the
      # Granite Ridge iGPU; the GPU row uses gpu0 so usage, VRAM and
      # temperature all refer to the same device.
      {
        location = "top";
        height = 30;
        opacity = "translucent";
        widgets = [
          {
            systemMonitor = {
              displayStyle = "org.kde.mika.mutedtextonly";
              # color is a REQUIRED submodule option here (no default).
              # Empty labels append the value to the row without a label
              # (temperatures, and the total half of a used/total pair).
              sensors = [
                {
                  name = "cpu/all/usage";
                  label = "CPU";
                  color = "110,140,150";
                }
                {
                  name = "cpu/all/maximumTemperature";
                  label = "";
                  color = "110,140,150";
                }
                {
                  name = "gpu/gpu0/usage";
                  label = "GPU";
                  color = "130,120,150";
                }
                {
                  name = "gpu/gpu0/usedVram";
                  label = "";
                  color = "130,120,150";
                }
                {
                  name = "gpu/gpu0/totalVram";
                  label = "";
                  color = "130,120,150";
                }
                {
                  name = "gpu/gpu0/temperature";
                  label = "";
                  color = "130,120,150";
                }
                {
                  name = "memory/physical/used";
                  label = "RAM";
                  color = "115,145,115";
                }
                {
                  name = "memory/physical/total";
                  label = "";
                  color = "115,145,115";
                }
                {
                  name = "network/all/download";
                  label = "↓";
                  color = "150,150,100";
                }
                {
                  name = "network/all/upload";
                  label = "↑";
                  color = "160,130,95";
                }
                {
                  name = "disk/all/read";
                  label = "R";
                  color = "160,105,105";
                }
                {
                  name = "disk/all/write";
                  label = "W";
                  color = "150,110,135";
                }
                {
                  name = "disk/all/usedPercent";
                  label = "DSK";
                  color = "140,140,140";
                }
              ];
              # Face config (org.kde.mika.mutedtextonly/General): one row per
              # related group, and no colored indicator at the row start.
              settings = {
                "org.kde.mika.mutedtextonly/General" = {
                  groupSensors = true;
                  showIndicators = false;
                };
              };
            };
          }
          # Separator between the system stats and the Bluetooth charge widget.
          "org.kde.plasma.marginsseparator"
          # Connected Bluetooth device charge, one label per device by type
          # (K keyboard, M mouse, H headphones; see the applet's
          # contents/tools/bt-battery.sh). Own applet because ksystemstats
          # has no battery sensors — UPower/BlueZ are the only sources.
          "org.kde.mika.btbattery"
          {
            panelSpacer = { };
          }
          {
            digitalClock = {
              date = {
                enable = true;
                # "14 Nov 2026"
                format = {
                  custom = "dd MMM yyyy";
                };
                position = "besideTime";
              };
            };
          }
        ];
      }
    ];
  };

  # Custom ksysguard sensor face used by the top-bar systemmonitor widget:
  # muted label/value text plus a 10s rolling average for the network/disk
  # rate rows (the stock textonly face can do neither).
  xdg.dataFile."ksysguard/sensorfaces/org.kde.mika.mutedtextonly".source =
    ../assets/plasma/ksysguard/sensorfaces/org.kde.mika.mutedtextonly;

  # Top-bar Bluetooth battery stat (org.kde.mika.btbattery). Plasma5Support's
  # executable data source runs contents/tools/bt-battery.sh, which intersects
  # the BlueZ connected set with UPower's charge levels, so only current
  # Bluetooth peripherals show up (a Magic Keyboard on USB does not).
  xdg.dataFile."plasma/plasmoids/org.kde.mika.btbattery".source =
    ../assets/plasma/plasmoids/org.kde.mika.btbattery;
}
