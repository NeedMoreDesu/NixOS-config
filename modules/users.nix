{ pkgs, ... }:
{
  users.users."mika" = {
    isNormalUser = true;
    description = "mika";
    extraGroups = [ "networkmanager" "wheel" "video" "render" ];
    packages = with pkgs; [
      kdePackages.kate
      emacs
      # Provides `cc` for Emacs' treesit-install-language-grammar, which
      # shells out to `cc` to build tree-sitter grammars.
      gcc
    ];
  };
}
