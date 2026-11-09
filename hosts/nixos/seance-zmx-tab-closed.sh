#!/usr/bin/env bash
# seance [hooks] on-tab-close handler (installed to ~/.local/bin by home.nix).
#
# Kills the zmx session of every terminal that lived in the closed tab.
# Session names are seance-<pane-uuid>, one per terminal; the close hook
# fires on explicit tab close only (never on window quit or app exit), so
# quitting seance leaves sessions alive for the next launch to re-attach.
set -u

for uuid in ${SEANCE_PANE_UUIDS:-}; do
    zmx kill --force "seance-${uuid}" &
done
wait
exit 0
