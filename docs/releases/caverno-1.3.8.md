# Caverno v1.3.8

> Release date: 2026-06-23

## Summary

Multi-participant chat coordination, semantic search (LL5), personal evaluation harness (LL12/LL14/LL19/LL23), security perimeter observability (SEC1/SEC2), and foundational improvements for tool reliability and model capability profiling.

## Changes

### Features

- **Multi-participant turn coordination** — Added full support for multi-agent/participant conversations with turn management, roster controls, invite presets, and streaming integration. (`participant_turn_coordinator.dart`, `chat_notifier.dart`)
- **LL5 semantic history search** — Implemented semantic-aware conversation search using embeddings, a drift/SQLite vector store, and cosine similarity, replacing/augmenting basic FTS. (`ll5_semantic_search_service.dart`, `drift_vector_store.dart`)
- **Personal evaluation harness (LL12/LL14/LL19/LL23)** — Added in-app personal eval recorder, replay foundation, per-model harness configuration, handoff measurement runners, and edit apply telemetry. (`personal_eval_suite_runner.dart`, `model_profile.dart`)
- **SEC1/SEC2 security perimeter observability** — Introduced tool perimeter context in approval UIs, untrusted-influence recording in audit logs, and taint-aware approval auto-review. (`tool_perimeter_context.dart`, `conversation_taint_state.dart`)
- **LaTeX math rendering** — Added support for rendering LaTeX math blocks in chat markdown. (`markdown_render_sanitizer.dart`)
- **Skill authoring tools (SKILL1/SKILL2)** — Added `save_skill` tool for in-chat skill authoring and `/skill` command with diff preview.
- **Model capability profiling** — Added bounded model capability auto-probes, persistent capability profiles, and prefix-stable tool loop settings.
- **F4/F6 tool and storage improvements** — Migrated storage to drift/SQLite with FTS history search (F4), guarded built-in tool initial-load classification (F6), and derived initial tool-search load from registry.

### Fixes

- **Participant turn stability** — Fixed issues with participant turns being chat-only, serializing conversation messages correctly, and routing participant roles through the system prompt.
- **Tool execution reliability** — Fixed `save_skill` inclusion in initial tool selection, constrained ask-user answer reuse by turn, and kept ask-user answers sticky per turn.
- **Git commit guard** — Narrowed the `git_execute_command` commit preflight to only block when a *staged* file also has unstaged worktree edits (the stale-index footgun), instead of blocking any commit while unrelated files are unstaged or untracked. (`git_tools.dart`)
- **Streaming and truncation handling** — Added flags for final answers truncated at the max-token limit and raised default max tokens from 4096 to 8192.
- **Model lifecycle** — Added auto-preparation for switched primary models and logging for local model lifecycle actions.

### Refactors

- **MCP tool definitions** — Split MCP built-in tool definitions for better modularity.
- **Tool classification** — Refactored initial tool-search load derivation from the registry (F6 follow-up).

### Testing

- **Participant and eval coverage** — Added tests for participant invite sheets and isolated personal eval record page dependencies.

### Documentation

- **LL28 and roadmap updates** — Marked LL28 implementation complete, aligned LL28 roadmap names, and updated future platform vision layers.
- **Security and feature docs** — Added documentation for F6 built-in tool classification guards and SEC1/SEC2 perimeter fields.

## Version

- `1.3.8+19` (proposed)

## Notes

This is a major feature release focusing on multi-agent collaboration, semantic search, and robust evaluation tooling. Security observability has been significantly enhanced with taint tracking and perimeter context.
