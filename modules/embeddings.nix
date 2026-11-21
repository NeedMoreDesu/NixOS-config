{ pkgs, ... }:
{
  # Mesa/userspace drivers. HIP does not need Mesa to compute, but Vulkan
  # fallback and normal desktop acceleration do.
  hardware.graphics.enable = true;

  # Verification tools for the embedding service. The actual llama.cpp
  # build lives in home/embeddings.nix so it is scoped to mika's profile.
  environment.systemPackages = with pkgs; [
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];
}
