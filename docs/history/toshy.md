# Toshy (rolled back)

Toshy was evaluated as the keyboard remapper and rolled back: too
heavyweight, and it could not solve the Emacs copy/paste case cleanly.

The reason it failed is structural: Toshy's Cmd→Ctrl is a blanket GUI modmap,
so Cmd+C lands as literal keyboard-quit in Emacs.

After the rollback, keyd is back **without** the blanket Cmd→Ctrl map. The
`swapm`/`maccycle` hold-layer rework and the clipboard policy pin were picked
from the `pasteboard` branch. Since then Cmd+C/V/X are plain Super+key —
inert by design.

See [keyboard](../keyboard.md) for the current stack.
