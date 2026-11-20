{ ... }:
{
  services.syncthing = {
    enable = true;
    user = "mika";
    group = "users";
    dataDir = "/home/mika";
    configDir = "/home/mika/.config/syncthing";
    openDefaultPorts = true;
  };
}
