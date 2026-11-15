# NixOS workflow + sandboxed agent launches. Sourced from ~/.bashrc.
#
# nyvibe  system mode: / is visible (read-only), $PWD writable, and HOME is
#         rebuilt from the allowlist below. Missing paths are simply absent.
# nycode  project mode: no host /; only runtime dirs, $PWD, and one random
#         /tmp directory. Nothing else from HOME is mounted.
# nybox   raw launcher: `nybox system|project [command ...]`
#
# The home allowlist is policy: add only what the agent actually needs to
# read (and the state dirs it must write). Secrets are absent by default,
# which is the point - no blacklist to keep in sync as tools add new files.

alias nyx='sudo bash "$HOME/nixos_config/rebuild.sh"'

# Runtime/state that must be writable. opencode keeps provider auth in
# ~/.local/share/opencode/auth.json, so it is necessarily visible to the
# agent process; this sandbox protects everything OUTSIDE these paths.
_NYBOX_HOME_RW=(
  .local/share/opencode
  .local/state/opencode
  .cache/opencode
  .local/state/nix
  .cache/nix
)

# Settings/dotfiles that are useful for investigating the system. Read-only.
_NYBOX_HOME_RO=(
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

_NYBOX_PROJECT_RW=(
  .local/share/opencode
  .local/state/opencode
  .cache/opencode
  .local/state/nix
  .cache/nix
)

_NYBOX_PROJECT_RO=(
  .config/opencode
  .gitconfig
  .config/git
)

# Refuse a workspace that is HOME or an ancestor of it: binding it writable
# would re-expose the very tree the tmpfs mask hides.
_nybox_guard_pwd() {
  local pwd_real home_real
  pwd_real=$(realpath -- "$PWD") || return 1
  home_real=$(realpath -- "$HOME") || return 1
  if [ "$pwd_real" = / ]; then
    printf 'nybox: refusing workspace /\n' >&2
    return 1
  fi
  case "$home_real/" in
    "$pwd_real"/*)
      printf 'nybox: refusing workspace %s (it contains $HOME)\n' "$PWD" >&2
      return 1
      ;;
  esac
  return 0
}

nybox() {
  if [ "$#" -lt 1 ]; then
    printf 'usage: nybox system|project [command ...]\n' >&2
    return 2
  fi

  local mode=$1
  shift
  local -a flags cmd=("$@")
  [ "${#cmd[@]}" -eq 0 ] && cmd=(bash -i)

  _nybox_guard_pwd || return 1

  case "$mode" in
    system)
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
        --bind "$PWD" "$PWD"
      )

      if [ "${NYBOX_GUI:-0}" -eq 1 ] && [ -d "/run/user/$(id -u)" ]; then
        # Wayland/D-Bus/Audio. Also exposes keyring/SSH-agent/KWin-Scripting,
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

      for p in "${_NYBOX_HOME_RW[@]}"; do
        flags+=(--bind-try "$HOME/$p" "$HOME/$p")
      done
      for p in "${_NYBOX_HOME_RO[@]}"; do
        # An allowlist entry equal to the workspace would make it read-only.
        [ "$HOME/$p" = "$PWD" ] && continue
        flags+=(--ro-bind-try "$HOME/$p" "$HOME/$p")
      done

      flags+=(--die-with-parent --new-session --chdir "$PWD")
      bwrap "${flags[@]}" -- "${cmd[@]}"
      ;;
    project)
      local tmp
      tmp=$(mktemp -d "${TMPDIR:-/tmp}/nybox.XXXXXXXX") || return 1
      chmod 700 "$tmp"
      flags+=(
        # Runtime only: no /home, no /run/user, no network isolation (the
        # agent still needs its API). /etc is NixOS state, not user data.
        --ro-bind /nix/store /nix/store
        --ro-bind /run/current-system /run/current-system
        --ro-bind /etc /etc
        --ro-bind /usr /usr
        --ro-bind /bin /bin
        --ro-bind /lib64 /lib64
        --ro-bind-try /nix/var/nix/profiles/default /nix/var/nix/profiles/default
        --ro-bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
        --dev /dev
        --proc /proc
        --bind "$tmp" /tmp
        --dir "$HOME"
        --bind "$PWD" "$PWD"
        --unshare-user --disable-userns
        --unshare-pid --unshare-ipc --unshare-uts --hostname nybox
        --unsetenv XDG_RUNTIME_DIR
        --unsetenv DBUS_SESSION_BUS_ADDRESS
        --unsetenv SSH_AUTH_SOCK
        --die-with-parent --new-session --chdir "$PWD"
      )
      for p in "${_NYBOX_PROJECT_RW[@]}"; do
        flags+=(--bind-try "$HOME/$p" "$HOME/$p")
      done
      for p in "${_NYBOX_PROJECT_RO[@]}"; do
        flags+=(--ro-bind-try "$HOME/$p" "$HOME/$p")
      done

      # The single random /tmp directory dies with the session.
      ( trap 'rm -rf -- "$tmp"' EXIT; bwrap "${flags[@]}" -- "${cmd[@]}" )
      ;;
    *)
      printf 'nybox: unknown mode %s (use system|project)\n' "$mode" >&2
      return 2
      ;;
  esac
}

nyvibe() {
  ( cd "$HOME/nixos_config" && nybox system opencode --prompt "read short_summary.md" "$@" )
}

nycode() {
  nybox project opencode "$@"
}
