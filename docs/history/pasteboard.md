# pasteboard (closed)

The pasteboard experiment is **closed**. Do not resurrect it on `master`.

## What it was

Two pieces lived on the `pasteboard` branch, with the full design history in
that branch's `DESIGN.md` (§13–15):

- a Cmd+C live-copy daemon;
- a Cmd+V paste verb implemented as KWin `fake_input` keysym typing.

## Why it was closed (v4, 2026-11-07)

Typing real keysyms while Cmd is down has unforeseeable consequences in
consumers: Enter/Tab semantics differ per app. Cmd+C alone isn't useful
without the paste side, so the combination was dropped.

Everything keyboard-relevant from the branch was already picked into
`master` (the `swapm`/`maccycle` hold-layer rework and the clipboard policy
pin; see [Toshy](toshy.md) and [keyboard](../keyboard.md)).
