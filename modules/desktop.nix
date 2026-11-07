{
  services.xserver.enable = true;

  services.displayManager.sddm = {
    enable = true;
    enableHidpi = true;
  };
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    layout = "gb";
    variant = "mac";
    options = "caps:ctrl_modifier";
  };

  # Upstream Qt/KDE treat wheel-over-hover changing combo/spinbox/slider
  # values as a feature with no user-facing toggle (KDE bug #399324). Both
  # QQC2 styles we run hardcode it on; flip it in the packages so scrolling
  # over a dropdown just scrolls the page, everywhere.
  nixpkgs.overlays = [
    (final: prev: {
      kdePackages = prev.kdePackages.overrideScope (finalKde: prevKde: {
        qqc2-desktop-style = prevKde.qqc2-desktop-style.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            sed -i 's/wheelEnabled: true/wheelEnabled: false/' \
              org.kde.desktop/ComboBox.qml \
              org.kde.desktop/SpinBox.qml \
              org.kde.desktop/DoubleSpinBox.qml
            # slider uses a custom wheel handler (tickmarks workaround);
            # early-return so the wheel event passes through to the page
            sed -i 's/onWheel: wheel => {/onWheel: wheel => { return;/' \
              org.kde.desktop/Slider.qml
          '';
        });
        qqc2-breeze-style = prevKde.qqc2-breeze-style.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            sed -i 's/wheelEnabled: true/wheelEnabled: false/' \
              style/qtquickcontrols/SpinBox.qml
            sed -i 's/enabled: control.count > 1 \&\& (popup ? !popup.visible : true)/enabled: false/' \
              style/qtquickcontrols/ComboBox.qml
          '';
        });
      });
    })
  ];
}
