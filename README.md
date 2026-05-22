<p align="center">
  <img src="assets/icons/AppIcon_1024.png" width="128" alt="Caverno">
</p>
<h1 align="center">Caverno</h1>
<p align="center">
  A Flutter chat client for OpenAI-compatible LLM APIs with tool calling, session memory, and voice I/O.
</p>

<p align="center">
  <a href="https://apps.apple.com/us/app/caverno/id6760192392">
    <img src="assets/badges/app_store.svg" height="50" alt="Download on the App Store">
  </a>
  &nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.noguwo.apps.caverno">
    <img src="assets/badges/google_play.svg" height="50" alt="Get it on Google Play">
  </a>
</p>

## Features

- **OpenAI-compatible API** — Works with any OpenAI-compatible endpoint (local or remote)
- **Tool Calling (MCP + built-in tools)** — HTTP and stdio MCP servers plus
  local tools for web search, memory, network diagnostics, files, Git, SSH,
  Wi-Fi, BLE, and macOS Computer Use
- **Session Memory** — Automatically extracts and persists user preferences, persona, and context across sessions
- **Plan Mode** — Creates reviewable workflow plans, decisions, saved tasks, and validation evidence before implementation
- **Routines** — Schedule recurring prompts with optional tool use, approved Markdown plans, run history, and Google Chat delivery
- **Voice I/O** — Speech-to-text input and text-to-speech output with configurable speech rate
- **Multi-conversation** — Create, switch, and manage multiple conversations with persistent storage
- **Content Parsing** — Renders `<think>` reasoning blocks and inline `<tool_call>` / `<tool_use>` tags
- **Image Input** — Attach images to messages (base64 with MIME type)
- **Assistant Modes** — Switch between `general`, `coding`, and `plan` modes with specialized system prompts
- **Settings Import/Export** — Share configuration via JSON file or QR code with validation
- **Localization** — English and Japanese UI (easy_localization)
- **Local Notifications** — Background response notifications

## Roadmap

The active milestone roadmap is maintained in
[`docs/roadmap.md`](docs/roadmap.md). Plan Mode milestones use `PM<number>`,
while macOS Computer Use keeps the existing `M<number>` milestone series.

## Requirements

- Flutter 3.44.0 (managed via [FVM](https://fvm.app/))
- An OpenAI-compatible LLM server (defaults to `http://localhost:1234/v1`)

## Getting Started

```bash
# Select the repository Flutter version
fvm use 3.44.0

# Install dependencies
fvm flutter pub get

# Generate Freezed / JSON serializable code
fvm dart run build_runner build --delete-conflicting-outputs

# Run the app
fvm flutter run
```

## Development Workflow

Use the Codex task template for focused implementation, debugging, refactor, and
review work:

- [`docs/codex_task_template.md`](docs/codex_task_template.md)
- [`.github/ISSUE_TEMPLATE/codex_task.md`](.github/ISSUE_TEMPLATE/codex_task.md)

For local verification, prefer the shared entrypoint:

```bash
tool/codex_verify.sh
```

For focused tests:

```bash
tool/codex_verify.sh --test test/core/utils/content_parser_test.dart
```

For coverage-sensitive work:

```bash
tool/codex_verify.sh --coverage
```

The coverage summary excludes generated `*.freezed.dart` and `*.g.dart` files
from the line-rate rollup. Coverage output is written under `coverage/`, which
is intentionally ignored by git.

Large-file refactor guidance lives in
[`docs/large_file_refactor_plan.md`](docs/large_file_refactor_plan.md). Use it
before splitting `ChatNotifier`, `ChatPage`, MCP tool services, or large
Computer Use settings/debug surfaces.

## Configuration

All settings are configurable in-app via the Settings page:

| Setting | Default |
|---------|---------|
| Base URL | `http://localhost:1234/v1` |
| Model | `mlx-community/GLM-4.7-Flash-4bit` |
| API Key | `no-key` |
| Temperature | 0.7 |
| Max Tokens | 4096 |
| MCP Enabled | `true` |
| Default MCP Server | `http://localhost:8081` |
| Whisper URL | `http://localhost:8080` |
| VOICEVOX URL | `http://localhost:50021` |
| Language | `system` |
| Assistant Mode | `general` |

Optional integrations:
- **MCP Servers** — Configure trusted HTTP or desktop stdio servers for external
  tools
- **Built-in Tools** — Enable or disable categories for datetime, memory,
  network, coding, Git, SSH, BLE, Wi-Fi, LAN scan, system logs, and Computer Use
- **TTS / STT** — Enable voice features and auto-read in settings
- **Routines** — Configure scheduled prompt runs, workspace access, tool use,
  and Google Chat completion delivery

## Local Server Setup (Ubuntu)

To fully utilize the continuous voice mode and local LLM capabilities, you can set up the following services natively or via Docker on your Ubuntu machine.

### 1. LLM Server (llama.cpp)

The application connects to any OpenAI-compatible REST endpoint. `llama.cpp`
is one supported option for local GGUF models.

```bash
# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make -j  # Use LLAMA_CUDA=1 for NVIDIA GPUs

# Download your model format (replace with actual URL)
wget -O model.gguf <MODEL_DOWNLOAD_URL>

# Start the OpenAI-compatible server on the default Caverno port (1234)
./llama-server -m model.gguf --host 0.0.0.0 --port 1234 -c 4096
```

### 2. STT Server (whisper.cpp)

The continuous voice mode requires a local Whisper server exposing an OpenAI-compatible `/v1/audio/transcriptions` endpoint.

```bash
# Clone the repository
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp

# Download a multilingual Whisper model (e.g., base, small, or large-v3-turbo)
# Note: DO NOT use models ending in '.en' (like base.en) as they are English-only.
# The standard models (base, small) fully support Japanese.
bash ./models/download-ggml-model.sh base

# Build the project
cmake -B build
cmake --build build -j --config Release

# Start the server on port 8080
./build/bin/whisper-server -m models/ggml-base.bin --host 0.0.0.0 --port 8080
```

### 3. TTS Server (VOICEVOX)

For natural-sounding Japanese text-to-speech, download and run the pre-built Linux NVIDIA binaries (e.g., v0.25.1).

```bash
# Install p7zip if you haven't already
sudo apt-get update
sudo apt-get install p7zip-full

# Download the split 7z archives
wget https://github.com/VOICEVOX/voicevox_engine/releases/download/0.25.1/voicevox_engine-linux-nvidia-0.25.1.7z.001
wget https://github.com/VOICEVOX/voicevox_engine/releases/download/0.25.1/voicevox_engine-linux-nvidia-0.25.1.7z.002

# Extract the engine (7z automatically finds the .002 part)
7z x voicevox_engine-linux-nvidia-0.25.1.7z.001

# Run the server (bind to 0.0.0.0 for LAN access)
cd linux-nvidia
./run --host 0.0.0.0
```

## Store Screenshots

Generate dark-mode screenshots for App Store / Google Play submission using integration tests.

```bash
# iPhone (6.7" — 1284×2778)
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d <iphone-device-id>

# iPad (13" — 2048×2732)
SCREENSHOT_DEVICE=ipad flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d <ipad-device-id>

# Android Phone (20:9 — 1080×2400)
SCREENSHOT_DEVICE=android_phone flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d <android-device-id>

# Android Tablet (10:16 — 1600×2560)
SCREENSHOT_DEVICE=android_tablet flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d <android-tablet-id>
```

Screenshots are saved to device-specific directories and automatically resized to store dimensions:

| Device | Output Directory |
|--------|-----------------|
| iPhone | `screenshots/apple/ios/` |
| iPad | `screenshots/apple/ipad/` |
| Android Phone | `screenshots/android/phone/` |
| Android Tablet | `screenshots/android/tablet/` |

| # | Screenshot | Content |
|---|-----------|---------|
| 1 | `1_chat_conversation` | Chat with markdown, code blocks, and thinking |
| 2 | `2_tool_calling` | Web search tool calls with results |
| 3 | `3_thinking_block` | Chain-of-thought reasoning block |
| 4 | `4_conversation_drawer` | Conversation history sidebar |
| 5 | `5_settings_page` | Settings page |
| 6 | `6_voice_mode` | Voice input interface |
| 7 | `7_image_attachments` | Image attachment in conversation |

## Plan Mode Integration Tests

The repository includes deterministic Plan mode scenarios, a PM5 live gate, an
MVP handoff, a release readiness checklist, and a release candidate gate.

For release candidate sign-off, start with
[`docs/plan_mode_release_candidate_gate.md`](docs/plan_mode_release_candidate_gate.md).
For release readiness classification, use
[`docs/plan_mode_release_readiness_checklist.md`](docs/plan_mode_release_readiness_checklist.md).
For MVP context, use
[`docs/plan_mode_mvp_handoff.md`](docs/plan_mode_mvp_handoff.md). Additional
scenario coverage and promotion rules live in
[`docs/plan_mode_scenario_coverage.md`](docs/plan_mode_scenario_coverage.md).
Model and endpoint compatibility notes live in
[`docs/plan_mode_model_endpoint_compatibility.md`](docs/plan_mode_model_endpoint_compatibility.md).
The user-facing Plan Mode release package lives in
[`docs/plan_mode_release_package_2026-05-13.md`](docs/plan_mode_release_package_2026-05-13.md).
The current final release candidate decision lives in
[`docs/plan_mode_release_candidate_final_signoff_2026-05-13.md`](docs/plan_mode_release_candidate_final_signoff_2026-05-13.md).
For issue reports, copy the redacted Plan Mode support snapshot from Settings >
General and attach the latest relevant report path.
Post-release guardrails, canary cadence, and hotfix rules live in
[`docs/plan_mode_post_release_guardrails_2026-05-13.md`](docs/plan_mode_post_release_guardrails_2026-05-13.md).
Additional implementation notes for the ping CLI stabilization work live in
[`docs/plan_mode_ping_cli_stabilization_playbook.md`](docs/plan_mode_ping_cli_stabilization_playbook.md).

### MVP verification path

Use this shortest path when checking Plan Mode readiness. The release checklist
defines how these results map to pass, warning, blocker, and environment-blocked
decisions.

```bash
CAVERNO_PLAN_MODE_TAGS=smoke \
fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact

fvm flutter analyze

CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 \
tool/run_plan_mode_pm5_live_gate.sh
```

The PM5 live gate runs the live smoke suite and the ping CLI live canary. Use
`CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE=1` only after a fresh live smoke pass when
you need a faster ping-only rediscovery loop. On failure, the gate prints the
latest live suite and ping canary artifact paths plus the investigation order.

### Deterministic suite

```bash
fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact
```

Results are written to `build/integration_test_reports/plan_mode_suite_macos_report.json`, `build/integration_test_reports/plan_mode_suite_macos_report.md`, and `build/integration_test_reports/plan_mode_suite_macos_report.xml`.

### Live LLM suite

Use the PM5 gate for MVP and release confidence:

```bash
tool/run_plan_mode_pm5_live_gate.sh
```

Use the lower-level helper script when you need to run a specific live scenario
against a real OpenAI-compatible endpoint.

```bash
tool/run_plan_mode_live_test.sh
```

Set these required environment variables in your shell before running it:

| Variable | Required | Notes |
|----------|----------|-------|
| `CAVERNO_LLM_BASE_URL` | Yes | OpenAI-compatible base URL for the live test server |
| `CAVERNO_LLM_API_KEY` | Yes | API key or any token your server expects |
| `CAVERNO_LLM_MODEL` | Yes | Model ID used for the live Plan mode suite |
| `CAVERNO_PLAN_MODE_DEVICE` | No | Defaults to `macos` |
| `CAVERNO_PLAN_MODE_REPORTER` | No | Defaults to `compact` |
| `CAVERNO_PLAN_MODE_TAGS` | No | Optional tag filter |
| `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS` | No | Defaults to `0` |
| `CAVERNO_PLAN_MODE_PREFLIGHT` | No | Defaults to `1`; set `0` to skip the endpoint `/models` check |
| `CAVERNO_PLAN_MODE_PREFLIGHT_TIMEOUT_SECONDS` | No | Defaults to `5` |

The PM5 gate also supports these optional variables:

| Variable | Required | Notes |
|----------|----------|-------|
| `CAVERNO_PLAN_MODE_PM5_SMOKE_SCENARIOS` | No | Optional scenario filter for the live smoke phase |
| `CAVERNO_PLAN_MODE_PM5_SMOKE_TAGS` | No | Defaults to `smoke` |
| `CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT` | No | Defaults to `1` |
| `CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE` | No | Set to `1` to skip the smoke phase |
| `CAVERNO_PLAN_MODE_PM5_SKIP_PING_CANARY` | No | Set to `1` to skip the ping CLI canary phase |

Example:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_plan_mode_live_test.sh
```

Optional filters:

- `CAVERNO_PLAN_MODE_SCENARIOS=live_host_health_scaffold`
- `CAVERNO_PLAN_MODE_TAGS=smoke` to run scenarios matching any listed tag
- `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1` to fail the run when warnings are recorded

When `CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1` is enabled, the suite fails only on unexpected warnings. Scenario-specific expected warnings are still captured in the reports as allowed warnings.

Before launching Flutter, the live helper checks `${CAVERNO_LLM_BASE_URL}/models`
so an offline endpoint fails quickly instead of waiting for each scenario's
planning timeout. Set `CAVERNO_PLAN_MODE_PREFLIGHT=0` only when your
OpenAI-compatible endpoint intentionally does not expose `/models`.

Current live scenario names:

- `live_host_health_scaffold`
- `live_cli_entrypoint_decision`
- `live_readme_first_canary`
- `live_ping_cli_completion`
- `live_clarify_recovery`

Current live tags:

- `artifact`
- `automation`
- `canary`
- `completion`
- `convergence`
- `decision`
- `live`
- `recovery`
- `smoke`

The `live_readme_first_canary` scenario is intentionally tagged as a canary
rather than smoke, so `CAVERNO_PLAN_MODE_TAGS=smoke` keeps the default live
smoke surface focused on the core approval and recovery flows.
Use `docs/plan_mode_scenario_coverage.md` before promoting any canary into
the default smoke surface.

Examples:

```bash
# Run all live smoke scenarios
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_TAGS=smoke \
tool/run_plan_mode_live_test.sh

# Run only the clarify/recovery live scenario
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_SCENARIOS=live_clarify_recovery \
tool/run_plan_mode_live_test.sh
```

Live results are written to device-scoped files such as
`build/integration_test_reports/plan_mode_live_suite_macos_report.json`,
`build/integration_test_reports/plan_mode_live_suite_macos_report.md`, and
`build/integration_test_reports/plan_mode_live_suite_macos_report.xml`.

The live JSON report includes `outcomeSummary`, `warningSummary`, and
`executionPathSummary` for quick triage. Scenario reports also include
`approvalPath` and `fallbackPath`; `liveHarnessApprovalFallback` means the app
produced a reviewable plan, but the live test harness approved and started it
directly instead of depending on a foreground-sensitive approval sheet tap.
Treat `unexpectedWarnings` as fix targets. `allowedWarnings` are still reported,
but they have a documented recovery path or scenario-level allow pattern.

## Routine Live LLM Canary

Routine live LLM validation is documented in
[`docs/routine_live_llm_canary.md`](docs/routine_live_llm_canary.md).

Use it when changing routine execution, routine tool-call parsing, workspace
file tools, or Google Chat notification handling. It is an explicit canary, not
part of the normal deterministic unit test suite.

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_routine_live_llm_canary.sh
```

## Architecture

Clean Architecture with feature-based modules and Riverpod state management.

```
lib/
├── core/              # Constants, services (TTS/STT), types, utils
├── features/
│   ├── chat/          # Chat feature (data → domain → presentation)
│   │   ├── data/      # Remote datasource (OpenAI), MCP client, repositories
│   │   ├── domain/    # Entities (Freezed), services (prompt builder, memory)
│   │   └── presentation/  # ChatPage, ChatNotifier, widgets
│   ├── routines/      # Scheduled prompt execution, routine plans, run history
│   │   ├── data/      # SharedPreferences repository, execution service
│   │   ├── domain/    # Routine entity (Freezed), schedule/tool policy services
│   │   └── presentation/  # Routine pages, providers, editor widgets
│   └── settings/      # Settings feature (data → domain → presentation)
│       ├── data/      # Repository, file service, QR service
│       ├── domain/    # AppSettings entity (Freezed)
│       └── presentation/  # Pages, providers, widgets (QR dialogs)
└── shared/            # Shared widgets
```

### Tech Stack

| Category | Library |
|----------|---------|
| State Management | flutter_riverpod |
| API Client | openai_dart, http |
| Immutable Models | freezed + json_serializable |
| Local Storage | hive / hive_flutter (conversations and memory), shared_preferences (settings, routines, coding projects, window settings) |
| Voice (built-in) | speech_to_text, flutter_tts |
| Voice (server) | record, audioplayers (Whisper STT + VOICEVOX TTS) |
| Settings Transfer | file_picker, qr_flutter, mobile_scanner |
| Localization | easy_localization |
| Notifications | flutter_local_notifications |
| Desktop Windowing | window_manager |
| Built-in Tools | dart_ping, multicast_dns, dartssh2, bluetooth_low_energy, wifi_scan, network_info_plus |
| UI | flutter_markdown_plus, url_launcher, image_picker |
