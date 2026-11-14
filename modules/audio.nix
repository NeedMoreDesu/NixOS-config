{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Prefer AAC on Bluetooth A2DP. PipeWire ranks ENABLED codecs by a
    # hard-coded order (LC3 > LHDC > LDAC > aptX HD > aptX > AAC > SBC), not
    # by the order in the list, so the only way to make AAC win is to leave
    # the higher-ranked codecs disabled. SBC stays as the mandatory A2DP
    # fallback for devices without AAC. Trade-off: LDAC/aptX-capable devices
    # will also land on AAC/SBC. `wpctl status` / `pactl list | grep
    # a2dp_codec` shows the codec actually negotiated.
    wireplumber.extraConfig."51-bluez-codecs" = {
      "monitor.bluez.properties" = {
        "bluez5.codecs" = [ "aac" "sbc" ];
      };
    };
  };
}
