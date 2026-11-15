# NixOS workflow + sandboxed agent launches. Sourced from ~/.bashrc.
#
# box [cmd]            project mode (default): runtime dirs + $PWD + one
#                      random /tmp. HOME is deny-by-default with a build
#                      cache allowlist (no credentials).
# box -s|--system [cmd] system mode: / read-only, $PWD writable, HOME
#                      rebuilt from the settings allowlist plus the
#                      project build-cache/toolchain lists.
# nyvibe               system-mode opencode in the repo with the
#                      short_summary prompt.
#
# The command defaults to `bash -i`. The home lists are policy: add only
# what the agent actually needs. Secrets are absent by default, which is
# the point - no blacklist to keep in sync as tools add new files.
# BOX_SECRETS=1 opts known credential paths back in read-only;
# BOX_GUI=1 binds /run/user (+ /dev/dri in project mode).

alias nyx='sudo bash "$HOME/nixos_config/rebuild.sh"'

# --- system mode: settings that are useful for investigating the box -----

_BOX_SYSTEM_RW=(
  .local/share/opencode
  .local/state/opencode
  .cache/opencode
  .local/state/nix
  .cache/nix
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

# Refuse a workspace that is HOME or an ancestor of it: binding it writable
# would re-expose the very tree the tmpfs mask hides.
_box_guard_pwd() {
  local pwd_real home_real
  pwd_real=$(realpath -- "$PWD") || return 1
  home_real=$(realpath -- "$HOME") || return 1
  if [ "$pwd_real" = / ]; then
    printf 'box: refusing workspace /\n' >&2
    return 1
  fi
  case "$home_real/" in
    "$pwd_real"/*)
      printf 'box: refusing workspace %s (it contains $HOME)\n' "$PWD" >&2
      return 1
      ;;
  esac
  return 0
}

box() {
  local mode=project
  while :; do
    case "${1:-}" in
      -s|--system)
        mode=system
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

  if [ "$mode" = system ]; then
    local p
    flags+=(
      # Whole system readable; devices are a FRESH minimal /dev (no
      # /dev/input, so the input group cannot snoop keystrokes).
      --ro-bind / /
      --dev /dev
      --dev-bind-try /dev/dri /dev/dri
      --proc /proc
      --tmpfs /tmp
      # Home is deny-by-default, then the allowlist above is layered in.
      --tmpfs "$HOME"
    )

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
      # Runtime only: no host /home, no /run/user, no network isolation
      # (the agent still needs its API). /etc is NixOS state, not user data.
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
      --proc /proc
      --bind "$tmp" /tmp
      --dir "$HOME"
      --unshare-user --disable-userns
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

  if [ "$mode" = project ]; then
    # The single random /tmp directory dies with the session.
    ( trap 'rm -rf -- "$tmp"' EXIT; bwrap "${flags[@]}" -- "${cmd[@]}" )
  else
    bwrap "${flags[@]}" -- "${cmd[@]}"
  fi
}

nyvibe() {
  ( cd "$HOME/nixos_config" && box -s opencode --prompt "read short_summary.md" "$@" )
}
