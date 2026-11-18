// KWin script: enforce maximized state for a small list of apps at login,
// with geometry recomputed from the CURRENT available screen area.
// Two login-time failure modes covered:
// 1. Wayland session restore drops maximize state — listed windows arrive
//    unmaximized (max=0) out of place every login (seance) -> force-maximize.
// 2. A window restored/autostarted maximized gets its geometry from KWin
//    BEFORE the panel struts (and our on-login kscreen scale change) are in
//    place, so it extends under the left dock (upstream bug family: 515323,
//    523995, 514225) -> restore/maximize toggle recomputes it.
// Non-listed windows are left exactly as they are.
//
// Loaded by the kwin-remax user unit via org.kde.KWin /Scripting under the
// fixed plugin name below. No blind startup sleep: it sweeps immediately and
// then every 2s for ~20s, touching each victim window exactly once (dedup by
// internalId) — early-restore windows are fixed within ~2s, late autostarts
// are still covered. Then the script unloads ITSELF (callDBus works from
// plain JS; note plain-JS timers must use the `interval` PROPERTY +
// start(), because QJSEngine meta-object wrappers do not expose inherited
// slots like setInterval).
//
// Match on resourceClass: this KWin build has NO appId property (reads back
// as `undefined` even though the docs advertise it); resourceClass holds the
// app id for Wayland windows (seance -> com.seance.app).
//
// MaximizeMode (kwin effect/globals.h): Restore=0, Vertical=1, Horizontal=2,
// Full=3 (bitmask; "values are written to session files, don't change the
// order").
(function () {
    var PLUGIN = "kwin-remax"; // keep in sync with home.nix loadScript call
    // The only windows this script touches (Normal type only, dialogs left
    // alone). Add app-ids here.
    var REMAX = ["com.seance.app"];
    var seen = {};
    var passes = 0;
    var timer = new QTimer();

    function sweep() {
        passes++;
        var wins = workspace.windowList();
        for (var i = 0; i < wins.length; i++) {
            var w = wins[i];
            if (!w || w.minimized || w.windowType !== 0) {
                continue;
            }
            if (REMAX.indexOf(String(w.resourceClass)) === -1) {
                continue;
            }
            if (seen[w.internalId] !== true) {
                seen[w.internalId] = true;
                w.setMaximize(false, false);
                w.setMaximize(true, true);
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
