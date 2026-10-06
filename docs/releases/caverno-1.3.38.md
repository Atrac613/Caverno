# Caverno v1.3.38

> Release date: 2026-09-20

## Summary

Per-endpoint opt-in for `chat_template_kwargs` so thinking suppression no longer depends on the model name, plus a fix for composer shortcuts returning an empty list.

## Changes

### Features

- **Per-endpoint opt-in for `chat_template_kwargs`** — Add a `chatTemplateKwargsEnabled` flag to `LlmEndpoint` (following `videoInputEnabled`). Off by default; when enabled, structured utility roles suppress thinking regardless of the model family. Resolved by base URL so secondary routers are covered.

### Fixes

- **Composer shortcuts returning an empty list** — 29 of 45 drafts in the local app log came back `{"shortcuts": []}`. The prompt's git/verify conditions gated every chip kind at once; the prompt now states that those conditions never restrict `follow_up`, and that the answer to a question the assistant just asked is the first chip. Also lift the deploy/release/publish ban in the prompt and the destructive-prompt filter — a chip sends a prompt, and running what it asks for is still gated by tool approval.
- **Opt-in seeding for pre-endpoint installs** — `_migrateChatTemplateKwargsOptIn` walks `json['llmEndpoints']`, but an install predating the endpoint list has no such key. The frozen predicate is now shared between the migration and `withNormalizedLlmEndpoints` so an endpoint carries the same history however it came to exist.

### Refactors

- **Thinking suppression without the model name** — Suppression now follows from the role and the endpoint's opt-in alone, rather than `startsWith('qwen3.8')`. A family this policy has never heard of gets byte-identical overrides to the one it is named after. `isQwen38Model` survives for the reasoning-effort mapping only. `migrateLegacyJson` turns the flag on for exactly the endpoints whose model name used to earn it, and never overwrites a choice already made.

## Version

- `1.3.38+51`

## Notes

The `chat_template_kwargs` opt-in is not demonstrated end to end on a non-Qwen3.8 endpoint; the path is covered by unit tests and a local llama.cpp replay.
