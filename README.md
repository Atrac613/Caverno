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
