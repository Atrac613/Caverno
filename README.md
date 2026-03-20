# Caverno

A Flutter chat client for OpenAI-compatible LLM APIs with tool calling, session memory, and voice I/O.

## Features

- **OpenAI-compatible API** — Works with any OpenAI-compatible endpoint (local or remote)
- **Tool Calling (MCP)** — Model Context Protocol integration for dynamic tool execution (web search, datetime, etc.)
- **Session Memory** — Automatically extracts and persists user preferences, persona, and context across sessions
- **Voice I/O** — Speech-to-text input and text-to-speech output with configurable speech rate
- **Multi-conversation** — Create, switch, and manage multiple conversations with persistent storage
- **Content Parsing** — Renders `<think>` reasoning blocks and inline `<tool_call>` / `<tool_use>` tags
- **Image Input** — Attach images to messages (base64 with MIME type)
- **Assistant Modes** — Switch between `general` and `coding` modes with specialized system prompts

## Requirements

- Flutter 3.41.2 (managed via [FVM](https://fvm.app/))
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

## App Store Screenshots

Generate dark-mode screenshots for App Store submission using integration tests.

```bash
# Boot an iOS simulator
xcrun simctl boot "iPhone 17 Pro Max"

# Run the screenshot tests
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d <device-id>
```

Screenshots are saved to `screenshots/` and automatically resized to 1284×2778 (App Store 6.7" display).

| # | Screenshot | Content |
|---|-----------|---------|
| 1 | `1_chat_conversation` | Chat with markdown, code blocks, and thinking |
| 2 | `2_tool_calling` | Web search tool calls with results |
| 3 | `3_thinking_block` | Chain-of-thought reasoning block |
| 4 | `4_conversation_drawer` | Conversation history sidebar |
| 5 | `5_settings_page` | Settings page |

## Architecture

Clean Architecture with feature-based modules and Riverpod state management.

```
lib/
├── core/              # Constants, services (TTS/STT), utils
├── features/
│   ├── chat/          # Chat feature (data → domain → presentation)
│   │   ├── data/      # Remote datasource (OpenAI), MCP client, repositories
│   │   ├── domain/    # Entities (Freezed), services (prompt builder, memory)
│   │   └── presentation/  # ChatPage, ChatNotifier, widgets
│   └── settings/      # Settings feature (data → domain → presentation)
└── shared/            # Shared widgets
```

### Tech Stack

| Category | Library |
|----------|---------|
| State Management | flutter_riverpod |
| API Client | openai_dart |
| Immutable Models | freezed + json_serializable |
| Local Storage | hive (conversations), shared_preferences (settings) |
| Voice | speech_to_text, flutter_tts |
| UI | flutter_markdown, url_launcher, image_picker |
