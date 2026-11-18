{ lib, ... }:
{
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
