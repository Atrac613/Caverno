# Caverno agent guide

Caverno is a Flutter chat client for OpenAI-compatible LLM APIs. It supports
MCP and built-in tools, session memory, voice I/O, routines, remote coding,
and the Apple Watch companion app.

This file contains repository-wide rules and a compact map of the codebase.
Keep it short and update it when a rule stops being useful. Put detailed,
workflow-specific procedures in the referenced documentation instead of
expanding this file.

## Scope and verification

- Read only the files and documentation relevant to the current task. Use the
  references below when their condition applies; do not read every guide before
  every edit.
- Choose verification appropriate to the change. Documentation-only edits
  usually need a diff and reference check; behavior changes need relevant
  tests. Report checks performed and any unverified live or device behavior.
- Complete the requested workflow: implement, inspect the result, run the
  relevant checks, and fix failures caused by the change. Stop only when the
  acceptance condition is met or a concrete external blocker remains.
- Read-only research and API checks within the requested task are permitted.
  Pushes, publication, purchases, outbound messages, and pull-request creation
  require user authorization; authorization already given in the task applies.

## Repository map

```text
lib/
|-- core/                       # Shared services, types, constants, and utils
|-- features/chat/              # Chat, Plan Mode, tools, persistence, memory
|-- features/routines/          # Scheduled prompts and run history
|-- features/remote_coding/     # Paired-device remote coding
|-- features/settings/          # App configuration and imports/exports
|-- features/watch/             # Apple Watch companion integration
`-- main.dart                   # App bootstrap and provider overrides
```

The project uses Riverpod `Notifier` providers, Freezed entities for persisted
aggregates, Hive for conversations and memory, and SharedPreferences for
settings, routines, coding projects, and window state. Navigation uses Flutter
routes, dialogs, bottom sheets, and the conversation drawer; there is no router
package.

## Commands

The repository pins Flutter through FVM (`.fvmrc`). Prefer the quiet wrappers
for agent runs so failures remain visible without flooding the transcript.

```bash
fvm flutter pub get
fvm flutter analyze
tool/flutter_test_quiet.sh                       # Full test suite
tool/flutter_test_quiet.sh test/widget_test.dart # Focused suite
tool/codex_verify.sh                             # Verification gate
tool/codex_rg.sh -- PATTERN [PATH ...]            # Bounded discovery
rg PATTERN [PATH ...]                            # Exact follow-up search
fvm flutter run
```

Use `tool/codex_verify.sh --coverage` when coverage or missing edge cases are
part of the task. Use raw `fvm flutter test` only when the reporter stream is
itself needed. A full JSON reporter result is retained at
`build/test_reports/flutter_test.json`.

When affected local tests use disposable fixtures and have no production
access, run them, fix failures caused by the requested change, and rerun them
without asking for approval at each step.

## Conditional references

- When drafting non-trivial task descriptions, use `docs/codex_task_template.md`.
- Large-file refactors: follow `docs/large_file_refactor_plan.md`.
- macOS `flutter_tester` canaries targeting an HTTP LAN LLM endpoint: use
  `tool/with_live_llm_loopback.sh -- <canary command>` and follow
  `docs/live_llm_canary_agent_runbook.md`; do not create ad hoc tunnels or
  fixed-port relays.
- Lint rule changes: read `docs/lint_policy.md` first. Never run bare
  `dart fix --apply`; scope it with `--code=<rule>`.
- Session-log schema, redaction, retention, or analysis: read
  `docs/session_logs.md` first. Logs can contain prompts, tool arguments,
  results, review packets, and diff previews; treat them as sensitive and never
  commit them.
- Release or distribution work: inspect the current release scripts and
  platform configuration before running a release gate. Pass `--quiet-output`
  to repository release and live-canary scripts that support it.
- Apple Watch behavior: distinguish simulator/compile evidence from signed
  device behavior; hardware Dictation and Smart Stack behavior require a
  physical or otherwise signed verification path.

## Chat compatibility notes

- `McpToolService` is available even without a remote MCP server so built-in
  tools continue to work. Remote MCP supports trusted HTTP and desktop stdio
  servers.
- Tool results are usually sent back as a user-role message because some local
  models handle tool-role messages poorly. A clearly terminal tool-role final
  response may still be accepted directly.
- Streaming content may contain `<think>`, `<tool_call>`, or `<tool_use>` tags;
  `ContentParser` must continue to handle incomplete tags safely.

The approval audit trail is always on, including in release builds, and is
not user-disableable. Session logs and app logs have separate on/off settings.
Consult `docs/session_logs.md` for logging behavior and retention details.

## Generated entities

When modifying a Freezed class or any entity with committed `*.freezed.dart` or
`*.g.dart` outputs, run:

```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

Generated files are committed. Include their intentional changes in the diff.

## Configuration sources

Look up API defaults in `lib/core/constants/api_constants.dart` and settings
defaults in `lib/features/settings/domain/entities/app_settings.dart`. Use
`.fvmrc` for the pinned Flutter version. Keep changing values in their source
files rather than duplicating them here.

## Language and documentation

All repository code, comments, docstrings, documentation, generated error
messages, logs, commit messages, and pull-request text must be in English.
Prefer concise comments that explain why.

## Git conventions

- Keep commits atomic and local unless the user asks for publication.
- Use English Conventional Commit messages with an imperative subject of at
  most 72 characters and no final period, for example `fix: handle empty tool
  results`.
- Allowed types include `feat`, `fix`, `refactor`, `docs`, `chore`, `test`,
  `style`, `perf`, `ci`, and `build`.
- Do not add `Co-authored-by`, `Generated by Codex`, or other AI attribution.
- Pull-request titles use Conventional Commits without tool prefixes such as
  `[codex]`. Write the body in ordinary English prose describing the change
  and relevant verification.
