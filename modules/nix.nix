{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Reclaim disk from old `nyx` rebuilds: weekly, prune profile generations
  # (system, home-manager, user profiles) older than 14d, then GC everything
  # no longer referenced. Profile generations are the roots, so pruning them
  # is what actually frees the old toplevels.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Hardlink identical files in the store.
  nix.optimise = {
    automatic = true;
    dates = "weekly";
  };
}
