# Rebuild, generations and garbage collection

## `nyx` and `rebuild.sh`

`nyx` (`shell/nyx.sh`) is the normal entry point:

```
nyx    # shell/nyx.sh -> sudo bash ~/nixos_config/rebuild.sh --host "$NYX_HOST"
```

`rebuild.sh` runs `nixos-rebuild switch --flake ~/nixos_config#$HOST`, then
restarts the xremap user unit. The restart is deliberate: xremap has no live
config reload, and `nyx` uses `runuser` + `XDG_RUNTIME_DIR` so `systemctl
--user` reaches mika's manager rather than root's. A bad `xremap.yml` now
surfaces loudly as a failed unit instead of silently leaving stale keys in
place.

`-H/--host NAME` selects the host (defaults to `NYX_HOST`, then `hostname
-s`). Flags combine, e.g. `nyx -u -r`.

| Flag | Effect |
| --- | --- |
| `-u`, `--update` | Run the flake update first (see [pins](pins.md)). |
| `-r`, `--reboot` | Reboot after a successful switch. Wins if combined with `-l`. |
| `-l`, `--logout` | Apply the Plasma config, then end the KDE session instead of rebooting. |
| `-k`, `--kde` | Re-apply the Plasma config to the *live* session (skipped if `-l`/`-r` is also given). |

### `-l/--logout`

First runs `~/.local/share/plasma-manager/run_all.sh` as the user (same
runner as `-k`), then `qdbus org.kde.Shutdown /Shutdown logout`. Applying
the layout while the session is healthy stamps the generated scripts, so
the next login's autostart is a no-op instead of racing plasmashell; see
[the login autostart race](plasma.md#login-autostart-race-breaks-panels-and-apps-2026-11-21).
Plasma 6.8 dropped the old ksmserver logout slot, so `plasma-shutdown` is
the supported path; the session ends from inside, letting SDDM return to the
greeter.

Do **not** use `loginctl terminate-user`: with SDDM 0.21 the HUP-killed
`sddm-helper` reads as exit 1 = `HELPER_AUTH_ERROR` and the greeter never
restarts (black VT). KWin re-reads session bits on login, so a logout is
enough for session-scoped config.

### `-k/--kde`

Runs `~/.local/share/plasma-manager/run_all.sh` as the user with
`XDG_RUNTIME_DIR` set; failures are non-fatal.

Why it exists: plasma-manager only **writes** `kwinrc` (and other config
files), and KWin caches settings at startup. `nixos-rebuild`'s own activation
cannot touch the session bus — it only flips the `~/.local` symlinks. Without
`-k` (or a login), a changed panel or kwinrc setting does nothing until the
next session; the 2026-11-14 symptom was a top bar that ignored clicks after
`nyx` until the runner ran from inside the session.

`-k` also calls `org.kde.KWin.reconfigure` and `reconfigureEffect` on
`overview`/`windowview` — the same thing the Screen Edges KCM does after
saving. Otherwise a kwinrc change such as a disabled hot corner survives
until login.

To do the same without a rebuild, run `kde-restart` (a function in
`shell/nyx.sh` calling `scripts/kde_restart.sh`). It needs no sudo and is
useful after editing the config and switching by other means, or to repair
a session whose layout got lost.

## Generations and GC

After every successful switch, `nyx` caps system and home-manager generations
at the last 10 (`nix-env --delete-generations +10`) and then runs
`nix-collect-garbage`.

The weekly `nix-gc.timer` (`--delete-older-than 14d`, see `modules/nix.nix`)
remains as a fallback for weeks without rebuilds.

Important: the *collect* is the step that frees bytes. Build inputs are not
in the runtime closure, and `nix-env` alone only unlinks generations. The
local seance flake source is a `git+file` of a dirty worktree, which copies
the whole tree including its multi-GB `.zig-cache` into the store; that only
disappears via an explicit GC.

## Nix evaluation gotcha: `pkgs.system`

The warning

```
evaluation warning: 'system' has been renamed to/replaced by 'stdenv.hostPlatform.system'
```

fires on the attribute **access** `pkgs.system` — merely reading it warns,
and the warning carries no position. Bisect with:

```
nix eval --impure --expr 'f.inputs.nixpkgs.legacyPackages.x86_64-linux.system'
```

Use `pkgs.stdenv.hostPlatform.system` instead (this was fixed in
`modules/packages.nix` for the seance flake output). The `system =` argument
on `nixosSystem` was also legacy (same rename) and was dropped; the platform
now comes from `nixpkgs.hostPlatform` in `hardware-configuration.nix`, which
stays correct.

## Repository notes

`/etc/nixos/` is obsolete; this repo is the source of truth. No
`system.copySystemConfiguration` is needed with a git-backed flake.

The flake only sees committed/staged files, so `git add` before rebuilding
after adding new files.
