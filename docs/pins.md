# Flake inputs, updates and package holds

## Flake inputs

| Input | Notes |
| --- | --- |
| `nixpkgs` | `nixos-unstable`. |
| `nixpkgs-held` | Frozen anchor for the package holds. Never `-u`'d; moves only via `flake-rollback.sh --hold`. |
| `llm-agents` | numtide's `llm-agents.nix`; does **not** follow nixpkgs (see below). |
| `home-manager` | Home Manager. |
| `plasma-manager` | Plasma config generation. |
| `seance` | `git+https` with `?submodules=1` for vendored ghostty; `inputs.nixpkgs.follows = "nixpkgs"`. |
| `xremap-flake` | `github:xremap/nix-flake`: NixOS/HM module + its own pinned xremap build; does **not** follow nixpkgs. |

## Updating

`nyx -u` runs `scripts/flake-update.sh`, which updates every **root** input
except those in `HOLD_INPUTS` and then prints the held pins. It commits
`flake.lock` and prints one line per held package (held version vs what
current nixpkgs would give; equal means the hold is redundant).

`HOLD_INPUTS` now contains only `nixpkgs-held`, the frozen anchor used by the
per-package holds. `nixpkgs` itself is **not** held: single known-bad nixpkgs
packages are frozen through `modules/held-packages.nix` instead.

To update one input manually:

```
nix flake update <input>
```

Git is needed. A `sudo`-free shell may lack git until the systemPackages
rebuild lands; `nix-shell -p git` works in the meantime.

## Per-package holds

`scripts/held-packages.nix` is THE hold list: one nixpkgs attribute name per
line with a rationale comment. It is imported by `modules/held-packages.nix`
and read by both maintenance scripts.

`modules/held-packages.nix` overlays every listed name with the
`nixpkgs-held` input's build. An empty list means no overlay. The held
derivation brings its old-tree dependencies beside the new ones, so holds are
for **standalone binaries only** — never ABI libraries, interpreter
ecosystems, or packages with NixOS/home-manager modules.

Currently held:

- `zmx 0.8.1` — zmx 1.0.1 SIGABRTs on every session daemon shutdown, i.e.
  every zmx cleanup shortcut. Release once the fix (upstream zmx f5d604e)
  reaches nixpkgs. `nyx -u` prints `zmx held 0.8.1 -> nixpkgs would give
  <ver>`.

Manage holds with `scripts/flake-rollback.sh`:

- `--hold <pkg> [ref]` — per-package rollback: re-pin `nixpkgs-held` to that
  ref's nixpkgs and append `<pkg>` to the hold list. One shared anchor, so
  existing entries move with it (shown first).
- `--release <pkg>` — drop the entry. With an empty list, retire the
  `nixpkgs-held` input from `flake.nix` and `HOLD_INPUTS`.

### Why zmx is held

Every seance cleanup shortcut ends in `zmx kill`. In zmx 1.0.1 the daemon's
shutdown path (`Daemon.run` → `Daemon.deinit`) frees a caller-owned
`socket_path` with its post-fork C allocator, and glibc aborts
(`_int_free_merge_chunk`). zmx 0.8.1 is clean (verified: `attach` + `kill
--force` makes no core).

The original response was a wholesale nixpkgs rollback (pinned at f4a03c0,
zmx 0.8.1, so `nyx -u` could not pull it back). On 2026-11-14 that was
replaced by the per-package hold: zmx is overlaid from the frozen
`nixpkgs-held` input (same f4a03c0) while listed in
`scripts/held-packages.nix`, and `nixpkgs` updates freely again.

## Rolling back inputs

`./scripts/flake-rollback.sh [ref]` is the interactive pin rollback. The
default ref is the parent of the last lock commit. It:

- diffs `flake.lock` against the ref and lists every changed root input with
  rev/date and best-effort version numbers,
- restores the chosen inputs via `nix flake lock --override-input`,
- always shows the package holds.

Best-effort helpers: `scripts/flake-version.nix` probes one input/ref for a
version, and `scripts/flake-lock-info.nix` produces the shared root-input TSV
(name/rev/date/flake-ref).

## Input policy

- `llm-agents` (numtide's `llm-agents.nix`) is deliberately **not**
  following our nixpkgs. Its binaries in `cache.numtide.com` are built
  against its own pinned nixpkgs; `follows = "nixpkgs"` would mean cache
  misses and rebuilds.
- `xremap-flake` is likewise not following nixpkgs — same policy.
- `seance` follows our nixpkgs (`inputs.nixpkgs.follows = "nixpkgs"`) so it
  builds against our closure and avoids duplicate nixpkgs.
