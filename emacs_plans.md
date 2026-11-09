# emacs_plans.md — F14/XF86Launch5 as an Emacs Super prefix

## Confirmed facts (2026-11-09)

- xremap emits `KEY_F14` (evdev 184) -> X keycode 192 -> keysym `XF86Launch5`.
- `(global-set-key (kbd "<XF86Launch5>") ...)` works in Emacs (XWayland):
  tested with a `message "hello world"` lambda, fired on Cmd+c.
- `C-x @ s` is `event-apply-super-modifier` (looked up in `function-key-map`
  on emacs 31.1). It reads the NEXT event and applies Super to it.
  This is the model for what we want XF86Launch5 to do.

## The scheme

xremap (already committed):
- emacs modmap block: `Super_L -> F13` (Cmd = virtual modifier)
- emacs keymap block: every `F13-<key>` -> `[F14, <key>]` (two-event sequence)
  - letters a-z, digits 0-9, F1-F12, symbols (minus/equal/leftbrace/rightbrace/
    apostrophe/backslash/semicolon/comma/dot/slash/enter/backspace/delete)
  - tab/grave excluded: keyd consumes them upstream
  - arrows/home/end excluded: fall through to generic block
  - space excluded: Cmd+space = Alt-F2 run dialog is better than any chord

Emacs (to write):
- Bind `<XF86Launch5>` to `event-apply-super-modifier` (or a variant).
- After F13-<key> fires, the second event in the sequence arrives as a bare
  key; `event-apply-super-modifier` reads it and applies Super.
- Result: Cmd+X in Emacs becomes `s-X` — the native Super chord, no XKB
  option needed, fully per-app, no right-cmd/Menu wart.

## Open questions / caveats

- `event-apply-super-modifier` is a term-mode command; whether it works
  outside term-mode as a plain global binding needs testing. Fallback:
  write a small equivalent that reads the next event and calls
  `event-apply-modifier` or constructs `s-<key>` directly.
- Shift variants (Cmd+Shift+X): xremap inexact matching lets Shift through,
  so the sequence fires while Shift is held; Emacs will see `S-s-<key>`.
  Decide later whether that's acceptable.
- Currently left cmd = F13 (test state), so `s-` is gone in Emacs until the
  elisp binding is installed. Rollback modmap: `Super_L: Super_L`.
- The hello-world probe binding is gone after restart; reinstall it from
  scratch (see confirmed facts above).
