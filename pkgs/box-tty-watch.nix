{
  lib,
  stdenv,
}:

# In-box TTY resize watcher for `box` (shell/box.sh). bwrap --new-session
# detaches the sandboxed command from the terminal's foreground process
# group, so TUIs never see SIGWINCH. The helper polls stdin's TIOCGWINSZ and
# sends SIGWINCH to the box PID namespace on change.
stdenv.mkDerivation {
  pname = "box-tty-watch";
  version = "0.1.0";

  src = ./box-tty-watch.c;

  dontUnpack = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -o box-tty-watch "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 box-tty-watch "$out/bin/box-tty-watch"
    runHook postInstall
  '';

  meta = {
    description = "SIGWINCH watcher for bwrap --new-session boxes";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "box-tty-watch";
  };
}