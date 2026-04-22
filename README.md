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
- **Tool Calling (MCP)** — Model Context Protocol integration for dynamic tool execution (web search, datetime, etc.)
- **Session Memory** — Automatically extracts and persists user preferences, persona, and context across sessions
- **Voice I/O** — Speech-to-text input and text-to-speech output with configurable speech rate
- **Multi-conversation** — Create, switch, and manage multiple conversations with persistent storage
- **Content Parsing** — Renders `<think>` reasoning blocks and inline `<tool_call>` / `<tool_use>` tags
- **Image Input** — Attach images to messages (base64 with MIME type)
- **Assistant Modes** — Switch between `general` and `coding` modes with specialized system prompts
- **Settings Import/Export** — Share configuration via JSON file or QR code with validation
- **Localization** — English and Japanese UI (easy_localization)
- **Local Notifications** — Background response notifications

## Requirements

- Flutter 3.41.6 (managed via [FVM](https://fvm.app/))
- An OpenAI-compatible LLM server (defaults to `http://localhost:1234/v1`)

## Getting Started

```bash
# Install dependencies
flutter pub get

# Generate Freezed / JSON serializable code
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

## Configuration

All settings are configurable in-app via the Settings page:

| Setting | Default |
|---------|---------|
| Base URL | `http://localhost:1234/v1` |
| Model | `mlx-community/GLM-4.7-Flash-4bit` |
| API Key | `no-key` |
| Temperature | 0.7 |
| Max Tokens | 4096 |

Optional integrations:
- **MCP Server** — Configure endpoint for tool calling (SearXNG web search, etc.)
- **TTS / STT** — Enable voice features and auto-read in settings

## Local Server Setup (Ubuntu)

To fully utilize the continuous voice mode and local LLM capabilities, you can set up the following services natively or via Docker on your Ubuntu machine.

### 1. LLM Server (llama.cpp)

The application connects to any OpenAI-compatible REST endpoint. For running the **Qwen3.5 35b a3b** model, `llama.cpp` is recommended.

```bash
# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make -j  # Use LLAMA_CUDA=1 for NVIDIA GPUs

# Download your model format (replace with actual URL)
wget -O qwen3.5-35b-a3b.gguf <MODEL_DOWNLOAD_URL>

# Start the OpenAI-compatible server on the default Caverno port (1234)
./llama-server -m qwen3.5-35b-a3b.gguf --host 0.0.0.0 --port 1234 -c 4096
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

The repository includes deterministic Plan mode scenarios and an optional live LLM smoke suite.

Additional implementation notes for the ping CLI stabilization work live in
[`docs/plan_mode_ping_cli_stabilization_playbook.md`](docs/plan_mode_ping_cli_stabilization_playbook.md).

### Deterministic suite

```bash
flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact
```

Results are written to `build/integration_test_reports/plan_mode_suite_report.json`, `build/integration_test_reports/plan_mode_suite_report.md`, and `build/integration_test_reports/plan_mode_suite_report.xml`.

### Live LLM suite

Use the helper script to run the same Plan mode flow against a real OpenAI-compatible endpoint.

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

Current live scenario names:

- `live_host_health_scaffold`
- `live_cli_entrypoint_decision`
- `live_clarify_recovery`

Current live tags:

- `smoke`
- `decision`
- `recovery`

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

Live results are written to `build/integration_test_reports/plan_mode_live_suite_report.json`, `build/integration_test_reports/plan_mode_live_suite_report.md`, and `build/integration_test_reports/plan_mode_live_suite_report.xml`.

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
| Local Storage | hive / hive_flutter (conversations), shared_preferences (settings) |
| Voice (built-in) | speech_to_text, flutter_tts |
| Voice (server) | record, audioplayers (Whisper STT + VOICEVOX TTS) |
| Settings Transfer | file_picker, qr_flutter, mobile_scanner |
| Localization | easy_localization |
| Notifications | flutter_local_notifications |
| UI | flutter_markdown, url_launcher, image_picker |
