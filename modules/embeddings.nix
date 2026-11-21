{ pkgs, ... }:
{
  # Mesa/userspace drivers. HIP does not need Mesa to compute, but Vulkan
  # fallback and normal desktop acceleration do.
  hardware.graphics.enable = true;

  # The agent box drops supplementary groups, so membership in render/video
  # is not enough there. logind's uaccess ACL keeps /dev/kfd usable by the
  # logged-in user (and the box) without making it world-writable.
  services.udev.extraRules = ''
    SUBSYSTEM=="kfd", KERNEL=="kfd", TAG+="uaccess"
  '';

  # Verification tools for the embedding service. The actual llama.cpp
  # build lives in home/embeddings.nix so it is scoped to mika's profile.
  environment.systemPackages = with pkgs; [
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
  ];
}
