# Caverno v1.3.46

> Release date: 2026-09-24

## Summary

A release centered on finer control of model reasoning: a running turn can now be interrupted with an already-queued message, reasoning effort is probed, logged, and selectable (including a new `xhigh` level), and the live LLM diagnostic can pick thinking mode and effort. The Flutter SDK is pinned to 3.47.5, and the KC1/KC2 knowledge-census work continues with new measurement arms and fixture broadening.

## Changes

### Features

- **Interrupt a running turn with a queued message** — A message already in the queue can now interrupt the turn that is currently running. (`lib/features/chat/`)
- **Reasoning effort on the wire** — Thinking mode and effort are logged as they go on the wire, and the request policy no longer carries the Qwen3.8 prefix. (`lib/features/chat/`)
- **Reasoning effort probing** — Settings now probe which reasoning efforts an endpoint accepts, and a new `xhigh` effort level is available. (`lib/features/settings/`)
- **Live LLM diagnostic picks thinking mode and effort** — The diagnostic can now select thinking mode and effort for its probes. (`lib/features/settings/`)
- **Internal grep, legible SEC4.4g prompts, and shell write observation** — New internal grep tooling, more legible SEC4.4g prompts, and observation of shell writes. (`lib/features/chat/`)
- **KC2 census arms** — KC2 dependencies are selected by import breadth, measured in the KC1 census, and a versions-only production arm was added; the KC2 environment and dependency block is rendered and carried in coding prompts, including what installed versions changed. (`lib/features/chat/`, `lib/features/tool/`)
- **KC1 world-fact scoring** — KC1 class 1 world facts are scored against the pub.dev registry, with the report arm column widened for `worldFactGrounded`. (`lib/features/tool/`)

### Fixes

- **Template effort on effort retry** — The template effort is dropped when the effort retry drops it. (`lib/features/chat/`)
- **Broadened KC1 fixtures** — KC1 fixtures for classes 2 and 4 are calibrated before measuring. (`lib/features/tool/`)
- **KC2 manifest source** — The manifest source is recorded in KC2 inventory entries. (`lib/features/chat/`)

### Refactors

- **Live LLM diagnostic service slices** — The live LLM vision probes, diagnostic report evidence, sampler-calibration trials, and response scoring are extracted into the diagnostic service. (`lib/features/settings/`)
- **Shared pub lockfile resolver** — LL10's pub lockfile resolver is moved into a shared file. (`lib/features/chat/`)

### Testing

- **Large-file budgets** — The large files the F5 inventory was missing are budgeted. (`test/`)
- **Internal grep fixture** — The internal grep test points at its squashed commit. (`test/`)

### Documentation

- **KC1/KC2 census records** — KC1 is closed with real-answer corpus classification, and the KC2 slices (environment block, usable-context cap, digest coverage, production re-runs) are recorded, including the withdrawn causal readings and the KC3 re-scope as the coverage complement to KC2's delta window.
- **F5 diagnostic-service slices** — The second and third F5 slices are recorded, and the F5 large-file ranking is refreshed.
- **LL33 closure** — LL33 is closed with live file-save triage evidence.

### Build

- **Flutter 3.47.5** — The Flutter SDK is pinned to 3.47.5 via FVM. (`.fvmrc`)

## Version

- `1.3.46+60`

## Notes

The Flutter SDK pin to 3.47.5 is the first release built on the new SDK; watch for any platform-behavior changes in the first TestFlight / Sparkle cycle.