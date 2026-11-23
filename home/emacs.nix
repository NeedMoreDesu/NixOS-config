{ lib, pkgs, ... }:
let
  emacs = pkgs.emacs;

  # One daemon per session, healed on demand.
  #
  # Do not use `emacsclient -a ""` here: Emacs 31.1 segfaults in fail()
  # when the alternate editor is the empty string and no file arguments
  # are given (it tokenizes to zero tokens and calls execvp(NULL); fixed
  # upstream after 31.1). This launcher starts/restarts the daemon itself,
  # so the empty alternate-editor path is never reached.
  #
  # Do not use `emacsclient -n` either: a nowait frame is not tracked as a
  # client, so `C-x C-c` on the last frame runs `save-buffers-kill-emacs`
  # and kills the daemon (or leaves it wedged in a save prompt). A tracked
  # client (plain `-c`) makes `C-x C-c` delete only that client frame; the
  # daemon stays alive for the next click.
  #
  # A daemon that cannot create a window-system frame (e.g. started at
  # login before XWayland/Wayland was ready) or that stopped responding is
  # killed and restarted from the current graphical environment, then the
  # frame is retried once.
  emacsLauncher = pkgs.writeShellApplication {
    name = "emacs-gui";
    runtimeInputs = with pkgs; [
      coreutils
      procps
      util-linux
    ];
    text = ''
      unset ALTERNATE_EDITOR

      log_dir="''${XDG_STATE_HOME:-''${HOME:-/tmp}/.local/state}"
      log_file="$log_dir/emacs-gui.log"
      mkdir -p "$log_dir"
      log() {
        printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$log_file"
      }

      if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
        msg="no graphical display (WAYLAND_DISPLAY and DISPLAY are unset)"
        echo "emacs-gui: $msg" >&2
        log "error: $msg"
        exit 1
      fi

      emacs="${emacs}/bin/emacs"
      emacsclient="${emacs}/bin/emacsclient"

      if [ -n "''${XDG_RUNTIME_DIR:-}" ]; then
        socket="$XDG_RUNTIME_DIR/emacs/server"
        lock_dir="$XDG_RUNTIME_DIR"
      else
        socket="''${TMPDIR:-/tmp}/emacs$(id -u)/server"
        lock_dir="''${TMPDIR:-/tmp}"
      fi

      probe() {
        timeout 5 "$emacsclient" -w 2 -e '(emacs-pid)' >/dev/null 2>&1
      }

      wait_for_server() {
        for _ in $(seq 1 50); do
          if probe; then
            return 0
          fi
          sleep 0.2
        done
        return 1
      }

      start_daemon() {
        log "starting daemon"
        echo "emacs-gui: starting Emacs daemon" >&2
        timeout 60 "$emacs" --daemon >/dev/null 2>&1 || true
        wait_for_server
      }

      kill_daemon() {
        log "killing unresponsive daemon"
        timeout 5 "$emacsclient" -w 2 -e '(kill-emacs)' >/dev/null 2>&1 || true
        for _ in $(seq 1 50); do
          [ -S "$socket" ] || return 0
          sleep 0.1
        done
        log "daemon would not exit; sending SIGTERM"
        pkill -f -- '(^|/)emacs[^/ ]* .*--daemon' 2>/dev/null || true
        sleep 0.5
      }

      ensure_daemon() {
        if probe; then
          return 0
        fi
        if [ -S "$socket" ]; then
          log "daemon socket exists but no response; replacing daemon"
          echo "emacs-gui: replacing unresponsive Emacs daemon" >&2
          kill_daemon
        fi
        start_daemon
      }

      lock() {
        exec 9>"$lock_dir/emacs-launcher.lock"
        flock -w 20 9
      }

      unlock() {
        flock -u 9 2>/dev/null || true
        exec 9>&-
      }

      lock || {
        msg="another launcher is still starting the daemon"
        echo "emacs-gui: $msg" >&2
        log "error: $msg"
        exit 1
      }

      if ! ensure_daemon; then
        unlock
        msg="could not start the Emacs daemon"
        echo "emacs-gui: $msg (log: $log_file)" >&2
        log "error: $msg"
        exit 1
      fi

      # Release the lock before launching: a tracked client stays in the
      # foreground for the lifetime of its frame, and must not block later
      # clicks while it does so.
      unlock

      launch() {
        "$emacsclient" -c "$@"
      }

      # Capture output so the client never sees a terminal: on a
      # window-system failure it must report "could not get terminal name"
      # instead of opening a tty frame. Keep the text for classification.
      launch_output=""

      launch_once() {
        local status
        if launch_output=$(launch "$@" 2>&1); then
          if [ -n "$launch_output" ]; then
            printf '%s\n' "$launch_output" >&2
          fi
          return 0
        else
          status=$?
        fi
        return "$status"
      }

      if launch_once "$@"; then
        exit 0
      else
        status=$?
      fi

      case "$launch_output" in
        *"could not get terminal name"*|*"window system"*)
          log "window-system failure; restarting daemon"
          echo "emacs-gui: daemon cannot create a window-system frame; restarting it" >&2
          lock || {
            msg="another launcher is still working; not restarting the daemon"
            echo "emacs-gui: $msg" >&2
            log "error: $msg"
            exit 1
          }
          kill_daemon
          if ! start_daemon; then
            unlock
            msg="could not restart the Emacs daemon"
            echo "emacs-gui: $msg (log: $log_file)" >&2
            log "error: $msg"
            exit 1
          fi
          unlock
          if ! launch_once "$@"; then
            if [ -n "$launch_output" ]; then
              printf '%s\n' "$launch_output" >&2
            fi
            exit 1
          fi
          ;;
        *"can't find socket"*|*"have you started the server"*|*"No socket or alternate editor"*)
          log "lost the daemon; restarting"
          echo "emacs-gui: daemon connection lost; restarting it" >&2
          lock || {
            msg="another launcher is still working; not starting the daemon"
            echo "emacs-gui: $msg" >&2
            log "error: $msg"
            exit 1
          }
          if ! ensure_daemon; then
            unlock
            msg="could not start the Emacs daemon"
            echo "emacs-gui: $msg (log: $log_file)" >&2
            log "error: $msg"
            exit 1
          fi
          unlock
          if ! launch_once "$@"; then
            if [ -n "$launch_output" ]; then
              printf '%s\n' "$launch_output" >&2
            fi
            exit 1
          fi
          ;;
        *)
          if [ -n "$launch_output" ]; then
            printf '%s\n' "$launch_output" >&2
          fi
          exit "$status"
          ;;
      esac
    '';
  };

  clientExec = "${emacsLauncher}/bin/emacs-gui %F";

  # Written to ~/.local/share/applications (XDG_DATA_HOME), which outranks
  # the stock entries from the emacs package in /etc/profiles/per-user/mika.
  # xdg.desktopEntries cannot do this here: with useUserPackages the
  # per-user profile treats home-manager-path and the emacs package as two
  # opaque packages, so the stock emacs.desktop wins that collision.
  emacsDesktop = pkgs.makeDesktopItem {
    name = "emacs";
    desktopName = "Emacs";
    genericName = "Text Editor";
    comment = "Edit text";
    exec = clientExec;
    icon = "emacs";
    terminal = false;
    startupNotify = true;
    categories = [ "Development" "TextEditor" ];
    mimeTypes = [
      "text/english"
      "text/plain"
      "text/x-makefile"
      "text/x-c++hdr"
      "text/x-c++src"
      "text/x-chdr"
      "text/x-csrc"
      "text/x-java"
      "text/x-moc"
      "text/x-pascal"
      "text/x-tcl"
      "text/x-tex"
      "application/x-shellscript"
      "text/x-c"
      "text/x-c++"
    ];
    extraConfig.StartupWMClass = "Emacs";
  };

  # The stock emacsclient.desktop also carries StartupWMClass=Emacs, so KDE
  # could bind the frame to that entry and show a second task icon. Hidden,
  # and given an impossible WM class so it can never claim a window.
  emacsclientDesktop = pkgs.makeDesktopItem {
    name = "emacsclient";
    desktopName = "Emacs (Client)";
    exec = clientExec;
    icon = "emacs";
    terminal = false;
    noDisplay = true;
    extraConfig.StartupWMClass = "emacsclient-hidden";
  };
in
{
  # Keep the launcher itself in the profile closure; the desktop entry only
  # references it as a string.
  home.packages = [ emacsLauncher ];

  xdg.dataFile."applications/emacs.desktop" = {
    source = "${emacsDesktop}/share/applications/emacs.desktop";
    force = true;
  };
  xdg.dataFile."applications/emacsclient.desktop" = {
    source = "${emacsclientDesktop}/share/applications/emacsclient.desktop";
    force = true;
  };

  # Emacs config is a git repo of its own: the Prelude fork on GitHub
  # (upstream bbatsov/prelude kept as a remote for pulling updates).
  # Clone on first activation so a fresh machine is usable right after
  # `nyx`; never touch it afterwards — it is the user's working tree,
  # pulls/commits stay manual. Non-fatal on failure (network/ssh key)
  # so a rebuild never dies on it.
  home.activation.emacs-d = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.emacs.d/.git" ]; then
      $VERBOSE_ECHO "Cloning prelude fork into ~/.emacs.d"
      if git clone git@github.com:NeedMoreDesu/prelude.git "$HOME/.emacs.d"; then
        git -C "$HOME/.emacs.d" remote add upstream git@github.com:bbatsov/prelude.git
      else
        echo "WARNING: ~/.emacs.d clone failed (needs network + GitHub ssh key) - clone it manually" >&2
      fi
    fi
  '';
}
