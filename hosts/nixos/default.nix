{
  imports = [
    ./hardware-configuration.nix
    ./kscreen.nix
    ../../modules/audio.nix
    ../../modules/bluetooth.nix
    ../../modules/boot.nix
    ../../modules/desktop.nix
    ../../modules/embeddings.nix
    ../../modules/held-packages.nix
    ../../modules/home-manager.nix
    ../../modules/llm-agents.nix
    ../../modules/locale.nix
    ../../modules/mac-keys.nix
    ../../modules/networking.nix
    ../../modules/nix.nix
    ../../modules/packages.nix
    ../../modules/printing.nix
    ../../modules/syncthing.nix
    ../../modules/users.nix
    ../../modules/xremap.nix
  ];

  networking.hostName = "nixos";

  # The local llama.cpp service mlocks the ~16 GB Inkling model so the desktop
  # and opencode cannot evict its expert pages. The user manager starts with an
  # 8 MiB memlock limit, so raise it for all user services.
  systemd.services."user@".overrideStrategy = "asDropin";
  systemd.services."user@".serviceConfig.LimitMEMLOCK = "infinity";

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.05"; # Did you read the comment?
}
