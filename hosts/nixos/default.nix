{
  imports = [
    ./hardware-configuration.nix
    ../../modules/audio.nix
    ../../modules/bluetooth.nix
    ../../modules/boot.nix
    ../../modules/desktop.nix
    ../../modules/locale.nix
    ../../modules/networking.nix
    ../../modules/nix.nix
    ../../modules/packages.nix
    ../../modules/printing.nix
    ../../modules/users.nix
  ];

  system.stateVersion = "26.05";
}
