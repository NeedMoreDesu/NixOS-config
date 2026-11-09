// KWin script: re-apply the maximize state of maximized windows so their
// geometry is recomputed from the CURRENT available screen area.
// Workaround for the login race: windows restored/autostarted maximized get
// their geometry from KWin BEFORE the panel's reserved struts (and our
// on-login kscreen scale change) are in place, so they end up extending
// under the left dock. Upstream bug family: 515323, 523995, 514225 (the 6.6
// "sinking" variant 515529 is fixed).
//
// Loaded by the kwin-remax user unit via org.kde.KWin /Scripting under the
// fixed plugin name below. No blind startup sleep: it sweeps immediately and
// then every 2s for ~20s, toggling each victim window exactly once (dedup by
// internalId) — early-restore windows are fixed within ~2s, late autostarts
// are still covered. Then the script unloads ITSELF (callDBus works from
// plain JS; note plain-JS timers must use the `interval` PROPERTY +
// start(), because QJSEngine meta-object wrappers do not expose inherited
// slots like setInterval).
//
// MaximizeMode (kwin effect/globals.h): Restore=0, Vertical=1, Horizontal=2,
// Full=3 (bitmask; "values are written to session files, don't change the
// order").
//
// POLICY pass (added 2026-11-09): session restore does NOT carry maximize
// state for Wayland clients — seance comes back every login as a plain
// max=0 window in an out-of-place geometry, so the re-apply pass above has
// no victim to fix (it only toggles windows that ARE maximized; X11-SM
// apps like emacs do restore max=3). Anything in POLICY_MAXIMIZE that
// arrives unmaximized (Normal windows only) gets force-maximized by the
// sweep instead. Cost: a deliberately unmaximized policy window at logout
// comes back maximized at login. Window identity matching MUST use
// resourceClass — this KWin build has NO appId property (reads back as
// undefined), even though the docs advertise it; resourceClass holds the
// app id for Wayland windows (seance -> com.seance.app).
(function () {
    var PLUGIN = "kwin-remax"; // keep in sync with home.nix loadScript call
    var POLICY_MAXIMIZE = ["com.seance.app"]; // matched against resourceClass
    var seen = {};
    var passes = 0;
    var timer = new QTimer();

    function sweep() {
        passes++;
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (!w || w.minimized) {
                continue;
            }
            var m = w.maximizeMode;
            if (m === 0 && w.windowType === 0 &&
                POLICY_MAXIMIZE.indexOf(String(w.resourceClass)) !== -1) {
                m = 3; // policy: this app must end up maximized
            }
            if (m !== 0 && seen[w.internalId] !== true) {
                seen[w.internalId] = true;
                w.setMaximize(false, false);
                w.setMaximize((m & 1) !== 0, (m & 2) !== 0);
            }
        }
        if (passes >= 10) {
            timer.stop();
            callDBus("org.kde.KWin", "/Scripting",
                     "org.kde.kwin.Scripting", "unloadScript", PLUGIN);
        }
    }

    timer.timeout.connect(sweep);
    timer.interval = 2000;
    timer.start();
    sweep();
})();
