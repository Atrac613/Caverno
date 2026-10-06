# Caverno v1.3.55

> Release date: 2026-09-29

## Summary

A provider and tool-loop reliability release: Caverno can now talk to the
Anthropic Messages API and route code reviews to a dedicated model endpoint,
while a batch of fixes hardens tool-argument decoding, delegation recovery,
and coding-workspace containment.

## Changes

### Features

- **Support the Anthropic Messages API** — Caverno can now use Anthropic
  Messages API endpoints in addition to OpenAI-compatible ones.
- **Route code reviews to a dedicated model endpoint** — Code review calls
  are sent to a dedicated model endpoint instead of the default chat model.

### Fixes

- **Report blocked delegation task preconditions** — Delegation tasks whose
  preconditions are blocked are now reported as blocked instead of being
  filed as executed.
- **Narrow tools offered during code review** — The tool set offered to the
  model during code review is narrowed so reviews cannot edit or answer with
  stdout.
- **Preserve repeated read evidence in final answers** — Repeated file-read
  evidence is preserved when composing final answers.
- **Bound and cancel semantic embedding jobs** — Semantic embedding jobs are
  now bounded and can be cancelled instead of running unbounded.
- **Omit chat_template_kwargs without an endpoint opt-in** —
  `chat_template_kwargs` is no longer sent unless the endpoint opts in.
- **Allow Anabasis parent tool search** — Anabasis parent agents can search
  for tools again.
- **Recover saved workflow delegation after validation** — Saved workflow
  delegations are recovered after validation instead of being lost.
- **Contain foreground Python commands in the coding workspace** —
  Foreground Python commands are contained to the coding workspace.
- **Close the idle browser when the macOS window closes** — The idle browser
  is closed when the macOS window closes.
- **Serialize structured JSON write_file content** — Structured JSON content
  passed to `write_file` is serialized correctly.
- **Check tool argument types before the batch guards** — Tool argument
  types are validated before the batch guards run.
- **Decode stringified options that end in a stray closer** — Stringified
  option arguments ending in a stray closing bracket are decoded correctly.

### Tooling

- **Add firing signatures for write_file content type rejection and
  trailing-text argument handling** — Firing signatures were added for the
  `write_file` content type rejection and for trailing-text argument
  handling.

### Documentation

- **Track tool definition cost across request paths** — Tool definition cost
  is now tracked across request paths.
- **Add the guard-ordering and stringified-options lessons to FOR_ME.md** —
  The guard-ordering and stringified-options lessons are recorded in
  FOR_ME.md.

## Version

- `1.3.55+69` (proposed)