# CLI4 Doctor Foundation

## Task

- Goal: Define the first supported CLI release target and add a bounded,
  automation-safe `caverno doctor` command before standalone packaging work.
- User-visible behavior: A terminal user can inspect effective configuration,
  endpoint and selected-model availability, storage, an optional project, and
  terminal tool-runtime readiness without opening the Caverno window or
  exposing credentials.
- Non-goals: Publishing release artifacts, shell completion, Linux or Windows
  runner changes, routine execution, Computer Use, model inference, MCP tool
  execution, or upgrading dependencies and application data.

## Supported Platform Matrix

| Platform | CLI4 foundation status | Evidence required before promotion |
| --- | --- | --- |
| macOS arm64 | Initial supported target | Packaged process tests prove `version`, `doctor`, and one runtime command execute without a visible app window |
| macOS x86_64 or universal | Deferred | A matching signed build and the same packaged process gate pass on the target architecture |
| Linux | Unsupported | The GTK runner must route CLI invocations without constructing or presenting a window, then pass process-level CLI tests |
| Windows | Unsupported | The Win32 runner must bypass GUI single-instance activation and window construction for CLI invocations, preserve console streams, and pass process-level CLI tests |

Unsupported platforms must fail or be documented explicitly; a Flutter build
completing on a platform is not sufficient evidence that the terminal client is
headless there.

## Artifact Contract

The first packaging follow-up will produce an architecture-stamped archive and
an adjacent checksum manifest:

```text
cli-release/
|-- caverno-cli-<version>-macos-arm64.zip
`-- SHA256SUMS

caverno-cli-<version>-macos-arm64.zip
|-- Caverno.app/
`-- bin/
    `-- caverno
```

- `Caverno.app` is the existing signed, notarized, and stapled release bundle;
  the Flutter executable is not separated from its required frameworks and
  resources.
- `bin/caverno` resolves the adjacent bundle relative to its own location,
  forwards every argument unchanged to
  `Caverno.app/Contents/MacOS/Caverno`, and preserves the child exit status.
- The launcher contains no absolute build-machine paths and works after the
  archive is extracted into a path containing spaces.
- The adjacent `SHA256SUMS` covers the final distributable archive. A later
  packaging task must define whether an additional detached signature is
  required.
- Packaging reuses the existing macOS signing and notarization pipeline, but a
  CLI archive is not published implicitly by the Sparkle release command.

## Doctor Contract

### Invocation

```text
caverno doctor [--project PATH] [--json]
               [--base-url URL] [--model ID] [--api-key VALUE]
               [--data-dir PATH]
```

Configuration precedence remains flags, environment, persisted settings, then
built-in defaults. Doctor must reuse the production resolver rather than
implementing a second precedence chain.

### Required checks

1. Resolve and validate the effective endpoint, model, and data root.
2. Probe the configured OpenAI-compatible `GET /models` endpoint with the
   effective authorization header and a fixed short timeout.
3. Confirm that the configured model is present in the returned model IDs.
4. Confirm that the data root is readable and writable without opening Hive or
   Drift, running migrations, or retaining a probe file.
5. When `--project` is present, canonicalize the directory and confirm that it
   exists and is accessible without registering or mutating a coding project.
6. Report terminal runtime capability groups, including tools disabled by the
   headless safety boundary. Doctor must not start an LLM turn, connect to MCP,
   request approval, or execute a tool.

Each check has a stable identifier, `pass`, `warning`, `fail`, or `skipped`
status, a bounded duration, and a remediation message when it is not ready.
Optional capability warnings do not mask required-check failures.

### Output and redaction

- Human output is concise and prints one row per check plus the final status.
- `--json` emits exactly one newline-delimited `doctor_report` event with
  `schemaName: caverno_cli_doctor_report`, `schemaVersion: 1`, an overall
  status, sanitized configuration metadata, and ordered checks.
- The API key, authorization header, URL user information, URL query and
  fragment, environment values containing credentials, and temporary probe
  names never appear in human output, JSON output, diagnostics, or thrown
  errors.
- The endpoint may expose only its sanitized scheme, host, port, and path. The
  selected model and canonical project path may be reported because they are
  explicit diagnostic subjects.

### Exit codes

- `0`: all required checks pass; optional warnings may remain.
- `64`: invalid CLI syntax.
- `65`: invalid endpoint, model, data-root, or project input.
- `69`: the endpoint, configured model, or required tool runtime is
  unavailable.
- `74`: storage cannot be inspected safely or the temporary writability probe
  cannot be removed.

When more than one check fails, storage safety has precedence over service
availability, which has precedence over invalid optional project input. The
JSON report still includes every check that can run safely.

## Context

- Affected components:
  `lib/features/terminal/application/caverno_cli_contract.dart`,
  `lib/features/terminal/application/caverno_cli_arguments.dart`,
  `lib/features/terminal/application/caverno_cli_runtime_configuration.dart`,
  a new pure doctor service and report model, CLI process composition, CLI
  usage text, and the macOS command-line invocation allowlist.
- Related docs: `docs/roadmap.md` and
  `docs/caverno_cli_terminal_contract.md`.
- Reference patterns: `CavernoConversationQuery` for a command that completes
  without starting an LLM run, `CavernoCliRedactor` for last-mile output
  defense, and `ModelRemoteDataSource.parseModelCatalogResponse` for strict
  OpenAI-compatible model response parsing.
- Known quirks: The existing model catalog load can fall back to provider-
  specific endpoints and is not a bounded health probe. Doctor needs a narrow,
  injected HTTP probe so endpoint failures remain attributable and testable.

## Implementation Notes

- Keep argument parsing, check orchestration, report serialization, and HTTP
  transport behind independent pure or injected boundaries.
- Route doctor before normal runtime bootstrap opens application databases or
  creates a conversation.
- Always close the HTTP client and remove a storage probe in `finally`.
- Use monotonic elapsed durations and deterministic check ordering.
- Add `doctor` to both Dart and macOS native CLI-recognition lists.
- Generated files needed: None unless the implementation deliberately adopts a
  generated immutable report model.
- Migration concerns: Doctor must not read, write, or advance migration markers.

## Similar-Pattern Search

- Search terms: `listModelCatalog`, `/models`, `looksLikeCliInvocation`,
  `isCommandLineInvocation`, `CavernoCliRedactor`, and CLI exit-code mappings.
- Files inspected: Terminal argument/process code, model remote data source,
  macOS AppDelegate, Linux GTK runner, Windows runner, and macOS release tools.
- Follow-up tasks found: macOS archive packaging, Linux headless runner routing,
  Windows console/headless routing, shell completion and upgrade guidance, and
  the combined CLI4 release gate.

## Acceptance Criteria

- `caverno doctor` and `caverno doctor --json` parse without a prompt or LLM
  run and use the same effective configuration as runtime commands.
- A healthy endpoint with the selected model, writable storage, and valid
  optional project exits `0` with deterministic human and JSON reports.
- Timeout, non-2xx, malformed response, missing configured model, invalid
  project, unwritable storage, and failed probe cleanup map to the documented
  check statuses and exit codes.
- Tests prove credentials and URL secrets are absent from every output and
  exception path.
- The storage check leaves no file and does not initialize or migrate Hive or
  Drift state.
- The packaged macOS executable runs doctor without activating an existing GUI
  instance or displaying a new window.
- The terminal contract documents the doctor schema and the currently
  unsupported platform and tool boundaries.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/terminal/application/caverno_cli_arguments_test.dart \
  --test test/features/terminal/application/caverno_cli_doctor_test.dart \
  --test test/features/terminal/presentation/caverno_cli_doctor_presenter_test.dart \
  --test test/tool/desktop_single_instance_test.dart
```

After focused tests pass, build the Debug macOS app and invoke `version` and
`doctor --json` through `Caverno.app/Contents/MacOS/Caverno` with an isolated
data root. Confirm both processes exit without a visible Caverno window, then
run `tool/codex_verify.sh`.

## Handoff Notes

- Summary: Implemented the doctor parser, read-only settings resolution,
  bounded OpenAI-compatible model probe, removable storage probe, optional
  project inspection, stable report and exit-code model, redacted human/JSON
  presenters, shared terminal tool exclusions, and macOS CLI recognition.
- Tests run: The focused `tool/codex_verify.sh` gate passed 48 tests with no
  analyzer findings or generated-file drift. It covers arguments, diagnostics,
  presentation, read-only settings, terminal runtime policy, docs, and native
  single-instance recognition.
- Coverage or low-coverage notes: Exercise every check result and exit-code
  precedence branch with injected filesystem, clock, and HTTP dependencies.
- Risks or follow-ups: A fresh Debug macOS build reached code signing but failed
  because the timestamp service was unavailable. The packaged no-window doctor
  smoke remains required after signing connectivity is restored. Do not claim
  Linux, Windows, universal macOS, or standalone artifact support from
  Dart-only tests.
