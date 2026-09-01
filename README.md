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

### Chat

- **OpenAI-compatible API** — Works with any OpenAI-compatible endpoint (local or remote)
- **Session Memory** — Automatically extracts and persists user preferences, persona, and context across sessions
- **History Search** — Full-text search over past conversations, ranked by embedding similarity when an `/v1/embeddings` endpoint is available
- **Mid-turn Interruption** — Send with Cmd/Ctrl+Enter to redirect the turn that is already running instead of queueing behind it; the turn keeps its tool results and partial output
- **Multi-thread** — Run turns in several conversations at once; each thread keeps its own state, queue, and approvals
- **Voice I/O** — Speech-to-text input and text-to-speech output with configurable speech rate
- **Content Parsing** — Renders `<think>` reasoning blocks and inline `<tool_call>` / `<tool_use>` tags
- **Image Input** — Attach images to messages (base64 with MIME type)
- **Assistant Modes** — Switch between `general`, `coding`, and `plan` modes with specialized system prompts
- **Slash Commands** — `/new`, `/coding`, `/plan`, `/goal`, `/agent`, `/skill`, `/review`, `/fix`, `/test`, and more

### Tools

- **Tool Calling (MCP + built-in tools)** — HTTP and stdio MCP servers plus
  built-in tools grouped by category: web search, memory, files and scripts,
  Git, SSH, network, LAN scan, Wi-Fi, BLE, serial port, system logs, tasks,
  skills, built-in browser, and macOS Computer Use
- **Approvals** — High-risk tools are intended to require explicit approval;
  repeated identical decisions can be cached per turn. The current security
  audit records open execution/classification gaps that must be closed before
  this is treated as a complete boundary.
- **Embedded Python** — Runs `run_python_script` on a bundled interpreter, on desktop and mobile alike
- **Built-in Browser** — An in-app webview the model can navigate and read
- **Embedded Terminal** — A desktop-only terminal panel in the coding workspace, running a long-lived login shell that keeps going while the panel is hidden

### Coding

- **Coding Mode** — Project-associated sessions with a repo map, dependency
  grounding, and LSP-backed post-edit diagnostics; canonical filesystem
  containment is an open security-remediation item
- **Git Worktrees** — Work in an isolated worktree per thread, with `/agent` queueing tasks across several at once
- **Turn Checkpoints** — Whole-turn file snapshots with one-action revert
- **Goals** — Set a coding goal with `/goal`; the agent can continue toward it across turns under a visible token and turn budget
- **Plan Mode** — Creates reviewable workflow plans, decisions, saved tasks, and validation evidence before implementation
- **Skills** — Save a conversation's workflow as a reusable skill and load it later
- **Remote Coding** — Drive a desktop coding session from a paired phone on the
  same LAN; keep it disabled in release builds until the authenticated-transport
  roadmap is complete
- **Apple Watch Companion** — Answer a blocked turn's approval or question from
  the wrist, glance at what is running, and dictate a new instruction. Approval
  notifications carry Approve/Deny even when the watch app is closed. See
  [`docs/apple_watch_companion.md`](docs/apple_watch_companion.md)
- **AGENTS.md Support** — In coding and plan modes, the project root `AGENTS.md` (and the higher-priority `AGENTS.override.md`) is injected into the system prompt, following the [OpenAI Codex AGENTS.md spec](https://developers.openai.com/codex/guides/agents-md)

### Models and operations

- **Per-role Model Routing** — Send secondary work (memory extraction, subagents, approval auto-review) to a smaller model, optionally on another machine
- **LAN Inference Mesh** — Discover and register OpenAI-compatible endpoints on the local network and route roles across them with fallback
- **Local Stack Manager** — Manage model lifecycle and hardware fit for llama.cpp, LM Studio, and Ollama from `Advanced > Local Stack`
- **Routines** — Schedule recurring prompts with optional tool use, approved Markdown plans, run history, and Google Chat delivery
- **Settings Import/Export** — Share configuration via JSON file or QR code;
  executable hooks and MCP servers remain quarantined until exact review
- **Localization** — English and Japanese UI (easy_localization)
- **Local Notifications** — Background response notifications

## Roadmap

The active milestone roadmap is maintained in
[`docs/roadmap.md`](docs/roadmap.md). Plan Mode milestones use `PM<number>` and
macOS Computer Use keeps the existing `M<number>` series; local-LLM agent work
(`LL<number>`), foundation refactors (`F<number>`), and the platform vision
tracks are detailed in
[`docs/local_llm_agent_roadmap.md`](docs/local_llm_agent_roadmap.md).

## Security

The current point-in-time security assessment, stable finding IDs, release
decision, and remediation map are recorded in
[`docs/security_audit_2026-08-14.md`](docs/security_audit_2026-08-14.md).
`SEC1`, `SEC2`, `SEC4`, and `RC1` in the roadmap own the open release blockers.

## Requirements

- Flutter 3.44.8 (managed via [FVM](https://fvm.app/))
- An OpenAI-compatible LLM server (defaults to `http://localhost:1234/v1`)
- Python 3 on the host to repackage the embedded Python worker (contributors only)

## Getting Started

```bash
# Select the repository Flutter version
fvm use 3.44.8

# Install dependencies
fvm flutter pub get

# Stage the embedded Python interpreter (once per machine, after pub get)
tool/prepare_serious_python.sh

# Generate Freezed / JSON serializable code
fvm dart run build_runner build --delete-conflicting-outputs

# Run the app
fvm flutter run
```

`tool/prepare_serious_python.sh` stages the interpreter for iOS and macOS, which
`pod install` also does on its own. Android reads the staged site directory from
the environment at build time, so export it in the shell you build from:

```bash
export SERIOUS_PYTHON_SITE_PACKAGES="$(pwd)/build/serious_python_site"
```

### macOS builds

Every worktree that builds the macOS app produces its own `Caverno.app` claiming
the same bundle ID, which makes LaunchServices route XPC requests to whichever
copy registered last and breaks the Computer Use helper. macOS builds therefore
go through a wrapper that only proceeds in the worktree designated canonical by
a gitignored `.macos-canonical` sentinel:

```bash
touch .macos-canonical        # once, in the worktree that owns macOS builds
tool/safe-flutter run -d macos
```

Every other subcommand passes straight through, so any worktree can still run
`tool/safe-flutter analyze` and `tool/safe-flutter test`.

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
tool/codex_verify.sh --test test/core/utils/markdown_render_sanitizer_test.dart
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
Computer Use settings/debug surfaces. Oversized files are held to a CI-enforced
line budget that only ever ratchets down, so a change that grows one has to make
room by extracting something first.

### Embedded Python worker

The `run_python_script` tool runs against a packaged worker asset. After editing
anything under `lib/core/services/script_runtime/worker/` (including its vendored
`__pypackages__/`), regenerate the deterministic `assets/python/app.zip`:

```bash
python3 tool/pack_python_worker.py
```

The worker has a regression suite that needs only the system `python3`, and the
native path is covered by an integration test that runs the real interpreter on
a device or simulator:

```bash
python3 test/python/worker_test.py
fvm flutter test integration_test/python_runtime_test.dart -d <device-id>
```

Mobile supports pure-Python wheels only. To vendor another package, install it
into the worker's `__pypackages__/` with `--no-deps --no-compile` and repackage.

## Configuration

All settings are configurable in-app via the Settings page:

| Setting | Default |
|---------|---------|
| Base URL | `http://localhost:1234/v1` |
| Model | `qwen3.6-27b-mtp-vision` |
| API Key | `no-key` |
| Temperature | 0.7 |
| Max Tokens | 4096 |
| MCP Enabled | `true` |
| Default MCP Server | `http://localhost:8081` |
| Whisper URL | `http://localhost:8080` |
| VOICEVOX URL | `http://localhost:50021` |
| Language | `system` |
| Assistant Mode | `general` |
| Read AGENTS.md in coding mode | `true` |

Optional integrations:
- **MCP Servers** — Configure trusted HTTP or desktop stdio servers for external
  tools
- **Built-in Tools** — Enable or disable categories for date & time, memory,
  web search, code & scripts, Git, SSH, network, LAN scan, Wi-Fi, Bluetooth LE,
  serial port, system, tasks, interaction, skills, built-in browser, and
  Computer Use
- **TTS / STT** — Enable voice features and auto-read in settings
- **Semantic Search** — Point Caverno at an `/v1/embeddings` endpoint to rank
  history search by meaning; it degrades to lexical full-text search without one
- **LLM Endpoints** — Register additional OpenAI-compatible endpoints and route
  individual roles to them, with fallback to the primary
- **Routines** — Configure scheduled prompt runs, workspace access, tool use,
  and Google Chat completion delivery

### Project Instructions (AGENTS.md)

When the assistant mode is `coding` or `plan` and the toggle **Tools → Coding
Agent Approvals → Read AGENTS.md in coding mode** is enabled (default), Caverno
loads `AGENTS.md` from the active coding project's root directory and injects it
into the system prompt. This lets you keep project-specific rules — build
commands, code style, approval workflows — alongside the code so any compatible
agent (Caverno, Codex, etc.) can apply them.

Behavior:

- **Discovery** — Only the project root is scanned: `<projectRoot>/AGENTS.md`
  and `<projectRoot>/AGENTS.override.md`. Nested subdirectory files and the
  global `~/.codex/AGENTS.md` are not loaded in this version.
- **Precedence** — If `AGENTS.override.md` exists, it takes priority over
  `AGENTS.md`. Empty files are treated as absent.
- **Size cap** — 32 KiB, matching the Codex spec. Larger files are truncated
  and marked in the prompt.
- **Caching** — Contents are cached in memory and re-read when the file's mtime
  changes, so editing `AGENTS.md` takes effect on the next message without an
  app restart.
- **Modes** — Not injected in `general` mode. Disable the toggle if you would
  rather keep `AGENTS.md` purely for other tools.

Example `AGENTS.md`:

```markdown
# Project Rules

- Use `pnpm` instead of `npm`.
- Run `pnpm test` before claiming a change is complete.
- All new files must pass `pnpm lint` with no warnings.
```

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

The PM5 live gate runs the live smoke suite, the ping CLI live canary, and the
chat background-process live canary. Use `CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE=1`
only after a fresh live smoke pass when you need a faster ping-only rediscovery
loop. On failure, the gate prints the latest live suite, ping canary, and
background-process canary artifact paths plus the investigation order.

### Multi-thread live canary

Two coding threads on two projects draft a plan at the same time against a real
model, checking that neither thread prompts for the other's project, logs under
the other's session, resolves a tool path into the other's root, or loses its
plan. The canary asserts the overlap itself first, so a run that happened to go
sequentially fails loudly instead of passing for the wrong reason.

```bash
CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
fvm flutter test tool/canaries/multi_thread_plan_live_canary_test.dart
```

On macOS, wrap this command with `tool/with_live_llm_loopback.sh --` when the
endpoint is an HTTP LAN address: Local Network Privacy stops the test binary
from reaching it directly. Do not create a fixed-port relay. Two concurrent
threads issue two concurrent requests, so a single-slot server serialises them —
allow for a slow run rather than assuming a hang. See the
[`Live LLM Canary Agent Runbook`](docs/live_llm_canary_agent_runbook.md) for the
complete command shape and evidence checks.

### Deterministic suite

```bash
fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact
```

Results are written to `build/integration_test_reports/plan_mode_suite_macos_report.json`, `build/integration_test_reports/plan_mode_suite_macos_report.md`, and `build/integration_test_reports/plan_mode_suite_macos_report.xml`.

### Live LLM suite

Codex, Claude, and developers should start with the
[`Live LLM Canary Agent Runbook`](docs/live_llm_canary_agent_runbook.md). It
defines endpoint preflight, when to use the managed macOS loopback wrapper, the
smallest bounded production streaming check, and the evidence required before
claiming success.

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
| `CAVERNO_PLAN_MODE_PM5_BACKGROUND_PROCESS_REPEAT_COUNT` | No | Defaults to `1` |
| `CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE` | No | Set to `1` to skip the smoke phase |
| `CAVERNO_PLAN_MODE_PM5_SKIP_PING_CANARY` | No | Set to `1` to skip the ping CLI canary phase |
| `CAVERNO_PLAN_MODE_PM5_SKIP_BACKGROUND_PROCESS_CANARY` | No | Set to `1` to skip the chat background-process canary phase |

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
Use `docs/live_llm_canary_coverage.md` when comparing chat, coding, and
routine coverage for a model switch or Live LLM regression investigation.
Long-running background process MVP task tracking lives in
[`docs/long_running_process_mvp_tasks.md`](docs/long_running_process_mvp_tasks.md).

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

## Chat Live LLM Canary

Chat live LLM validation covers plain chat streaming, memory extraction JSON,
and content-embedded tool-call execution.

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_chat_live_llm_canary.sh
```

The oversized tool-result recovery path is covered separately:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_tool_result_budget_live_canary.sh
```

The background-process lifecycle path is covered with a dedicated canary that
verifies long-running command start/monitor/ completion safety.

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_chat_background_process_live_canary.sh
```

For stability checks, run three consecutive times by setting:

```bash
CAVERNO_CHAT_BACKGROUND_PROCESS_LIVE_REPEAT_COUNT=3 \
tool/run_chat_background_process_live_canary.sh
```

Both scripts write `canary_summary.json`, `canary_summary.md`, and the captured
Flutter JSON log under `build/integration_test_reports/` so model-switch
handoffs can compare chat recovery signals across runs.

Mid-turn interruption has its own canary. It runs an interrupt arm against a
queued control arm and reads its verdict from the sandbox filesystem rather than
the model's prose, because both failure modes — the interruption was silently
requeued, and it arrived and was ignored — leave the same file on disk.

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_turn_steering_live_canary.sh
```

It asserts a probabilistic model behavior, so a single run is a sample rather
than a measurement; set `CAVERNO_TURN_STEERING_REPEAT_COUNT` and read the rate
printed at the end.

## Routine Live LLM Canary

Routine live LLM validation is documented in
[`docs/routine_live_llm_canary.md`](docs/routine_live_llm_canary.md).
Cross-surface Live LLM coverage for chat, coding, and routines is documented in
[`docs/live_llm_canary_coverage.md`](docs/live_llm_canary_coverage.md).

Use it when changing routine execution, routine tool-call parsing, workspace
file tools, or Google Chat notification handling. It is an explicit canary, not
part of the normal deterministic unit test suite.

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
tool/run_routine_live_llm_canary.sh
```

The routine wrapper writes the same `canary_summary.json`, `canary_summary.md`,
and captured Flutter JSON log artifact shape as the chat live canaries.

## Architecture

Clean Architecture with feature-based modules and Riverpod state management.

```
lib/
├── core/              # Constants, services (TTS/STT, Python script runtime,
│                      # SSH/BLE/Wi-Fi, Computer Use, windowing), types, utils
├── features/
│   ├── chat/          # Chat feature (data → domain → presentation)
│   │   ├── data/      # Remote datasource (OpenAI), MCP client, repositories
│   │   ├── domain/    # Entities (Freezed), services (prompt builder, memory)
│   │   └── presentation/  # ChatPage, ChatNotifier, widgets
│   ├── routines/      # Scheduled prompt execution, routine plans, run history
│   │   ├── data/      # SharedPreferences repository, execution service
│   │   ├── domain/    # Routine entity (Freezed), schedule/tool policy services
│   │   └── presentation/  # Routine pages, providers, editor widgets
│   ├── remote_coding/ # Paired-device remote coding (server/client)
│   │   ├── data/      # Pairing registry, protocol, security, repository
│   │   ├── domain/    # Remote coding models
│   │   └── presentation/  # Remote coding pages, client/server notifiers
│   ├── settings/      # Settings feature (data → domain → presentation)
│   │   ├── data/      # Repository, file service, QR service
│   │   ├── domain/    # AppSettings entity (Freezed)
│   │   └── presentation/  # Pages, providers, widgets (QR dialogs)
│   └── watch/         # Apple Watch companion bridge (no Flutter UI)
│       ├── domain/    # WatchSnapshot / WatchCommand wire models, mapper
│       └── presentation/  # WatchSessionNotifier (projection + commands)
└── main.dart          # Entry point: storage, SharedPreferences, localization, Riverpod
```

Three internal packages hold the contracts the app is decomposed against:

```
packages/
├── caverno_tool_contracts/     # Tool result envelope and outcome types
├── caverno_execution_runtime/  # Typed execution runtime shared with the CLI work
└── caverno_content_protocol/   # Streaming content parsing (think / tool tags)
```

### Storage

Conversations and chat memory are stored in a drift (SQLite) database, which
also backs full-text history search and the embedding vector store. Hive remains
in the app for the one-time migration path: the database is opened and migrated
at startup, and any failure there falls back to the original Hive-backed
repositories rather than blocking launch. Settings, routines, coding projects,
and window geometry live in SharedPreferences; SSH credentials live in
`flutter_secure_storage`.

### Tech Stack

| Category | Library |
|----------|---------|
| State Management | flutter_riverpod |
| API Client | openai_dart, http |
| Immutable Models | freezed + json_serializable |
| Local Storage | drift (conversations, chat memory, FTS5 history search, embeddings), hive / hive_flutter (migration source), shared_preferences (settings, routines, coding projects, window settings), flutter_secure_storage (SSH credentials) |
| Voice (built-in) | speech_to_text, flutter_tts |
| Voice (server) | record, audioplayers (Whisper STT + VOICEVOX TTS) |
| Settings Transfer | file_picker, qr_flutter, mobile_scanner |
| Localization | easy_localization |
| Notifications | flutter_local_notifications |
| Desktop Windowing | window_manager |
| Embedded Python | serious_python |
| Terminal | xterm, flutter_pty |
| Built-in Browser | flutter_inappwebview |
| Built-in Tools | dart_ping, multicast_dns, dartssh2, bluetooth_low_energy, wifi_scan, network_info_plus, flutter_libserialport |
| UI | flutter_markdown_plus, flutter_math_fork, url_launcher, image_picker, desktop_drop |
| Documents | syncfusion_flutter_pdf (PDF text extraction) |

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md).

### Third-party licenses

Most dependencies are permissively licensed. One is not:

- **syncfusion_flutter_pdf**, used to extract the text layer from attached
  PDFs, ships under the Syncfusion Essential Studio license. Syncfusion offers
  a Community License and a commercial license; eligibility for the Community
  License is defined by Syncfusion's current terms (not only revenue and
  headcount), so check
  [those terms](https://www.syncfusion.com/products/communitylicense) rather
  than this summary. Caverno's own MIT license does not extend to it, so
  building this project from source means holding a Syncfusion license of
  your own.

PDF support is confined to `lib/core/services/pdf_text_extraction_service.dart`
precisely so this dependency can be swapped without touching its callers.
