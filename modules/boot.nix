{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Cap boot-menu entries so old generations stop piling up after GC prunes
  # them; 8 keeps a healthy rollback window.
  boot.loader.systemd-boot.configurationLimit = 8;
}
