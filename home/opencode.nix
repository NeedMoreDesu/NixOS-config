{ lib, pkgs, ... }:
let
  # agent-browser ships SKILL.md trees inside the CLI package. Copy the
  # version-matched core skill (which itself lists the specialized skills)
  # into opencode's user skill dir as real files, not store symlinks.
  agentBrowserSkills = [ "core" ];

  # Copy trees and record what was installed in ~/.nix_update_paths, so the
  # next activation removes stale copies first. See scripts/nix-copy-tree.sh.
  nixCopyTree = pkgs.writeShellScriptBin "nix-copy-tree" ''
    export PATH=${pkgs.coreutils}/bin:$PATH
    ${builtins.readFile ../scripts/nix-copy-tree.sh}
  '';
in
{
  # opencode TUI theme, declarative (aura — purple, pairs with seance's
  # Monokai Soda). assets/opencode/opencode.jsonc is policy; the agent-browser
  # skill copy below is the one managed exception (tracked in
  # ~/.nix_update_paths); everything else under plugins/, skills/ and
  # node_modules/ stays user-local. `force` re-links over the old unmanaged
  # file / any theme-picker writes.
  xdg.configFile."opencode/opencode.jsonc".source = ../assets/opencode/opencode.jsonc;
  xdg.configFile."opencode/opencode.jsonc".force = true;

  # agent-browser's core SKILL.md is copied out of the CLI package on every
  # activation (real files, not store symlinks). scripts/nix-copy-tree.sh
  # tracks installed paths in ~/.nix_update_paths and removes stale copies
  # before the next copy. Specialized skills stay runtime-only — core's
  # SKILL.md lists them and they are fetched with `agent-browser skills get`.
  home.activation.agent-browser-skills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${nixCopyTree}/bin/nix-copy-tree \
      "$HOME/.nix_update_paths" \
      "$HOME/.config/opencode/skills" \
      agent-browser \
      ${lib.escapeShellArgs (lib.concatMap (name: [
        "agent-browser-${name}"
        "${pkgs.agent-browser}/skill-data/${name}"
      ]) agentBrowserSkills)}
  '';
}
