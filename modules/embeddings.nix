{ pkgs, ... }:
{
  # Mesa/userspace drivers. HIP does not need Mesa to compute, but Vulkan
  # fallback and normal desktop acceleration do.
  hardware.graphics.enable = true;

  # bwrap drops supplementary groups, so membership in render/video does not
  # help inside the box. Give mika ownership of /dev/kfd so both the user
  # service and the box (same host uid) can open it, without making it
  # world-writable.
  services.udev.extraRules = ''
    SUBSYSTEM=="kfd", KERNEL=="kfd", OWNER="mika", MODE="0600"
  '';

  # Verification tools for the embedding service. The actual llama.cpp
  # build lives in home/embeddings.nix so it is scoped to mika's profile.
  environment.systemPackages = with pkgs; [
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];
}
