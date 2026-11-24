# Hosts vs shared configuration

- `hosts/<name>/` is **machine-specific**:
  - `default.nix` — the composition root: imports the generated hardware
    config, per-host user units, and the shared modules.
  - `hardware-configuration.nix` — generated at install; machine-specific
    mounts and `nixpkgs.hostPlatform`.
  - `bashrc.sh` — per-host shell shim, sourced by `~/.bashrc`; sets
    `NYX_REPO`/`NYX_HOST`, host box defaults such as `BOX_DEFAULT_PORTS`,
    and sources `shell/{box,nyx,agents,aliases}.sh`.
  - per-host user units such as `kscreen.nix`.
- Nothing auto-discovers hosts. `flake.nix` explicitly maps
  `nixosConfigurations.<name> = mkHost "<name>"`, where `mkHost` builds from
  `hosts/<name>/default.nix`; `specialArgs` adds `hostName = <name>`.
- `home/`, `modules/`, `assets/`, `shell/`, `scripts/` are shared and
  imported by whichever host needs them.

## Adding a host

1. Create `hosts/<name>/` (start from an existing host's `default.nix` and
   generate its hardware config).
2. Add a `mkHost "<name>"` entry in `flake.nix`.
3. Give its `bashrc.sh` the right `NYX_HOST`; its `nyx` builds that key.

## The current host: `nixos`

`hosts/nixos/default.nix` imports the hardware config, `kscreen.nix`, and
the shared modules. It sets `networking.hostName = "nixos"` and
`system.stateVersion = "26.05"` — **never** bump `stateVersion`
(see the comment in the file). Hostname lives here, not in
`modules/networking.nix`.
