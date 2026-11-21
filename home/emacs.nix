{ lib, pkgs, ... }:
let
  # One launcher: attach to the per-session daemon instead of spawning a
  # standalone Emacs. `-a ""` (== --alternate-editor=) starts
  # `emacs --daemon` on first use, `-c` opens a frame in it, and `-n`
  # returns immediately so the launcher does not hang.
  clientExec = "emacsclient -c -a \"\" -n %F";

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
