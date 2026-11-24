# Box TTY resize watcher

Status: **not implemented** (2026-11-24). This file is transient work state:
when the watcher lands, move the durable behavior into `docs/sandbox.md` and
delete this file. Do not treat it as documentation.

## Problem

`box` runs every command through bwrap with `--new-session`
(`shell/box.sh:380`):

```
bwrap ... --die-with-parent --new-session --chdir "$PWD" -- "${cmd[@]}"
```

`--new-session` calls `setsid()`, so the sandboxed command is a session/process
group leader detached from the outer terminal. The inherited PTY fds still work
and the outer terminal (seance/zmx, tmux, a plain terminal) resizes the PTY with
`TIOCSWINSZ`. But the kernel delivers `SIGWINCH` to the PTY's **foreground
process group** — the outer shell — not to the boxed command. A TUI that only
learns its size from `SIGWINCH` keeps its startup size forever.

### Evidence (2026-11-24)

- In the affected seance pane, closing the second column changed the inner PTY
  from `88x52` to `179x52` (pixels `1594x2002` -> `3230x2002`), but opencode
  continued drawing at 88 columns.
- `~/.config/seance/session.json` confirmed the window (1876x1022 logical) and
  the new single-column layout; the PTY matched a full-width pane. The PTY path
  and the zmx daemon were correct.
- Plain opencode in the same pane reflows correctly. Boxed opencode does not:
  100% reproducible.
- `pkill -WINCH -f 'read short_summary.md'` sent `SIGWINCH` directly to the
  boxed processes; opencode reflowed immediately. Only the notification is
  missing.
- opencode 1.19.6 uses `@opentui/core 0.4.5`; its `SIGWINCH` handler samples
  `stdout.columns`/`stdout.rows` and calls `processResize`. It has no size
  polling. This is an app-side detail, not the fix target.
- Root cause is the box's `--new-session`, not zmx/seance: both resize the
  daemon's inner PTY correctly.

## Goals / constraints

- Keep `--new-session` and the existing sandbox boundary; do not weaken it.
- No changes to seance, zmx, opencode, or the app.
- Fix every boxed TUI, not just opencode, including TUIs nested under a boxed
  shell.
- No per-frame polling; negligible CPU; one small watcher per interactive box.
- No behavioral change for non-TTY boxes.
- Preserve stdio, exit status, and box teardown semantics.

## Options considered

1. **Drop `--new-session`** — rejected: it provides terminal/job-control
   isolation for the sandbox.
2. **seance-side process-tree signalling** — works (`pkill` proved it), but it
   lives outside the box, needs `/proc` walking, and only helps seance panes.
   Keep as a fallback idea, not the chosen fix.
3. **In-box TTY-size watcher (chosen)** — inside the sandbox, poll the inherited
   PTY's `TIOCGWINSZ` and signal the sandbox's processes on change.
4. **App-side ioctl polling / V2 upgrade** — fixes opencode only; V1 is EOL.
5. **zmx/upstream resize signalling** — cannot see the bwrap-created new
   session; would still need a tree/session signal.

## Chosen design

A tiny `box-tty-watch` helper wraps the box command **inside** bwrap:

```
bwrap ... --new-session ... -- box-tty-watch -- "${cmd[@]}"
```

The helper:

1. If stdin is not a TTY or `TIOCGWINSZ` fails, `execvp(cmd)` directly.
2. Otherwise forks/execs the command, keeping the same stdin/stdout/stderr.
3. Polls `ioctl(STDIN_FILENO, TIOCGWINSZ, &ws)` every ~100-150 ms.
4. On a rows/cols change, sends `SIGWINCH` to **all processes in the sandbox
   PID namespace except itself and PID 1** via `kill(-1, SIGWINCH)`.
   - This reaches the direct TUI and any nested shell/child (e.g. `box -s`
     then `bash -i` then opencode).
   - SIGWINCH's default action is ignore, so non-TUIs are unaffected.
   - It is scoped to the box PID namespace; it cannot signal the host.
5. Reaps the child, forwards SIGTERM/SIGINT/SIGHUP to it, and exits with the
   child's status.

Why `kill(-1, ...)`: the watcher runs inside the box's PID namespace, so `-1`
means "all sandbox processes" — not the host. This avoids `/proc` walking and
covers nested jobs without pgrp/job-control assumptions. The kernel excludes
PID 1 (bwrap) and the caller.

### Packaging

- Add `pkgs/box-tty-watch.c` plus `pkgs/box-tty-watch.nix` (recommended over a
  shell loop: no `stty` fork per poll, straightforward signal/exit handling).
  - Source: ~60 lines of C: fork/exec, `ioctl(TIOCGWINSZ)`, `nanosleep`/`poll`,
    signal handlers, `waitpid`, `kill(-1, SIGWINCH)`.
  - Build with `stdenv.mkDerivation` (`dontUnpack = true`, `$CC -O2 ...`) or
    `pkgs.runCommandCC`; install `$out/bin/box-tty-watch`.
- Add it to `environment.systemPackages` in `modules/packages.nix` so the host
  shell can resolve it. An absolute `/nix/store` path is passed into the box, so
  no sandbox PATH changes are needed.
- Pure-shell fallback (only if a C package is unwanted): a
  `writeShellScriptBin` that polls `stty size` and runs `kill -WINCH -- -1`.
  More forky, and signal/exit handling is weaker; document the tradeoff.

### Wiring in `shell/box.sh`

After the existing `cmd` default:

```bash
local -a cmd=("$@")
[ "${#cmd[@]}" -eq 0 ] && cmd=(bash -i)
```

add:

```bash
local -a run_cmd=("${cmd[@]}")
local tty_watch=""
if [ "${BOX_NO_TTY_WATCH:-0}" != 1 ] && [ -t 0 ]; then
  tty_watch=$(command -v box-tty-watch 2>/dev/null) || tty_watch=""
fi
[ -n "$tty_watch" ] && run_cmd=("$tty_watch" -- "${cmd[@]}")
```

and use `"${run_cmd[@]}"` in both bwrap invocations (project and system). Keep
`BOX_NO_TTY_WATCH=1` as an escape hatch. If the helper is missing, run exactly
as today (silent fallback).

- Resolve the helper on the host before bwrap, then pass the absolute path;
  `command -v` inside the box could fail because the sandbox PATH differs.
- `[ -t 0 ]` is just an optimization; the helper itself no-ops on non-TTYs.
- The helper is inside bwrap so its PID namespace is the box's; this is what
  makes `kill(-1)` safe and scoped.

### C helper sketch

```c
// box-tty-watch -- CMD [ARG...]
// stdin is the box PTY. Poll TIOCGWINSZ; on change kill(-1, SIGWINCH)
// inside the box PID namespace.
if (ioctl(0, TIOCGWINSZ, &prev) < 0)
    execvp(cmd[0], cmd);

pid = fork();
if (pid == 0) { execvp(cmd[0], cmd); _exit(127); }

install handlers for SIGTERM/SIGINT/SIGHUP -> forward to child;
for (;;) {
    if (waitpid(pid, &status, WNOHANG) == pid)
        return exit_code(status);
    if (ioctl(0, TIOCGWINSZ, &cur) == 0 &&
        (cur.ws_row != prev.ws_row || cur.ws_col != prev.ws_col)) {
        kill(-1, SIGWINCH);
        prev = cur;
    }
    nanosleep(~100ms) / poll ...; retry on EINTR
}
```

Do not read fd 0; do not write to the child's stdio; handle EINTR after
signals.

### Lifecycle and edge cases

- Child exits/signaled: watcher returns the same status (or 128+signal) so
  `box`/scripts see the real exit code.
- Watcher receives SIGTERM/SIGINT/SIGHUP: forward to the child, wait, exit.
- PTY disappears: ioctl fails; keep the child running, stop polling (or exit
  after the child).
- A size change during app startup is caught by the next poll.
- If the command itself calls `setsid` (some daemons), `kill(-1)` still reaches
  it inside the same PID namespace.
- Nested shells: `kill(-1)` reaches the TUI even if it is not the direct child.
- Non-TTY boxes (`printf x | box ...`): helper execs directly, no polling.
- `BOX_NO_TTY_WATCH=1`: bypass the wrapper, useful for debugging.
- No sandbox/bind/namespace changes; `--new-session` stays.
- CPU: one wakeup per ~100ms per interactive box; negligible.

## Implementation checklist

- [ ] Add `pkgs/box-tty-watch.c` + `pkgs/box-tty-watch.nix`.
- [ ] Add the package to `modules/packages.nix`.
- [ ] Wire `run_cmd` into `shell/box.sh` (both bwrap branches).
- [ ] Rebuild (`nyx`) and confirm `command -v box-tty-watch`.
- [ ] Reproduce: boxed opencode + seance split/close; plain vs boxed.
- [ ] Test nested `box -s bash -i` then opencode inside.
- [ ] Test non-TTY, exit status, signals, and `BOX_NO_TTY_WATCH=1`.
- [ ] Update `docs/sandbox.md`: replace the known-issue section with the
      implemented behavior (watcher, escape hatch, and why `--new-session`
      stays).
- [ ] Update `short_summary.md` only if the `plans/` convention needs editing.
- [ ] Delete this plan file; commit.

## Testing / procedure

- Build: `nyx` (seance is not involved).
- `box -s opencode` (or `nyvibe`); in seance open/close a split, change the
  column preset, drag the window. The TUI should reflow within ~150ms.
- Nested: `box -s bash -i`, run `opencode` (or `vim`) inside.
- Non-TTY: `printf x | box -s cat`.
- Exit: `box -s sh -c 'exit 7'; echo $?` -> 7.
- Signals: start `box -s sleep 100`, close/kill; verify no orphan.
- Debug: `BOX_NO_TTY_WATCH=1 box -s opencode` should reproduce the bug; with
  the watcher it should not.
- Optional: a small `stty size` loop inside the box plus an outer resize.
- Verify inside the box that PID/PID namespaces are unchanged and the watcher
  only adds one process.

## Rollback

Set `BOX_NO_TTY_WATCH=1` (runtime) or revert the `run_cmd` wiring; the package
can remain installed.
