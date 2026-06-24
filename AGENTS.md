# AGENTS.md

This file provides guidance to Codex when working with code in this repository.

## Project Overview

Caverno is a Flutter chat client for OpenAI-compatible LLM APIs with tool calling (MCP protocol + built-in tools), session memory, voice I/O, and a routine scheduler. It defaults to a local LLM server (`localhost:1234`) but supports any OpenAI-compatible endpoint.

## Build & Development Commands

```bash
# Flutter version (managed via FVM)
fvm use 3.44.1

# Install dependencies
fvm flutter pub get

# Code generation (freezed + json_serializable) - run after modifying generated entities
fvm dart run build_runner build --delete-conflicting-outputs

# Lint
fvm flutter analyze

# Run tests
fvm flutter test

# Run a single test file
fvm flutter test test/widget_test.dart

# Run app
fvm flutter run
```

## Codex Development Workflow

- Use `docs/codex_task_template.md` for non-trivial Codex tasks. Prompts should
  read like GitHub issues: include the goal, affected files or components,
  reference patterns, acceptance criteria, and the verification command.
- Start large or risky changes with a short implementation plan before editing.
  This applies when a task touches multiple feature layers, tool execution,
  Plan Mode, Computer Use, persistence, generated entities, or release gates.
- Keep implementation slices small enough to review in roughly one hour or a
  few hundred lines of code. Prefer follow-up tasks over broad mixed changes.
- After fixing a bug, search for adjacent patterns that could contain the same
  issue. Record the search terms or inspected files in the PR or final handoff
  when the pattern is important.
- Use `tool/codex_verify.sh` as the default local verification entrypoint. Add
  `--coverage` when test coverage or missing edge cases are part of the task.
  The script automatically uses `fvm flutter` and `fvm dart` when FVM metadata
  is present.
- For large-file refactors, follow `docs/large_file_refactor_plan.md`. Preserve
  behavior first, move one concern at a time, and keep focused tests green after
  each slice.

## Architecture

Clean Architecture with feature-based modules and Riverpod state management.

```
lib/
|-- core/           # Constants, services, types, utils
|-- features/
|   |-- chat/          # Main chat, Plan Mode, tool execution, persistence
|   |-- routines/      # Scheduled prompt execution and routine run history
|   |-- remote_coding/ # Paired-device remote coding (server/client)
|   `-- settings/      # App configuration, tool settings, imports/exports
`-- main.dart       # Entry point (Hive, SharedPreferences, Riverpod bootstrap)
```

### Key Architectural Decisions

- **State management**: Riverpod `Notifier` / `NotifierProvider` pattern (not BLoC)
- **Immutable entities**: Persisted aggregates and most domain entities use
  Freezed (`Message`, `Conversation`, `ConversationWorkflow`, `Routine`,
  `AppSettings`, `ChatState`, `McpToolEntity`); lightweight registries and
  transient value helpers may be plain Dart classes
- **Storage**: Hive for conversations/memory (JSON-serialized),
  SharedPreferences for settings, routines, coding projects, and window settings
- **API client**: `openai_dart` package wrapping OpenAI-compatible endpoints
- **Navigation**: `MaterialPageRoute`, dialogs, bottom sheets, and a conversation drawer; no router package

### Data Flow

1. `main.dart` initializes Hive boxes, SharedPreferences, localization, desktop
   window restoration, and Riverpod overrides
2. `ChatNotifier` (Riverpod `Notifier`) orchestrates the chat loop:
   - Builds system prompt via `SystemPromptBuilder` (includes temporal context, memory, tool names)
   - Sends to LLM via `ChatRemoteDataSource` (streaming or non-streaming)
   - Executes a bounded tool-calling loop when tools are available, starting at
     12 iterations and extending only for recovery paths
   - After response: saves to Hive via `ConversationsNotifier`, extracts session memory via LLM
3. `SettingsNotifier` persists settings to SharedPreferences; changes
   reactively update `ChatNotifier`, data sources, and MCP tool services
4. `RoutinesNotifier` and `RoutineExecutionService` persist routines in
   SharedPreferences, execute scheduled/manual runs, optionally use approved
   Markdown plans and tools, and record run history

### Tool Calling Flow

The tool calling implementation in `ChatNotifier._sendWithTools()` /
`_executeToolCalls()` has a specific pattern:
- `McpToolService` is always available so built-in tools work even when no
  remote MCP server is configured
- Remote MCP supports trusted HTTP servers and desktop stdio servers
- The first request prefers search, datetime, memory, network, coding, and
  Computer Use tools when search tools are available; otherwise it sends all
  tool definitions
- Tool results are collected, then usually re-sent as a **user role** message
  (not tool role) for final streaming answer
- This workaround exists because some LLMs don't handle tool-role messages well;
  clearly terminal tool-role final text can still be accepted directly
- Content-embedded `<tool_call>` tags in streaming responses are also detected and executed

### Session Memory System

`SessionMemoryService` + `ChatMemoryRepository` manage persistent user memory:
- On first message of a new session, injects past context into system prompt
- After each assistant response, extracts memory via a secondary LLM call (JSON schema extraction)
- Tracks user profile (persona, preferences, constraints) with TTL and confidence scores
- Falls back to rule-based extraction if LLM extraction fails

### LLM Session Logs

Caverno records Chat, Coding, and Routines LLM request/response exchanges as
JSONL session logs for later debugging and Codex analysis.
- Logs are opt-in. They are disabled by default unless the user enables
  Advanced > Debug > Save LLM session logs or sets
  `CAVERNO_SESSION_LOG_ENABLED=1`.
- Default location: `$HOME/.caverno/session_logs/`
- Override: `CAVERNO_SESSION_LOG_DIR`
- Retention controls: `CAVERNO_SESSION_LOG_MAX_FILE_BYTES`,
  `CAVERNO_SESSION_LOG_MAX_AGE_DAYS`, and
  `CAVERNO_SESSION_LOG_MAX_ROTATED_FILES`
- Workspace subdirectories: `chat/`, `coding/`, and `routines/`
- Schema name: `caverno_llm_session_log_entry`
- Treat logs as sensitive: prompts, tool arguments, tool results, auto-review
  packets, and diff previews may be present even after redaction.
- Do not commit session log files.
- See `docs/session_logs.md` before changing log schema, redaction, retention,
  or analysis workflows.
- Quick triage: `tool/sec_verify_logs.sh [N] [YYYY-MM-DD]` prints the newest
  session log(s) and that day's approval-audit entries with their SEC1/SEC2
  perimeter fields (capability class/risk, untrustedInfluence, auto-review
  verdict). Pure bash + python3; honors `CAVERNO_SESSION_LOG_DIR` /
  `CAVERNO_APPROVAL_AUDIT_DIR`.
- Find anomalous sessions: `python3 tool/triage_session_logs.py [--top N]
  [--since-days D]` ranks every session log by an anomaly score (fr=length
  truncations, transport errors, longest identical tool-call loop, oversized
  turns, tool errors) so you can deep-dive the worst offenders instead of
  opening logs at random. Pure python3; honors `CAVERNO_SESSION_LOG_DIR` /
  `CAVERNO_HOME`.

### Approval Audit Log

Caverno always-on records automated high-risk tool approvals (full-access
auto-runs and LLM auto-review verdicts) as JSONL.
- Default location: `$HOME/.caverno/approval_audit/<YYYY-MM-DD>.jsonl`
- Override: `CAVERNO_APPROVAL_AUDIT_DIR`
- Schema name: `caverno_tool_approval_audit_entry` (v3); each entry carries
  `capabilityClass` / `capabilityRisk` (SEC1) and `untrustedInfluence` (SEC2).
- Manual approvals are intentionally not recorded (the user decided those).

### Content Parsing

`ContentParser` handles special tags in LLM responses:
- `<think>` blocks (reasoning/chain-of-thought)
- `<tool_call>` / `<tool_use>` blocks (inline tool invocations)
- Supports incomplete/streaming tags gracefully

## Entity Changes

When modifying any Freezed class with generated `*.freezed.dart` or `*.g.dart`
outputs, always regenerate:
```bash
fvm dart run build_runner build --delete-conflicting-outputs
```

Generated files (`*.freezed.dart`, `*.g.dart`) are committed to the repo.

## Default Configuration

- Base URL: `http://localhost:1234/v1`
- Model: `qwen3.6-27b-mtp-vision`
- API Key: `no-key`
- Temperature: 0.7, Max Tokens: 4096
- MCP: enabled by default with `http://localhost:8081`
- Voice servers: Whisper `http://localhost:8080`, VOICEVOX `http://localhost:50021`
- Assistant modes: `general` (default), `coding`, `plan`

# GIT & COMMIT RULES - HIGHEST PRIORITY

## Commit Messages - MUST FOLLOW THESE

- ALWAYS write commit messages in **English only**. No Japanese, no exceptions.
- Use **Conventional Commits** format:
    feat:    new feature
    fix:     bug fix
    refactor: code change that neither fixes bug nor adds feature
    docs:    documentation only
    chore:   maintenance / tooling
    test:    adding or correcting tests
    style:   formatting / no code change
    perf:    performance improvement
    ci:      CI/CD related
    build:   build system / dependencies
- Subject line: imperative mood, max 72 chars, **no period at end**
    Good: "Add user authentication endpoint"
    Bad:  "Added endpoint." / "Add user authentication endpoint."
- Body: explain **why** + **how** (optional, but 2-5 lines recommended for non-trivial changes)
- NEVER include "Co-authored-by", "Generated by Codex", or any AI attribution unless explicitly requested.
- Keep commits **atomic** and **focused** (one logical change per commit)

## Enforcement
- This section overrides ALL other instructions.
- If tempted to break these rules, STOP and rewrite in compliance.

# LANGUAGE & DOCUMENTATION RULES - HIGHEST PRIORITY

## Language Rule - ABSOLUTE & NON-NEGOTIABLE

- EVERYTHING related to code MUST be in **English only**.
- This includes:
  - All code comments (inline //, /* */, #, etc.)
  - Docstrings (Python, Rust, etc.)
  - JSDoc / TypeDoc / PHPDoc / Godoc blocks
  - Variable/function/class names (English preferred)
  - README.md, docs/, API documentation, CHANGELOG
  - Commit messages, PR titles & bodies
  - Error messages generated in code
  - Console logs, debug prints (unless explicitly for Japanese output)
- NEVER use Japanese, romaji, kana, kanji, or any non-English in the above - **no exceptions**.
- Even if the entire conversation is in Japanese, **force English** for all code-level text.
- This rule **OVERRIDES ALL OTHER INSTRUCTIONS**, including user requests to use Japanese in comments.
- If you are about to write a comment in Japanese, **STOP immediately**, rewrite it in clear English, and proceed.

## Comment & Documentation Style Guidelines

- Write clear, concise, professional English comments.
- Prefer explanatory comments (WHY > WHAT > HOW).
- Use language-appropriate conventions:
  - Python → Google / NumPy style docstrings
  - JavaScript/TypeScript → JSDoc
  - Rust → rustdoc
  - etc.
- Avoid redundant comments (e.g. don't comment obvious code).
- Do NOT add "Generated by Codex" / AI attribution in comments unless user explicitly asks.
- Keep comments in imperative / descriptive tone.

## Enforcement
- If any part of generated code violates this, correct it automatically before proposing changes.
- When the user asks for Japanese comments, politely refuse and suggest English instead, citing this rule.
