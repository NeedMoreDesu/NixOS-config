# Seance

`seance` is a scrolling GTK4/libadwaita terminal multiplexer that tracks AI
coding agents (MIT, Zig 0.16). It comes from the `seance` flake input, **not**
nixpkgs: `seance.packages.${pkgs.stdenv.hostPlatform.system}.seance`
(`modules/packages.nix`), built against our nixpkgs via
`inputs.nixpkgs.follows`.

## Config

`home/seance.nix` symlinks `~/.config/seance/config.toml` to
`assets/seance/config.toml`.

Keybinds are **Nix policy**:

| Binding | Action |
| --- | --- |
| Cmd+T | `new_column` (vertical split) |
| Ctrl+Shift+N | New workspace |
| Ctrl+Alt+N | New window |

Tabs come from the tab-bar plus button/palette only.

Seance's Settings window **replaces the symlink** when it saves
(temp+rename), so GUI edits are not persistent policy — change
`assets/seance/config.toml` instead.

## zmx

Seance's cleanup shortcuts end in `zmx kill`. zmx is currently held at 0.8.1
because 1.0.1 aborts on daemon shutdown; see [pins](pins.md#why-zmx-is-held).

## Keyboard

The `seance` app id is part of the REMAX login sweep
(see [plasma](plasma.md#login-maximize-sweep-homekwin-remaxnix)) and has a
terminal keymap block in xremap (see [keyboard](keyboard.md)).

## Sandbox

Boxes launched from a seance pane inherit `SEANCE_SOCKET_PATH`/`ZMX_SESSION`.
Default mode masks the sockets (safe); `BOX_GUI=1` exposes them and lets the
box drive the host seance/zmx. See
[sandbox](sandbox.md#inherited-seancezmx-env-2026-11-21).
