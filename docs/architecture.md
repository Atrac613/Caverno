# Caverno Architecture

Extracted from `CLAUDE.md` so the agent entrypoint stays short. Read this before
changing the chat loop, the tool-calling path, the plan system, or session
memory. `AGENTS.md` keeps its own, deliberately shorter map and is maintained
independently of this file.

Last verified against the tree on 2026-09-18. Treat anything here as a starting
point, not as evidence: check the source before relying on a claim.


Clean Architecture with feature-based modules and Riverpod state management.

```
lib/
├── core/
│   ├── constants/    # API defaults, system prompt constants
│   ├── security/     # Redaction and sensitive-value handling
│   ├── services/     # TTS/STT, Voicevox, Whisper, SSH, BLE, WiFi, LAN scan,
│   │                 # notifications, window management, macOS computer-use, etc.
│   ├── theme/        # App theming
│   ├── types/        # AssistantMode {general, coding, plan}, WorkspaceMode
│   │                 # {chat, coding, routines}, AppThemePreference,
│   │                 # GoalCompletionPolicy
│   ├── utils/        # ContentParser, Logger, Debouncer, markdown sanitizer
│   └── widgets/      # Cross-feature UI
├── features/         # Each: data → domain → presentation
│   ├── chat/         # Main chat loop, tools, plan mode, persistence, memory
│   ├── dashboard/    # Usage and activity overview
│   ├── maintenance/  # Idle maintenance runs and their settings
│   ├── onboarding/   # First-run setup
│   ├── personal_eval/ # Personal evaluation cases and records
│   ├── remote_coding/ # Paired-device remote coding (server/client)
│   ├── routines/     # Scheduled/recurring agent runs
│   ├── settings/     # App configuration and import/export
│   ├── terminal/     # Caverno CLI process host
│   └── watch/        # Apple Watch companion integration
└── main.dart         # Bootstraps the drift database, legacy Hive boxes,
                      # SharedPreferences, EasyLocalization, desktop window
                      # restoration, Riverpod overrides
```

There is no `lib/shared/`. Cross-feature UI lives in `lib/core/widgets/`;
anything used by a single feature stays inside that feature.

## Key Architectural Decisions

- **State management**: Riverpod with `Notifier` / `NotifierProvider` pattern (not BLoC)
- **Immutable entities**: All domain entities use Freezed (`Message`, `Conversation`, `AppSettings`, `ChatState`, `McpToolEntity`, `Routine`, `SessionMemory`, plan artifacts, etc.)
- **Storage**: the drift/SQLite `AppDatabase` (`features/chat/data/datasources/app_database.dart`) is the primary store — tables `Conversations`, `ChatMemoryEntries`, `Embeddings`, `ModelUsageDaily`, `Rag2StoreMeta`, `Rag2Generations`. Hive boxes (`conversations`, `chat_memory`, `skills`) survive only as legacy sources behind per-box migration flags in `features/chat/application/persistence/caverno_legacy_hive_boxes.dart`. SharedPreferences holds settings, routines, coding projects and window state; `flutter_secure_storage` holds SSH credentials
- **API client**: `openai_dart` package wrapping OpenAI-compatible endpoints
- **Navigation**: no router package. `ChatPage` is the entry surface, with modal sheets (settings, plan editor) and the conversation drawer; settings, routines, remote coding, dashboard, terminal, onboarding, maintenance and personal_eval each push their own pages via `Navigator` / `MaterialPageRoute`
- **i18n**: `easy_localization` with `assets/translations/{en,ja}.json`, locale resolved via `AppLanguageResolver` from settings + system locale

## Data Flow

1. `main.dart` initializes EasyLocalization, SharedPreferences, the drift database (`openAppDatabase`), the legacy Hive boxes (`CavernoLegacyHiveBoxes.open`) and, on desktop, `WindowManagerService`. All shared resources are passed via Riverpod overrides.
2. `ChatNotifier` (Notifier, split across `chat_notifier*.dart` files) orchestrates the chat loop:
   - Builds system prompt via `SystemPromptBuilder` (temporal context, session memory, tool names, assistant mode)
   - Sends to LLM via `ChatRemoteDataSource` (streaming or non-streaming)
   - If tools enabled: runs a tool-calling loop (capped iterations), re-sends results as user-role messages for the final streaming answer
   - On completion: persists via `ConversationsNotifier`, extracts session memory via a secondary LLM call (`SessionMemoryService`), may emit plan/workflow artifacts
3. `SettingsNotifier` persists settings to SharedPreferences; changes reactively update `ChatNotifier` and others via `ref.listen`
4. `RoutinesNotifier` + `RoutineSchedulerController` run routines on schedule using `RoutineExecutionService`, which reuses the chat datasource and a `RoutineToolRunner` constrained by `RoutineToolPolicy`

## Tool Calling Flow

Tool calling logic lives in `ChatNotifier` and its handler part-files in `features/chat/presentation/providers/` — `chat_notifier_{approval,ble,browser,computer_use,git,local_file,serial,ssh,subagent,turn_rollback}_handlers.dart`. It has a specific pattern:

- First request sends only search-class tools (prevents the LLM from calling `web_url_read` before having a URL)
- Tool results are collected, then re-sent as a **user role** message (not tool role) for the final streaming answer — some LLMs handle tool-role messages poorly
- Content-embedded `<tool_call>` / `<tool_use>` tags in streaming responses are detected by `ContentParser` and executed inline
- High-risk tools (shell, filesystem write, computer-use, SSH) require user approval, cached via `ToolApprovalCache`

## Built-in Tool Catalog

`lib/features/chat/data/datasources/` exposes built-in tools alongside MCP:

- **Web / search**: SearXNG-backed `web_search` and web URL fetching, wired through `mcp_tool_service` / `mcp_tool_search_catalog`; `built_in_browser_tool_handler` for page interaction
- **MCP**: `mcp_client` (HTTP/SSE) and `mcp_stdio_client` (stdio) via `mcp_tool_service`
- **Local code/files**: `filesystem_tools`, `git_tools`, `local_shell_tools`,
  `file_rollback_*` (per-turn checkpoints), `project_*_path_fence` (path guards)
- **Code intelligence**: `lsp_*` (go-to-definition, diagnostics over JSON-RPC)
- **Scripting / processes**: `python_script_tools` (embedded interpreter, see
  `docs/embedded_python.md`), `background_process_tools` (long-running jobs that
  outlive a turn)
- **Retrieval**: `embeddings_client`, `rag2_*` (drift-backed), `conversation_search_tool`
- **Delegation**: `subagent_tool_runtime_adapter`, `participant_tool_runtime_adapter`
- **Network**: `network_tools`, `lan_scan_tools`, `wifi_tools`
- **Devices**: `ble_tools` (Bluetooth LE), `serial_port_tools`
- **Authoring**: `skill_catalog_data_source`, `create_routine_tool_runtime_adapter`
- **OS**: `os_log_tools`, macOS computer-use (`core/services/macos_computer_use_*.dart`)

## Session Memory System

`SessionMemoryService` + `ChatMemoryRepository` manage persistent user memory:

- On the first message of a new session, injects past context into the system prompt
- After each assistant response, extracts memory via a secondary LLM call (`MemoryExtractionDraftService` + `MemoryExtractionJsonParser`)
- Tracks user profile (persona, preferences, constraints) with TTL and confidence scores
- Falls back to rule-based extraction if LLM JSON extraction fails

## Content Parsing

`ContentParser` handles special tags in LLM responses:

- `<think>` blocks (reasoning / chain-of-thought)
- `<tool_call>` / `<tool_use>` blocks (inline tool invocations)
- Supports incomplete/streaming tags gracefully (renders partial state without flicker)

## Plan / Workflow System

For multi-step tasks, `ChatNotifier` can produce a structured plan instead of a free-form answer. Relevant services live in `features/chat/domain/services/conversation_plan_*.dart` and `conversation_execution_*.dart`:

- `ConversationPlanningPromptService` — builds the planning request
- `ConversationPlanDocumentBuilder` / `ConversationPlanProjectionService` — assemble the plan artifact and its UI projection
- `ConversationPlanExecutionCoordinator` + `ConversationPlanExecutionGuardrails` — drive step execution with safety checks
- `ConversationPlanDiffService` / `ConversationPlanHash` — track plan revisions
- `ConversationExecutionRecoveryService` / `ConversationExecutionSummaryService` — handle interrupted runs and post-run summaries

Plan UI: `features/chat/presentation/widgets/plan/` (review sheet, editor sheet, approval sheet, timeline card, revision history).

## Voice Mode

`VoiceModeNotifier` orchestrates push-to-talk and continuous voice chat:

- **STT**: `stt_service` (on-device `speech_to_text`) or `whisper_service` (remote Whisper-compatible endpoint)
- **TTS**: `tts_service` (platform TTS via `flutter_tts`) or `voicevox_service` + `voicevox_audio_player` (remote VOICEVOX)
- `voice_recorder` captures audio for Whisper; `voice_mode_overlay` is the active-call UI

## Routines

`features/routines/` lets the user save recurring prompts/agent runs:

- `Routine` entity with schedule (cron-like) and tool policy
- `RoutineSchedulerController` (behind `routineSchedulerProvider`) wakes routines using `flutter_local_notifications`; `RoutineExecutionService` runs them against the chat datasource
- `RoutineToolPolicy` restricts which tools a routine can call
- `RoutineCompletionActionService` dispatches the result (e.g., notification, Google Chat via `google_chat_delivery_service`)

## Desktop Window Management

On macOS / Windows / Linux, `WindowManagerService` + `WindowSettingsService` restore previous window size and position from SharedPreferences at startup.

## Entity Changes

When modifying Freezed entity classes (`*.dart` files in any `domain/entities/`), always regenerate:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated files (`*.freezed.dart`, `*.g.dart`) are committed to the repo.

## Default Configuration

Read the values from their source rather than from here — the copy that used to
live in this section had drifted.

- API defaults (base URL, model, API key, temperature, max tokens):
  `lib/core/constants/api_constants.dart`
- Settings defaults: `lib/features/settings/domain/entities/app_settings.dart`
- Pinned Flutter version: `.fvmrc`
- Assistant modes: `lib/core/types/assistant_mode.dart` (`general` is the default)
