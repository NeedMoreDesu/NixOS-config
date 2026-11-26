# Agent sandboxes (`shell/box.sh`)

`~/.bashrc` sources `hosts/nixos/bashrc.sh`, which sets `NYX_REPO`/`NYX_HOST`
and sources `shell/{box,nyx,agents}.sh`. The `nyx`, `nyvibe`, `oc`, `ab` and
`box` launchers live in the repo.

`box [flags] [cmd]` is **project mode**; `box -s|--system [flags] [cmd]` is
**system mode**; `box -x|--relaxed [flags] [cmd]` is **relaxed system mode**;
`cmd` defaults to `bash -i`.

`-n|--network` keeps the host network namespace (needed for CDP); without it
the box gets an egress-only pasta namespace. `-p|--port PORT` (repeatable, or
comma-separated) adds that host-loopback TCP port to the box. This host sets
`BOX_DEFAULT_PORTS=8088,8089,8090` in `hosts/nixos/bashrc.sh`, so `-p 1234`
forwards 8088, 8089, 8090 and 1234. Relaxed mode always uses the host network,
so ports are inert there.

`-d|--dir PATH` (repeatable) read-write-binds an extra host directory at the
same path, even one the HOME mask would otherwise hide. Relative paths resolve
under `$HOME` (`-d .ssh` is `~/.ssh`) and `~/` is expanded. It applies after
the HOME allowlists, before the `$PWD` bind, so it can override a read-only
entry; last one wins. Missing directories are an error.

`nyvibe` = `oc -s -p 8088` with the short_summary prompt appended, so oc's
flags work here too (`nyvibe -l` selects the local Inkling model); the explicit
`-p 8088` is deduped with the host default (8089 and 8090 are already in the
default).
`oc [box flags] [-l] [--] [opencode args]` runs opencode in a box on the
current directory; `oc -s` selects system mode, `oc -l` selects the local
Inkling model (`-m inkling/inkling-2-mini`), and `oc -h` prints `oc`'s help
followed by opencode's help.
`ab [prompt...]` = project-mode opencode in `~/ab_workspace` with `-n`,
attaching to the host's dedicated Chromium (see
[agent browser](agent-browser.md)).

## System mode (`box -s`)

- `/` read-only.
- Fresh minimal `/dev` (no `/dev/input`, so the input group cannot snoop),
  then host `/dev/dri` (render nodes) and `/dev/kfd` (ROCm compute) are
  bound in.
- Host `/tmp` read-write (shared; systemd-tmpfiles cleans it after 10 days).
- Private `/dev/shm`.
- PID/IPC/UTS unshared: host `/proc`, cmdlines, signals and SysV IPC are
  invisible.
- Host journal (`/var/log/journal`, `/run/log/journal`) masked.
- `$PWD` writable.
- `HOME` is a tmpfs rebuilt from `_BOX_SYSTEM_RW/RO`:
  - writable: opencode + nix state, `~/temp`, `~/nixos_config` (the repo is
    the source of truth, so agents can edit/commit from any cwd);
  - read-only: KDE/kate/emacs/seance settings, `~/models` (local model
    weights; the agent may load them, not replace the pins),
    `~/Pictures/Screenshots` (UI inputs; see `_BOX_SHARED_RO`);
  - absent: everything else (`.ssh`, browsers, `.dsh`, keyrings, cloud
    credentials, histories).
- `/run/user` (D-Bus, Wayland, SSH agent, KWallet, KWin Scripting) is masked
  unless `BOX_GUI=1`.
- Network is egress-only pasta; each `BOX_DEFAULT_PORTS`/`-p|--port`
  entry forwards that host-loopback TCP port into the box (this host:
  8088 llama-embed, 8089 llama-inkling, 8090 llama-vl).
- Refuses a `$PWD` that is (or is an ancestor of) a special mount/masked
  path: `$HOME`, `/tmp`, `/dev`, `/dev/shm`, `/proc`, `/sys`,
  `/var/log/journal`, `/run/log/journal`, `/run/user/$UID` — the workspace
  bind is last and would otherwise undo the mask.

## Relaxed system mode (`box -x`)

For debugging when the agent needs the host: the whole host root is bound
**read-write** with `--dev-bind`, so namespaces, mounts, `/dev`, `/proc`,
`/sys`, `/run/user`, the journal and the network are all the host's. (Plain
`--bind` is wrong here: bwrap recursively remounts every submount `nodev`,
which makes `/dev/null` and other device nodes fail with EACCES.) Only
`$HOME` is replaced by a tmpfs rebuilt from the system allowlists.
`-d|--dir` is the explicit escape hatch for a specific host directory.

- Host PID namespace (no `--unshare-pid`), so host processes are visible and
  the agent can attach to processes it starts.
- Host network namespace (no pasta), so host loopback and the local AI
  services are directly reachable; `-p` is inert.
- Host `/dev`, `/dev/shm`, journal (`/var/log/journal`, `/run/log/journal`)
  and `/run/user/$UID`: D-Bus, Wayland, audio, polkit agent, SSH agent and
  KWallet. `SEANCE_SOCKET_PATH`/`ZMX_SESSION` are unset and the
  `seance`/`zmx` runtime subdirectories are tmpfs-masked (otherwise a host
  pane would trivially read `~/.ssh`).
- `$HOME` is still a tmpfs rebuilt from the allowlists (opencode state, repo,
  `~/temp`, models, config).

This is deliberately **not** a stronger boundary than "the agent runs as
mika". bwrap still creates a user namespace, so inside the box `sudo` fails
(`no_new_privs`) and ptrace is limited to descendants: `/proc/<host-pid>/root`
and other host processes are gated by `kernel.yama.ptrace_scope=1`, exactly
the surface [the namespaces](#why-the-namespaces-escape-surface-2026-11-15)
closed for system mode. Treat it as a HOME lock for a mostly-trusted agent,
not as secret protection: `/run/user` exposes the keyring and SSH agent, and
user D-Bus services can reach the host session. Use it only when the
debugging value outweighs that.

## Project mode (`box`)

- No host root or home. Only `/nix/store`, `/run/current-system`, `/etc`,
  `/usr`, `/bin`, `/lib64`, `/sys`, a fresh `/dev` + `/proc`, `$PWD` rw,
  `~/temp` rw (shared), `~/Pictures/Screenshots` ro (shared with system
  mode), and ONE random `/tmp/box.*` bound to `/tmp` (deleted on exit).
- PID/IPC/UTS unshared; further user namespaces disabled.
- Network is egress-only by default: `pasta` supplies a tap/NAT namespace
  configured with `--no-map-gw --no-splice -t none -u none -T none -U none`,
  so host loopback (CDP 9222, agent-browser streams, CUPS, systemd varlink)
  is unreachable while DNS/HTTPS still work. `-n` keeps the host netns for
  the agent browser. Each `BOX_DEFAULT_PORTS`/`-p|--port` entry replaces
  that port's `-T none` with a single guest→host-loopback TCP hole (repeat
  `-p` or pass a comma-separated list; this host defaults to 8088,8089,8090
  for llama-embed, llama-inkling and llama-vl). `-n` bypasses pasta, so ports
  have no effect there.
- Needs the `tun` module (`modules/networking.nix`); udev already ships the
  `/dev/net/tun` 0666 rule.
- Compilers come from the store. `_BOX_PROJECT_RW` whitelists per-user build
  caches (cargo registry, go build/mod, npm/bun/pnpm/yarn, pip/uv,
  maven/gradle, cabal, ccache/sccache, ...) and `_BOX_PROJECT_RO` toolchain
  state. `~/temp` is the shared rw scratch/log handoff. Credential files next
  to those caches (`.cargo/credentials.toml`, `.m2/settings.xml`, `.npmrc`,
  ...) stay unmounted.
- `BOX_SECRETS=1` read-only-binds `.ssh`/`.gnupg`/cloud/gh/dsh.

`bubblewrap`, `passt` and `box-tty-watch` are in `modules/packages.nix`.

opencode's own `auth.json` must stay visible for provider calls — the
boundary covers everything outside the allowlist.

After the `tun` module is added, run `nyx -r` (or `sudo modprobe tun`) once;
before that every default-mode box fails loudly at "Failed to open
/dev/net/tun" instead of running without the network. `ab` uses `-n`, so it
works without pasta.

## opencode permissions

opencode's own "outside the project" folder prompts are off
(`assets/opencode/opencode.jsonc`): `permission.external_directory = allow`
plus an explicit `/tmp/*` edit allow — the sandbox is the boundary.

This is the **V1** shape (`permission`, value strings), NOT V2's
`permissions` array: opencode 1.19.5 hard-errors on V2 keys. It applies to
sessions outside `box` too, since the config is global.

## Why the namespaces (escape surface, 2026-11-15)

System mode used to keep the host PID, IPC and network namespaces.
`/proc/<host-pid>/root` (the real `$HOME`, including `.ssh`) was gated only
by `kernel.yama.ptrace_scope=1`; host cmdlines, mountinfo, the journal and
SysV shm were readable, and signals reached host processes. Shared localhost
reach also exposed the dedicated Chromium's CDP (`file://` reads and download
writes as mika).

Fix: `--unshare-pid/--unshare-ipc/--unshare-uts`, private `/dev/shm`,
journal masked, and an egress-only pasta netns (`--no-map-gw --no-splice`);
`-n` keeps the host netns for `ab`/CDP. pasta needs the `tun` module
(`modules/networking.nix`). The deliberate exceptions are `/dev/kfd` for
ROCm, read-only `~/models`, and the `-p|--port` loopback holes (this host
defaults `BOX_DEFAULT_PORTS=8088,8089,8090` for llama-embed, llama-inkling
and llama-vl); none of those expose the host filesystem, D-Bus or the journal.

Separately, each agent-browser session daemon opened a random loopback
WebSocket stream port for the unused dashboard; agent-chrome now disables the
session stream after every page command (see
[agent browser](agent-browser.md)).

## Inherited seance/zmx env (2026-11-21)

A box launched from a seance pane inherits `SEANCE_SOCKET_PATH`,
`ZMX_SESSION`, the `SEANCE_*` pane vars, and (non-GUI) `DISPLAY`/
`WAYLAND_DISPLAY`/`XAUTHORITY`. Default system mode is safe: `/run/user/$UID`
is masked, so `seance ctl` reports "socket not found", zmx resolves to
`/tmp/zmx-1000` while the host uses `/run/user/$UID/zmx`, and X/Wayland auth
is unreachable. It is **not** a new hole today.

It becomes one with `BOX_GUI=1`, which binds all of `/run/user/$UID` rw and
leaves those vars intact: `seance ctl split`/`send` then drives the host
seance (host shell), and a bare `zmx attach` uses the inherited
`ZMX_SESSION` (host shell). `nyvibe`/`ab` never set `BOX_GUI`, so it is an
unused opt-in — treat it as trusted-only. If hardening later: always unset
`SEANCE_*`/`ZMX_*`, and `--tmpfs` the `seance`/`zmx` subdirs even with GUI.

## TTY resize in boxes (`box-tty-watch`, 2026-11-24)

`box` keeps bwrap's `--new-session` (`shell/box.sh:391`), so the boxed
command is in its own session/process group and never receives the kernel's
pane-resize `SIGWINCH` (that goes to the outer terminal's foreground pgrp).
Rather than weaken the isolation, interactive boxes wrap the command with
`box-tty-watch` (`pkgs/box-tty-watch.c`, installed by
`modules/packages.nix`). Inside the sandbox it polls the inherited stdin
PTY's `TIOCGWINSZ` every 100 ms and, on a rows/cols change, calls
`kill(-1, SIGWINCH)`.

Because the helper runs inside the box PID namespace, `kill(-1)` only reaches
sandbox processes — the kernel skips PID 1 (bwrap) and the caller — so it
covers directly-run TUIs and nested shells/jobs without `/proc` walking, and
cannot signal the host. SIGWINCH's default action is ignore, so non-TUIs are
unaffected. The helper never reads stdin; stdio and exit status are
inherited, and SIGTERM/SIGINT/SIGHUP are forwarded to the command.

`shell/box.sh` resolves the helper on the host and passes its absolute
`/nix/store` path into bwrap in both project and system modes. Non-TTY boxes
(`printf x | box ...`) fall back to the bare command, as does a missing
helper. `BOX_NO_TTY_WATCH=1` disables the wrapper (useful for reproducing the
original behaviour). The PTY itself was always resized correctly (observed
`88x52` -> `179x52`); only the notification was missing.
