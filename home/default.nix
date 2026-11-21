{
  imports = [
    ./plasma.nix
    ./seance.nix
    ./opencode.nix
    ./emacs.nix
    ./kwin-remax.nix
    ./embeddings.nix
  ];

  home.username = "mika";
  home.homeDirectory = "/home/mika";
  home.stateVersion = "26.05";
}
