# Caverno v1.3.44

> Release date: 2026-09-23

## Summary

A release focused on composer shortcuts and tool-loop robustness: composer shortcuts are now drafted from the visible answer and read git state from the thread's worktree, and tool-loop iterations spent waiting on a running job are refunded. The chat layer also received a series of refactors extracting the composer model selector, thread message list, and scroll anchoring into their own files.

## Changes

### Fixes

- **Composer shortcut git state** — Composer shortcuts now read git state from the thread's worktree instead of the project root, and git state is refreshed before drafting, so shortcuts reflect the branch and worktree the conversation is actually running in. (`lib/features/chat/`)
- **Composer shortcut drafting** — Composer shortcuts are now drafted from the visible answer rather than the raw model output. (`lib/features/chat/`)
- **Tool-loop iteration refund** — Tool-loop iterations spent waiting on a running background job are refunded, so long-running jobs no longer burn the iteration budget while the agent waits. (`lib/features/chat/`)
- **Empty diff no longer unlocks uninspected commits** — An empty diff no longer unlocks an uninspected commit, keeping the commit inspection gate intact. (`lib/features/chat/`)

### Refactors

- **Composer model selector** — The composer model selector was split out of the composer into its own file. (`lib/features/chat/`)
- **Thread message list view** — The thread message list view was extracted from `ChatPage` into its own file. (`lib/features/chat/`)
- **ThreadScrollAnchor** — `ThreadScrollAnchor` was moved to its own file. (`lib/features/chat/`)
- **Scroll-to-latest visibility** — Thread scroll-to-latest visibility logic was extracted from the thread view. (`lib/features/chat/`)
- **Request tool declarations** — Request tool declarations were extracted from the remote datasource. (`lib/features/chat/`)
- **Release approval conflict result** — The production release approval conflict result was extracted into its own file. (`lib/features/chat/`)
- **Release argument canonicalization** — Production release argument canonicalization was extracted into its own file. (`lib/features/chat/`)

### Testing

- **update_goal blocker call** — Added a test covering a turn that ends with `update_goal` carrying a blocker call. (`test/`)
- **Remote-coding suppression tests** — Remote-coding page suppression tests now receive a `SharedPreferences` instance. (`test/`)

## Version

- `1.3.44+58`