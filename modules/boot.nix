{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Cap boot-menu entries so old generations stop piling up after GC prunes
  # them; 20 keeps a generous rollback window.
  boot.loader.systemd-boot.configurationLimit = 20;
}
