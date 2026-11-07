{ pkgs, ... }:
{
  users.users."mika" = {
    isNormalUser = true;
    description = "mika";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      kdePackages.kate
      emacs
    ];
  };
}
