# Portable Memory And Model Continuity

Date: 2026-09-06  
Status: Investigation complete; implementation proposed  
Code baseline: `012ee320b`

## Goal And Recommendation

Make accumulated user context durable and transferable across installations and
model changes. Start with a bounded memory archive and restore contract, then
measure behavioral continuity. This does not promise identical personality,
reasoning, or permanent availability of an inference runtime.

This document records the investigation requested in chat. It changes no runtime
behavior and introduces no automatic memory collection or external transmission.

## External Inspiration And Evidence Limits

- [Original post, September 4, 2026](https://x.com/kuwagata_no_isi/status/2095853531714802039)
  argues that an agent can remain the user's own across model changes and service
  shutdowns.
- [Author's follow-up](https://x.com/kuwagata_no_isi/status/2095921666576826769)
  describes a central memory system, approximately 25 GB of agent data, and six
  months to a year of development. These are author claims, not measurements
  independently reproduced here.
- The post and follow-up text were read in a browser on September 5. Video and
  detailed design images were not inspected because media access prompted login.
  No conclusions about the author's algorithms, implementation quality, or
  cross-model fidelity follow from this investigation.

The useful design principle is to keep durable state under user control and
separate from inference providers. Archive size alone does not establish memory
quality, recoverability, or behavioral continuity.

## Verified Caverno Baseline

| Component | Observed behavior | Implication |
|-----------|-------------------|-------------|
| [ChatMemoryRepository](../lib/features/chat/data/repositories/chat_memory_repository.dart) | Persists profile, session summaries, memories, review queue, suppression rules, and suppression hit count through a key/value abstraction; mutations refresh state under a coordinator. | Reuse the existing ownership boundary; do not add another memory store. |
| [SessionMemoryService](../lib/features/chat/domain/services/session_memory_service.dart) | Builds model-independent text context. Historical task context requires an explicit history reference; at most three summaries and six scored memories are injected. | Preserve bounded, selective retrieval when adding portability. |
| [MemoryEntry](../lib/features/chat/domain/entities/session_memory.dart) | Carries confidence, importance, expiry, update time, and source conversation ID. | Provenance exists, but this entry has no source-message reference, assertion-origin field, or supersession history. |
| [SettingsFileService](../lib/features/settings/data/settings_file_service.dart) | Imports and exports AppSettings, including an encrypted settings path. | Settings transfer is not a chat-memory archive; reuse applicable file/validation patterns rather than claim portability already exists. |
| [SaveSkillToolHandler](../lib/features/chat/domain/services/save_skill_tool_handler.dart) | Saves skills through an approval port, with existing-skill review support. | Conversation-to-skill authoring already exists; it is not a new feature proposal. |

The repository's `loadMemories` drops expired entries, and its normal upsert
paths deduplicate and cap lists. A faithful archive cannot blindly compose those
operations and claim lossless restore. Also, serialized mutations do not by
themselves establish rollback across multiple failed writes.

The [existing roadmap](local_llm_agent_roadmap.md) already covers:

- F4: drift-backed conversation and memory storage, marked done.
- SKILL1/SKILL2: approved skill authoring and chat-driven lifecycle, marked done.
- SKILL3: evidence-backed idle-time skill mining, marked later.

The earlier conversational suggestion to turn experience into reusable procedures
therefore maps to SKILL3, reusing SKILL1/SKILL2. It needs no duplicate milestone.
Memory portability also does not reopen the blocked RAG3 retrieval candidates.

## Proposed Work

### MEM1: Memory Archive And Restore

Status: `later`; first slice within this proposed track.

User-visible outcome: export memory locally and restore it into a clean Caverno
installation with explicit review. The first implementation slice should deliver
the codec and repository contract before adding the settings UI.

Scope and constraints:

- Define a versioned envelope for all six repository state categories, with
  explicit timestamp, expiry, size-limit, and validation rules.
- Preserve pending review status and suppression rules. Import must not approve
  pending memories, confer tool permissions, or silently enable memory features.
- Freeze whether the archive contains expired records before implementation.
  Keep original expiry times; restore must never make expired entries active.
- Keep AppSettings, credentials, skills, attachments, and full conversation
  transcripts outside v1. Explain that this is a memory archive, not a complete
  agent backup. Source conversation IDs may remain unresolved on a clean install.
- Keep the user's current memory enablement settings unchanged. The archive
  preserves suppression rules, not every application-level privacy setting.
- Begin with an empty-destination restore. Reject nonempty destinations before
  writing; merging and replacement are separate future decisions.
- Validate the entire envelope before mutation. Reuse cross-process memory
  ownership and implement a storage-supported all-or-nothing commit or recovery
  protocol; do not assume `runAtomicMutation` supplies transaction rollback.
- Keep file export user initiated, avoid logging archive contents, and decide
  encryption and file protection before exposing the archive in the UI.

Acceptance criteria:

1. A synthetic fixture containing all six categories survives export, clean-store
   restore, and re-export with semantic equality under the declared expiry policy.
2. At a fixed clock and identical input/conversation ID, prompt context before
   and after restore is equal; pending and suppressed content remains excluded
   according to existing behavior.
3. Invalid versions, malformed fields, oversized input, nonempty destinations,
   cancellation, and injected storage failure leave existing state unchanged.
4. Concurrent GUI/CLI mutations cannot produce a mixed snapshot or partial
   restore. Include ownership contention and failure recovery evidence.
5. The later UI slice reports what is included, missing source conversations,
   expiry handling, and restoration outcome without exposing contents in logs.

Reference tests:

- `test/features/chat/data/repositories/chat_memory_repository_test.dart`
- `test/features/chat/domain/services/session_memory_service_test.dart`
- `test/features/settings/data/settings_file_service_test.dart`

Use `tool/codex_verify.sh --test <new focused test file>` for each implementation
slice and `tool/codex_verify.sh` before closing MEM1. New fixture data must be
synthetic; no personal session logs belong in the repository.

### MEM2: Cross-Model Continuity Evaluation

Status: `later`; depends on the MEM1 state contract.

Use frozen synthetic memory snapshots and prompts with explicit expected facts,
preferences, constraints, corrected facts, and expected abstentions. Compare at
least two model configurations with and without memory. Keep deterministic
context-equivalence checks separate from variable model responses.

Record model identity, sampler settings, prompt, memory version, repetitions,
per-case results, latency, and token usage. Report constraint adherence, correct
recall, unsupported recall, and abstention separately. Define pass thresholds
before evaluating candidates; do not use matching prose or model self-report as
proof of identity. A live evaluation requires configured endpoints and separate
execution authorization; this documentation task runs none.

### MEM3: Evidence And Correction History

Status: `later`; additive follow-up, not a prerequisite for MEM1 v1.

Extend memory provenance with source-message references, user assertion versus
model inference, and supersession links. Older entries must remain readable with
unknown origin rather than invented evidence. A correction should stop the
superseded assertion from being retrieved as current while preserving reviewable
history. Deleted or missing source messages must have an explicit unresolved
state. Update archive schema compatibility when these fields are introduced.

Acceptance requires legacy decoding, correction/retraction retrieval cases,
unresolved-source behavior, and archive round-trip coverage. Preserve suppression
and approval boundaries; remembered text must not become authorization.

## Verification And Handoff

This was a source and roadmap inspection, not a runtime benchmark. No Flutter
tests or live-model calls were run for this documentation-only change.

Searches covered memory repository/service/entities, settings transfer,
`save_skill`, and F4/SKILL roadmap entries. Documentation checks cover whitespace,
relative Markdown file links, milestone uniqueness, and the complete diff.

Next action when this track is selected: freeze MEM1's envelope and expiry policy,
then implement the codec and clean-store restore with failure-injection tests.
The proposal does not change priority of current roadmap work.
