# bwrap agent sandboxes. Shared across hosts; sourced from
# hosts/<host>/bashrc.sh (which sets NYX_REPO/NYX_HOST).
#
# box [cmd]            project mode (default): runtime dirs + $PWD + one
#                      random /tmp + ~/temp rw. HOME is deny-by-default
#                      with a build cache allowlist (no credentials).
# box -s|--system [cmd] system mode: / read-only, $PWD + host /tmp +
#                      ~/temp writable, HOME rebuilt from the settings
#                      allowlist plus the project build-cache/toolchain
#                      lists. /dev/kfd (ROCm) is bound; ~/models is
#                      visible read-only.
#
# The command defaults to `bash -i`. The home lists are policy: add only
# what the agent actually needs. Secrets are absent by default, which is
# the point - no blacklist to keep in sync as tools add new files.
# BOX_SECRETS=1 opts known credential paths back in read-only;
# BOX_GUI=1 binds /run/user (+ /dev/dri in project mode).
# BOX_HOST_PORT=PORT forwards exactly that host-loopback TCP port into
# the egress-only pasta namespace (and nothing else).

# --- system mode: settings that are useful for investigating the box -----

_BOX_SYSTEM_RW=(
  .local/share/opencode
  .local/state/opencode
  .cache/opencode
  .local/state/nix
  .cache/nix
  # Shared scratch/log handoff. Host rw in both modes; do not put
  # credentials here.
  temp
)

_BOX_SYSTEM_RO=(
  .bashrc
  .gitconfig
  .config/opencode
  .config/kdeglobals
  .config/kwinrc
  .config/kglobalshortcutsrc
  .config/kscreenlockerrc
  .config/klipperrc
  .config/kaccessrc
  .config/kded5rc
  .config/kded6rc
  .config/kdedefaults
  .config/KDE
  .config/plasma-workspace
  .config/kate
  .config/katerc
  .config/katevirc
  .config/konsolerc
  .config/mimeapps.list
  .config/gtkrc
  .config/gtkrc-2.0
  .config/gtk-3.0
  .config/gtk-4.0
  .config/fontconfig
  .config/autostart
  .config/environment.d
  .config/systemd
  .config/ghostty
  .config/seance
  .config/qtvirtualkeyboard
  .config/session
  .config/xsettingsd
  .local/share/plasma
  .local/share/kwin
  .local/share/konsole
  .local/share/kate
  .local/share/color-schemes
  .local/share/plasma-manager
  .local/share/wallpapers
  .emacs.d
  seance
  # Model weights for local inference (llama.cpp/ROCm). Read-only: the
  # agent may load them but must not replace the pinned files.
  models
)

# --- project mode: toolchain state, never credential files ---------------
# Compilers/toolchains themselves come from /nix/store and
# /run/current-system; these are the per-user caches and module stores that
# would otherwise be re-downloaded into the missing HOME. Credential files
# that sit next to them (.cargo/credentials.toml, .m2/settings.xml,
# .gradle/gradle.properties, .npmrc, .yarnrc.yml, .stack/config.yaml) are
# deliberately not mounted.

_BOX_PROJECT_RW=(
  # opencode
  .local/share/opencode
  .local/state/opencode
  .cache/opencode
  # nix
  .local/state/nix
  .cache/nix
  # C/C++/Rust
  .cache/ccache
  .ccache
  .cache/sccache
  .cache/clangd
  .cache/rust-analyzer
  .cargo/registry
  .cargo/git
  # Go
  .cache/go-build
  .cache/gopls
  .go/pkg/mod
  .go/bin
  # JS/TS
  .npm
  .bun/install/cache
  .local/share/pnpm
  .yarn/berry/cache
  .cache/node
  .cache/typescript
  .cache/ms-playwright
  .cache/electron
  # Python
  .cache/pip
  .cache/uv
  .local/share/uv
  .cache/pypoetry
  .cache/pre-commit
  # JVM
  .m2/repository
  .gradle/caches
  .gradle/wrapper
  # Haskell
  .cabal/packages
  .cabal/store
  # misc
  .cache/zig
  .cache/huggingface
  .cache/torch
  .local/share/direnv
  # shared scratch/log handoff (host rw; not a credential path)
  temp
)

_BOX_PROJECT_RO=(
  .config/opencode
  .gitconfig
  .config/git
  .cargo/config.toml
  .rustup
  .ghcup
  .local/share/nix
  .nix-profile
  .nix-defexpr
  .local/bin
)

# Opt-in only: known credential stores, read-only (BOX_SECRETS=1). Read-only
# means git push works, but adding known_hosts / signing-key edits do not.
_BOX_SECRETS=(
  .ssh
  .gnupg
  .aws
  .kube
  .docker
  .netrc
  .git-credentials
  .npmrc
  .config/gh
  .config/gcloud
  .dsh
)

# Refuse a workspace that would shadow a special mount or re-expose a
# masked path. The workspace bind is applied last, so PWD=/tmp would shadow
# the project-mode private /tmp (and is pointless with the system-mode host
# /tmp bind), PWD=$HOME would re-expose the hidden home, etc.
_box_guard_pwd() {
  local pwd_real mask mask_real
  pwd_real=$(realpath -- "$PWD") || return 1
  if [ "$pwd_real" = / ]; then
    printf 'box: refusing workspace /\n' >&2
    return 1
  fi
  for mask in "$HOME" /tmp /dev /dev/shm /proc /sys \
              /var/log/journal /run/log/journal "/run/user/$(id -u)"; do
    mask_real=$(realpath -- "$mask" 2>/dev/null) || continue
    case "$mask_real" in
      "$pwd_real"|"$pwd_real"/*)
        printf 'box: refusing workspace %s (it would shadow/re-expose %s)\n' \
          "$PWD" "$mask" >&2
        return 1
        ;;
    esac
  done
  return 0
}

box() {
  local mode=project network=0
  while :; do
    case "${1:-}" in
      -s|--system)
        mode=system
        shift
        ;;
      -n|--network)
        network=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *) break ;;
    esac
  done

  local -a flags cmd=("$@")
  [ "${#cmd[@]}" -eq 0 ] && cmd=(bash -i)

  _box_guard_pwd || return 1

  # Shared scratch/log handoff in both modes. Create it on the host so the
  # --bind-try in the HOME allowlists always has a source.
  mkdir -p "$HOME/temp" 2>/dev/null || true

  if [ "$network" -eq 0 ] && [ ! -e /dev/net/tun ]; then
    printf 'box: /dev/net/tun missing: load tun (sudo modprobe tun) or use -n/--network\n' >&2
    return 1
  fi

  if [ "$mode" = system ]; then
    local p
    flags+=(
      # Whole system readable; devices are a FRESH minimal /dev (no
      # /dev/input, so the input group cannot snoop keystrokes).
      --ro-bind / /
      --dev /dev
      --tmpfs /dev/shm
      --dev-bind-try /dev/dri /dev/dri
      # AMD KFD interface for ROCm compute. /dev/dri alone only gives
      # rendering; HIP/rocminfo need /dev/kfd.
      --dev-bind-try /dev/kfd /dev/kfd
      --proc /proc
      # Host /tmp is rw: scratch/log files written here are visible outside
      # the box. systemd-tmpfiles cleans it after 10 days. /dev/shm stays
      # private.
      --bind /tmp /tmp
      # Keep the sandbox's mika identity even when `box` is wrapped by pasta
      # (which runs its child as userns-root). PID/IPC/UTS are unshared for
      # the same reason project mode does it: host /proc is not an oracle.
      --unshare-user
      --uid "$(id -u)"
      --gid "$(id -g)"
      --unshare-pid --unshare-ipc --unshare-uts
      # Home is deny-by-default, then the allowlist above is layered in.
      --tmpfs "$HOME"
    )
    # The host journal is otherwise readable through the ro-bind of /. Mask
    # it: the sandbox has no legitimate use for host logs.
    [ -d /var/log/journal ] && flags+=(--tmpfs /var/log/journal)
    [ -d /run/log/journal ] && flags+=(--tmpfs /run/log/journal)

    if [ "${BOX_GUI:-0}" -eq 1 ] && [ -d "/run/user/$(id -u)" ]; then
      # Wayland/D-Bus/audio. Also exposes keyring/SSH-agent/KWin-Scripting,
      # so this is opt-in for GUI work only.
      flags+=(--bind "/run/user/$(id -u)" "/run/user/$(id -u)")
    else
      [ -d "/run/user/$(id -u)" ] && flags+=(--tmpfs "/run/user/$(id -u)")
      flags+=(
        --unsetenv XDG_RUNTIME_DIR
        --unsetenv DBUS_SESSION_BUS_ADDRESS
        --unsetenv SSH_AUTH_SOCK
      )
    fi

    for p in "${_BOX_SYSTEM_RW[@]}"; do
      flags+=(--bind-try "$HOME/$p" "$HOME/$p")
    done
    for p in "${_BOX_SYSTEM_RO[@]}"; do
      flags+=(--ro-bind-try "$HOME/$p" "$HOME/$p")
    done
    # Build caches + toolchain state ride along too: / is read-only here,
    # so this only saves re-downloads. Re-binds of shared entries are
    # harmless (same source over same target).
    for p in "${_BOX_PROJECT_RW[@]}"; do
      flags+=(--bind-try "$HOME/$p" "$HOME/$p")
    done
    for p in "${_BOX_PROJECT_RO[@]}"; do
      flags+=(--ro-bind-try "$HOME/$p" "$HOME/$p")
    done
  else
    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/box.XXXXXXXX") || return 1
    chmod 700 "$tmp"
    flags+=(
      # Runtime only: no host /home, no /run/user. /etc is NixOS state, not
      # user data. The network namespace is provided by pasta (host loopback
      # unreachable) unless -n/--network is given.
      --ro-bind /nix/store /nix/store
      --ro-bind /run/current-system /run/current-system
      --ro-bind /etc /etc
      --ro-bind /usr /usr
      --ro-bind /bin /bin
      --ro-bind /lib64 /lib64
      --ro-bind /sys /sys
      --ro-bind-try /nix/var/nix/profiles/default /nix/var/nix/profiles/default
      --ro-bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
      --dev /dev
      --tmpfs /dev/shm
      --proc /proc
      --bind "$tmp" /tmp
      --dir "$HOME"
      --unshare-user --disable-userns
      --uid "$(id -u)"
      --gid "$(id -g)"
      --unshare-pid --unshare-ipc --unshare-uts --hostname box
    )

    if [ "${BOX_GUI:-0}" -eq 1 ] && [ -d "/run/user/$(id -u)" ]; then
      flags+=(
        --bind "/run/user/$(id -u)" "/run/user/$(id -u)"
        --dev-bind-try /dev/dri /dev/dri
        --ro-bind-try /run/opengl-driver /run/opengl-driver
        --ro-bind-try /run/opengl-driver-32 /run/opengl-driver-32
      )
    else
      flags+=(
        --unsetenv XDG_RUNTIME_DIR
        --unsetenv DBUS_SESSION_BUS_ADDRESS
        --unsetenv SSH_AUTH_SOCK
      )
    fi

    for p in "${_BOX_PROJECT_RW[@]}"; do
      flags+=(--bind-try "$HOME/$p" "$HOME/$p")
    done
    for p in "${_BOX_PROJECT_RO[@]}"; do
      flags+=(--ro-bind-try "$HOME/$p" "$HOME/$p")
    done
  fi

  if [ "${BOX_SECRETS:-0}" -eq 1 ]; then
    local p
    for p in "${_BOX_SECRETS[@]}"; do
      flags+=(--ro-bind-try "$HOME/$p" "$HOME/$p")
    done
  fi

  # Workspace last, so a read-only allowlist parent cannot shadow it.
  flags+=(--bind "$PWD" "$PWD")
  flags+=(--die-with-parent --new-session --chdir "$PWD")

  # Egress-only network namespace by default: pasta supplies the tap/NAT but
  # the namespace cannot reach host loopback (no gateway mapping, no local
  # splice path). -n/--network skips pasta and keeps the host netns, which is
  # what agent-browser needs to reach the dedicated Chromium on 127.0.0.1:9222.
  # BOX_HOST_PORT punches a single guest->host-loopback TCP hole through
  # pasta; everything else stays egress-only.
  local -a net=()
  local -a host_forward=(-T none)
  if [ -n "${BOX_HOST_PORT:-}" ]; then
    if [[ ! "$BOX_HOST_PORT" =~ ^[0-9]+$ ]] ||
       (( 10#$BOX_HOST_PORT < 1 || 10#$BOX_HOST_PORT > 65535 )); then
      printf 'box: BOX_HOST_PORT must be a TCP port number\n' >&2
      return 2
    fi
    # -T is loopback-only by design: it takes no listening address, and
    # the splice path preserves the guest's 127.0.0.1 destination.
    host_forward=(-T "${BOX_HOST_PORT}")
  fi
  if [ "$network" -eq 0 ]; then
    net=(pasta -f --config-net --no-map-gw --no-splice --quiet \
         -t none -u none "${host_forward[@]}" -U none --)
  fi

  if [ "$mode" = project ]; then
    # The single random /tmp directory dies with the session.
    ( trap 'rm -rf -- "$tmp"' EXIT; "${net[@]}" bwrap "${flags[@]}" -- "${cmd[@]}" )
  else
    "${net[@]}" bwrap "${flags[@]}" -- "${cmd[@]}"
  fi
}
