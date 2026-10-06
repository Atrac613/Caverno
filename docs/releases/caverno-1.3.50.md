# Caverno v1.3.50

> Release date: 2026-09-25

## Summary

A fix-focused release for iOS and macOS: built-in tool calls whose nested
arguments arrive as JSON text are now decoded and dispatched instead of
aborting the turn, and the fix-firing checks gain signatures for the two
recently added guards.

## Changes

### Fixes

- **Decode stringified tool arguments of the declared type** — The argument
  type guard only rejected, but the model's tool-call serializer sometimes
  stringifies nested values: in one session `ask_user_question` received its
  `options` as JSON text and `allow_other` as `"True"`, the model could not
  send anything else, and the turn aborted on the verbatim repeat. A string
  that is exactly the JSON text of the declared type is now decoded and the
  call dispatched; everything else is still rejected.
  (`lib/features/chat/domain/services/tool_argument_type_guard.dart`)

### Testing

- **Add firing signatures for the argument type guard and search anchors** —
  Both guards fired on their first real session (42f1b8d5, build a92ece3e3);
  their firing signatures are now recorded in the fix-firing checks.
  (`tool/check_fix_firings.py`)

## Version

- `1.3.50+64` (proposed)