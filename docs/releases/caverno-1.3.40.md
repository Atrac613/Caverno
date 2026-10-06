# Caverno v1.3.40

> Release date: 2026-09-22

## Summary

A loaded skill now reaches the turn that actually acts on it, Remote Coding accepts attachments, and the coding thread gains a scroll-to-latest button. The rest of the release is a set of chat-guard fixes that stop three guards from firing on their own scaffolding: the ask-answer cache, the release gate, and the file-save guard.

## Changes

### Features

- **Skill carry** — A skill's content no longer dies with the turn that loaded it. `LoadedSkillMemory` records which skills a thread has loaded, keyed by conversation rather than by turn, because the load and the work it governs are deliberately in different turns. The carried skill is matched by id or by name, and the wiring is registered as a decomposition collaborator with its own size budget. (`lib/features/chat/`)
- **Remote Coding attachments** — Remote Coding sessions now accept attachments alongside the prompt. (`lib/features/remote_coding/`)
- **Mobile remote coding composer** — The mobile remote coding composer now aligns with the desktop layout, with the model selector and input surface reworked for the mobile surface. (`lib/features/remote_coding/`)
- **Coding companion panel on mobile** — A coding companion panel now shows on the mobile remote coding surface, mirroring the desktop companion view. (`lib/features/remote_coding/`)
- **Coding thread scroll-to-latest button** — A button jumps the coding thread back to the latest message after it has scrolled up. (`lib/features/chat/presentation/`)

### Fixes

- **Plan Mode review on mobile coding** — The Plan Mode review now renders on the mobile coding surface. (`lib/features/chat/`)
- **Mobile coding project order** — The mobile coding project list now stays in sync with the desktop order. (`lib/features/remote_coding/`)
- **Scroll after rollback confirmation** — The coding thread scrolls to the latest message after a rollback is confirmed. (`lib/features/chat/presentation/`)
- **Ask-answer reuse only while the option is still offered** — `ask_user_question` matched a cached answer on question text alone, so an ask whose options had changed behind identical wording replayed a stale answer. Reuse now requires the option the user picked to still be on offer, fed from the selections the policy already held. An entry recording no selection (a cancellation, free text, a question with no options) still matches on the question, so a model looping on one decision does not re-prompt. The decision moves to `AskUserQuestionReusePolicy`. (`lib/features/chat/`)
- **Release gate no longer re-arms after a release ran** — A release that succeeded mid-turn left the guard demanding an approval no answer could satisfy, because granting the release spent its token and the next attempt minted a fresh one. The gate now answers a release it already dispatched with what happened and mints no new token; dispatch is read from `ToolResultInfo.outcome` rather than remembered, and an absent outcome means unknown, never succeeded. (`lib/features/chat/`)
- **Teardown progress instead of a frozen quit** — Confirming the quit used to pop the dialog and then spend up to five seconds closing persistence with the ordinary UI on screen and nothing happening. The dialog now stays up and swaps its body for a progress state while the teardown runs, and refuses every dismissal route once it starts. (`lib/features/settings/`)
- **Executor template no longer arms the file-save guard** — An executor-driven turn's latest user message is a template the coordinator writes around the saved task, and it carries the bare substring `save` eight times, so the guard stood open on every executor-driven coding turn. The guard now resolves its view of the request through the saved task's own authored fields (title, notes, validation command, target files) rather than the template. (`lib/features/chat/`)

### Testing

- **Watch for a skill reaching the turn that acts on it** — A firing-evidence row is registered now that the skill carry is wired on main, keyed on the prompt rather than on a transform because the carry is context the request now holds. It reports "not yet observed" against zero eligible logs; the next release is the test. (`tool/check_fix_firings.py`)

## Version

- `1.3.40+54`

## Notes

The skill carry is verified by the analyzer and the full test suite, but its live behavior — a thread that loads a skill in one turn and acts on it in a later one — is still unverified and needs a real thread to settle. The release workflow is exactly that shape, so this release is the first live sample.
