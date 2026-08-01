# ChatNotifier Decomposition Task Index

This index tracks the implementation units approved by
`docs/chat_notifier_decomposition_codex_task.md`. A catalog row is not one
implementation slice: each numbered sub-slice inside that catalog must keep its
own review and commit boundary.

## Gate Slices

| Slice | Task specification | Status |
|---|---|---|
| 1 | `docs/chat_notifier_decomposition_codex_task.md` | Complete |
| 2a1 | `docs/chat_notifier_decomposition_slice_2a1_codex_task.md` | Complete |
| 2a2 | `docs/chat_notifier_decomposition_slice_2a2_codex_task.md` | Complete |
| 2a3 | `docs/chat_notifier_decomposition_slice_2a3_codex_task.md` | Complete |
| 2b1 | `docs/chat_notifier_decomposition_slice_2b1_codex_task.md` | Complete |
| 2b2 | `docs/chat_notifier_decomposition_slice_2b2_codex_task.md` | Complete |
| 2b3 | `docs/chat_notifier_decomposition_slice_2b3_codex_task.md` | Complete |
| 2b4 | `docs/chat_notifier_decomposition_slice_2b4_codex_task.md` | Complete |
| 2b5 | `docs/chat_notifier_decomposition_slice_2b5_codex_task.md` | Complete |
| 2b6 | `docs/chat_notifier_decomposition_slice_2b6_codex_task.md` | Complete |
| 2b7 | `docs/chat_notifier_decomposition_slice_2b7_codex_task.md` | Complete |

The gate closed on 2026-07-28. The corrected four-scenario canary passed at
`http://192.168.100.241:1234/v1` with the endpoint reporting
`qwen3.6-27b-vision` as loaded. Exact completed-turn counts were
`{alpha: 2, beta: 2}` for plan drafting, `{alpha: 1, beta: 1}` for concurrent
coding, `{alpha: 2}` for queued work, and `{alpha: 1, beta: 0}` for handback.
Every expected generation emitted one `turn_exit`, all IDs were non-empty and
unique per conversation, and every scenario ended with zero busy conversations.

## Pre-Implementation Audit

The 2026-07-28 P1b completion tree measures 9,376 lines in
`chat_notifier.dart`, 42 declared parts containing 13,522 lines, and a
22,898-line same-library aggregate. The manifest intentionally retains 43
historical part records. Snapshot adoption lowered the turn-scope baseline from
132 to 114 ambient reads and from 118 to 101 turn-reachable reads, with 18
reviewed removals and no additions.

At that checkpoint, no Workstream 4-8 slice was complete. The audit also found
18 corrective areas covering ownership, atomic completion, shared policy, and
size. Splitting P3 into P3a and P3b makes those areas 19 separately reviewable
implementation slices.

P1a passed 30 focused tests with 100% line coverage for the owner type,
snapshot registry, and active-response registry. P1b then passed the
53-test owner-adoption matrix, the 314-test ordinary ChatNotifier suite, the
111-test common gate, analysis, and the canonical audit. The full coverage run
reached 4,256 passing root tests and retained only the two pre-existing M33
release-packaging failures. Its exact `qwen3.6-27b-vision` canary passed every
scenario with one exit per expected generation and zero busy owners.

P2 implementation now keeps completed/content/command evidence, content-tool
state, hidden assistant evidence, runtime lifecycle publication, project-root
dedupe, verification generations, final saves, and cancellation persistence
with an exact `ChatTurnOwner`. The 79-test direct helper matrix, 77-test
detached-turn suite, 55-test caller handoff, 313-test ordinary ChatNotifier
suite, 124-test common gate, analysis, and canonical audit passed. The audit is
86 ambient and 76 turn-reachable reads, down 28/25 from P1b with no additions.
The P2 completion tree was 9,306 primary lines, 13,582 declared-part lines, and
22,888 same-library lines with matching ceilings.

The fresh final-tree verifier ran generation, package analysis and tests, and
root analysis, then reached 4,354 passing root tests. Only the two
pre-existing M33 static packaging checks failed; focused reruns tied both to
direct-S3 predicates that lag the CloudFront migration and confirmed that no
P2, P4, or P5a file is an input. The exact-model canary passed all four
scenarios, so P2 completed its gate for P3a. A separate audit still records
cancelled plan-proposal late writes as a required follow-up before dependent
plan-flow extraction.

P4 implementation centralizes exact file-mutation tool classification,
notifier-specific result success, result and argument path extraction, and
result-first path precedence in `FileMutationEvidencePolicy`. Its 12-test
direct suite covered 33/33 executable lines. The 97-test adjacent-policy suite,
313-test ordinary ChatNotifier suite, 125-test common gate, analysis, and audit
passed. The P4 tree was 9,258 primary lines, 13,580 declared-part lines, and
22,838 same-library lines with matching ceilings. Lifecycle readiness was
restored with `qwen3.6-27b-vision` `loaded` and the 35B model `unloaded`. The
fresh verifier and exact-model canary above complete P4 and unblock WS5-4.

P5a keys approval and denial reuse by exact `ChatTurnOwner` while retaining the
exact tool name, normalized arguments, and unchanged optional state fingerprint
in the inner key. Dispatch passes a revocable owner-bound cache capability
through every cache-capable handler;
terminalization clears only that owner, and global reset/disposal clears all.
The 208-line cache passed 12 direct tests at 60/60 executable lines. The
78-test detached suite passed the A-approve, B-fresh-prompt, A-reuse, B-deny
poison sequence, and the 313-test ordinary suite plus 126-test common gate
passed. The P5a completion tree is 9,257 primary lines, 13,566 declared-part
lines, and 22,823 same-library lines with matching ceilings. Audit exposure
remains 86 ambient and 76 turn-reachable reads. The fresh exact-model canary
passed every expected generation once with zero busy owners, so P5a is
complete.

P5b binds command, process, file, rollback, Git, SSH, Python, skill, and routine
approval requests to an exact `ChatTurnOwner`. A typed authoritative registry
validates owner and ID together, removes completers before resolution, and
settles owner-local or global cancellation safely. Terminal and Remote Coding
adapters resolve through that registry, while each handler revalidates the
owner after asynchronous approval and immediately before side effects. The
10-test ownership suite and 12-test auto-review suite covered all 53 registry
lines and all 33 shared `resolveGate` lines, including an approve-then-clear
tool-loop poison case with no permission persistence or execution. The
395-test ordinary suites, 131-test common gate, final 153-test focused and
structural gate, analysis, and canonical audit passed.

The P5b tree is 9,191 primary lines, 13,586 declared-part lines, and 22,777
same-library lines with matching ceilings. Audit exposure remains 78 ambient
and 68 turn-reachable reads; the reviewed lifecycle helpers bring the graph to
784 methods and 751 reachable methods. The full verifier reached 4,395 passing
root tests and retained only the two known unrelated M33 CloudFront-migration
mismatches. The exact `qwen3.6-27b-vision` canary passed all four scenarios in
2 minutes 40 seconds with every expected generation emitted once and zero busy
owners, so P5b is complete.

P5c binds Computer Use, browser, BLE, serial, and participant approval requests
to an exact `ChatTurnOwner` and generalizes the P5b registry into one
authoritative typed approval registry. Public resolvers validate owner, ID, and
request type together. Terminalization cancels only the finishing owner,
global clearing settles every request, and visible pending state is no longer
an authority. The current Remote Coding wire protocol remains unchanged and
does not transport these approval families.

Every P5c handler revalidates the owner after asynchronous approval or
auto-review and immediately before a side effect. Browser and Computer Use
start no follow-up work after expiry; BLE and serial compensate an in-flight
stale success with disconnect and close; participant execution remains
cache-free. A 112-line independent coordinator serializes same-device BLE
attempts and preserves pre-existing and successor connections.

The eleven-test device ownership suite, 17-test terminal suite, 45-test focused
approval/UI gate, 395-test ordinary ChatNotifier suites, 132-test common gate,
analysis, and canonical audit passed. The completion tree is 9,191 primary
lines, 13,578 declared-part lines, and 22,769 same-library lines. The
historical manifest and generated outputs are unchanged; the coordinator is
budgeted at 112 lines. The audit reports 787 methods, 755 reachable methods, 78
ambient reads, and 68 turn-reachable reads. The fresh coverage verifier reached
4,412 passing root tests and retained only the two known unrelated M33
CloudFront-migration mismatches. The exact `qwen3.6-27b-vision` canary passed
all four scenarios in 2 minutes 53 seconds with each expected owner generation
emitting one `turn_exit` and every scenario ending with zero busy owners.

P5c unblocks WS6-11a, WS6-11b, WS6-14, WS6-16, and the WS8-9 approval
adapter. At that checkpoint WS6-1 waited only for P11; P11 is now complete.

P6 keys single-file history, active checkpoints, completed
checkpoint stacks, retry restoration, and clear operations by exact
`ChatTurnOwner`. Its conversation chronology stores exact completed owners, so
the no-argument ChatNotifier preview selects the latest completed owner for the
visible conversation without deriving a current-generation key. The preview
carries that owner plus a monotonic checkpoint token through confirmation to
prevent a newer completion, including one from the same owner, from changing
the rollback target.
Chat file mutations use a separate owner-required `executeFileTool` boundary;
ordinary ownerless execution remains available to non-chat callers but does
not create chat rollback history. Best-of-N now receives and retains its exact
owner. A provider-owned store spans settings-driven service rebuilds;
conversation deletion retires bounded state, and tombstones reject late
resurrection.

The P6 implementation changes 423 production lines across ten existing files
and leaves the notifier tree at 9,191 primary lines, 13,578 declared-part
lines, and 22,769 same-library lines. The 442-line store is newly budgeted, and
the filesystem handler shrank to 339 lines. The authored poison matrix covers
cross-conversation equal generations, same-conversation chronology,
simultaneous active checkpoints, first-entry capture, owner-local limits and
clear, immutable confirmation tokens, provider replacement, conversation
retirement, failure retry, ownerless mutations, and Best-of-N isolation. No
part/manifest transition, marker, generated output, or schema change is
present. The 133-test focused suite covered all 187 executable store lines. The
551-test adoption suite, 137-test common gate, analysis, and canonical audit
passed. The fresh verifier reached 4,433 passing root tests
with only the two known unrelated M33 failures, and the exact-model canary
passed all four scenarios in 2 minutes 27 seconds with zero busy owners. P6 is
complete and unblocks WS4-6 and WS6-4.

P12 split the 715-line command-output guardrail into a 133-line compatibility
facade, a 298-line output issue detector, and a 356-line preflight detector.
The public facade API, exported models, feedback JSON, issue ordering, cap,
and recursive-feedback behavior remain compatible. The 30 direct tests and
167-test caller suite passed, with 35/35, 107/107, and 135/135 executable lines
covered respectively. Exact budgets pass for all three files. The historical
`command-guardrails` part remains `remaining`; WS7-8 owns its adoption and
manifest transition.

P14 extracted the 21-line `HiddenAssistantEvidenceScorer` from
`ToolTerminalResponsePolicy`, which shrank from 743 to 725 lines. The exact
score precedence remains compatible for empty, hidden, visible, failed,
successful, and conflicting evidence, including the historical `incomplete`
substring behavior. The 19-test direct suite passed with 12/12 scorer lines
covered, and the exact size budget passed. No part, marker, generated output,
or manifest state changed.

P3a moves turn-exit hints, ordered transform IDs, accepted goal-completion
claims, and shadow goal outcomes into the 117-line
`TurnFinalizationStateRegistry`. Its four direct tests covered 50/50 executable
lines. The 80-test detached-owner suite includes independent transform/reset
and cross-owner goal-claim/shadow isolation cases; P3b later added exact-owner
claim consumption. The 313-test ordinary suite, five read-only guard tests,
127-test common gate, analysis, and canonical audit passed. The P3a completion
tree was 9,219 primary lines, 13,570 declared-part lines, and 22,789
same-library lines. The audit was 82 ambient and 72 turn-reachable reads.
The full verifier reached 4,361 passing root tests and retained only the two
known M33 CloudFront-migration mismatches. The exact-model canary passed four
scenarios with one exit per expected generation and zero busy owners.

P3b replaces the final flat goal-completion evidence with the 211-line
`TurnGoalCompletionEvidenceRegistry` and `TurnGoalCompletionFinalizer`.
Evidence begins, combines, reconciles, and disposes under an exact
`ChatTurnOwner`; the finalizer consumes the matching P3a claim and outcome
before persistence, freezes the visible-path goal token delta before later
detachment can overwrite it, and records against the detached owner's
conversation. Detached-at-entry turns still contribute zero. P10b has since
replaced the shared raw-usage read with request-local terminal metadata. The old
boolean continuation handoff is now a typed `initialGoalCompletionEvidence`
seed supplied only by an explicit predecessor.
Eleven direct tests covered 59/59 executable lines. The 82-test detached suite
covered failed-evidence isolation, explicit-only successor seeding, and
exact-owner accepted claims, including 11-versus-97 late-detachment
token-accounting poison;
the 313-test ordinary suite, 40 compatibility tests, 128-test common gate,
analysis, and canonical audit passed. The
completion tree is 9,213 primary lines, 13,567 declared-part lines, and 22,780
same-library lines; the test library is 33,226 lines. The audit is now 78
ambient and 68 turn-reachable reads, with four removals and no additions. The
fresh verifier reached 4,375 passing root tests and retained only the same two
known M33 CloudFront-migration mismatches. The loaded
`qwen3.6-27b-vision` canary passed all four scenarios with one exit per expected
generation and zero busy owners. P3b is complete, so WS8-7 is unblocked.

P7, P8, P9, P10a, P10b, P11, and P13 completed their focused acceptance on
2026-07-30. Background process state, SSH sessions, subagent tasks, response
metadata and timing, conversation taint, and participant stop/pause control are
now keyed by exact `ChatTurnOwner`; P10a pairs every plain content stream with
terminal metadata from that same request. The governed primary files measure
459/457 lines for background tools/monitoring, 279 for `SshService`, 210 for
`SubagentTaskNotifier`, 27 for terminal metadata, 107 for
`ResponseMetadataRegistry`, 82 for conversation taint, and 129 for participant
control. Their recorded coverage is 195/203 and 175/181, 110/115, 76/76, 2/2,
47/47, 29/29 plus 4/4 for its recorder, and 51/51 executable lines
respectively. The P10b 92-test registry/detached suite and 157-test focused
integration gate passed.

WS4-1 also completed its focused acceptance on 2026-07-30, so Workstream 4 is
now in progress. The independent 145-line `PythonAttachmentRepairPolicy`
retains the exact prompts and decision matrix while the 162-line notifier part
provides only owner-bound adaptation. Its 15 focused tests cover 48/48 policy
and 43/43 adapter executable lines, including the poison case where the visible
conversation and registered turn owner have opposite attachment state. The
manifest records `python-attachment-repair` as `partial` with the exact
collaborator path and size-budget key.

WS4-2 completed its extraction on 2026-07-30. The 209-line
`DuplicateToolResultRecovery` accepts recursively immutable current, executed,
and fallback results plus the exact owning project root. Direct tests cover
latest-match selection, frozen nested arguments, fallback ordering, and
filesystem-compatible relative-path identity. The 85-line historical part is
removed, its manifest record is `extracted`, and the current declared-part
count is 41. Post-hardening revalidation passed 13 direct tests with 85/85
executable lines covered. Flutter analysis and the exact committed tree's
159-test manifest, size, structural-boundary, and turn-scope gate also passed.

WS6-12 and WS6-13 completed focused acceptance on 2026-07-31. The 217-line
`SaveSkillToolHandler` and 490-line `CreateRoutineToolHandler` now sit behind
owner-scoped receipt adapters with exact approval, persistence, settlement,
and compensation identity. The historical skill and routine parts are removed,
both manifest records are `extracted`, and direct coverage reached 92/92 and
166/169 executable lines. The 153-test runtime suite, five ChatNotifier
integration tests, targeted analysis, and exact committed tree's 146-test
manifest, size, structural-boundary, and turn-scope gate passed.

WS6-10 completed focused acceptance on 2026-07-31. The 492-line
`PythonScriptToolHandler` receives an immutable exact-owner message snapshot
and now owns code validation, latest eligible attachment selection, staging,
approval, execution, cache settlement, and cleanup fencing. The production
adapter retires owner staging leases at terminalization and never consults the
visible conversation. The old 126-line Python handler part is removed and its
manifest record is `extracted`. Forty-two direct handler tests reached 151/158
executable lines, while the 96-test Python runtime suite, three ChatNotifier
integration tests, and targeted analysis passed.
The exact focused tree also passed the 159-test manifest, size,
structural-boundary, and regenerated turn-scope gate.

WS6-1 completed focused acceptance on 2026-07-31. The 489-line
`TurnToolApprovalCoordinator` now owns exact-owner approval reuse, deterministic
execution identity, auto-review precedence and request construction, warning
and denial compatibility, and best-effort audit recording behind four narrow
runtime ports. Thirty-two focused tests cover 163/167 executable lines
(97.60%), including cross-thread and cross-generation poison, reviewer and
audit
failures, manual escalation, and immutable input snapshots. The manifest
records `approval-handlers` as `partial`; the remaining notifier adapters stay
in place until the corresponding typed handler slices migrate.

WS6-2 completed focused acceptance on 2026-07-31. The 259-line
`LspGoToDefinitionToolHandler` receives the exact owner's immutable operation
identity and project root, while the 296-line runtime adapter fences LSP
session acquisition, collection, and conditional compensation. Twenty-six
focused tests cover 93/94 handler lines (98.94%), including every argument and
URI branch, ordered definitions, unavailable/error results, peer and successor
poison, and uncertain session settlement. The owner-bound registry entry no
longer calls the four historical local-file methods. That part falls from
1,191 to 1,041 lines, declared parts fall to 11,123 lines, and the same-library
aggregate falls to 20,035.

WS6-3 completed focused acceptance on 2026-07-31. The 434-line
`FileMutationToolHandler` receives immutable exact-owner requests and owns
write, edit, and delete validation, approval, conflict detection, effect
settlement, and rollback recording. Its runtime serializes each resolved path
through a receipt-backed filesystem boundary and compensates owner expiry
before releasing the path. Fifteen direct tests covered 105/105 executable
handler lines; the 108-test focused runtime/filesystem suite and four notifier
integration cases passed. The `local-file-handlers` manifest record is now
`partial`, and that focused tree was 9,073 primary lines, 12,964 declared-part
lines, and 22,037 same-library lines.

WS6-4 completed focused acceptance on 2026-07-31. The 225-line
`FileRollbackToolHandler` binds history, approval, execution, and cache
acknowledgements to one exact owner and immutable checkpoint token. Thirty-three
direct tests reached 85/86 executable handler lines, and the 33-test runtime,
conditional-store, and path-fence suite passed. The `local-file-handlers`
record remains `partial` with `file-rollback-tool-handler` appended.

WS4-6 completed focused acceptance on 2026-07-31. The 111-line
`FileTurnRollbackService` isolates whole-turn preview and rollback behind a
narrow checkpoint port while the notifier retains its existing public APIs.
Nine direct tests cover unavailable service behavior, immutable previews,
result propagation, exact owner/token forwarding, and cross-owner isolation.
The historical 22-line delegate part remains `partial` because moving its
public APIs into the primary file would exceed the exact primary ratchet.

WS4-3 completed focused acceptance on 2026-07-31. The 75-line
`ReferencedSpecificationLoader` receives the owning project's explicit root
and performs bounded Markdown discovery without a visible-project fallback.
Twelve direct tests cover path containment, Unicode, missing and oversized
files, malformed input, first-match selection, and filesystem failures. The
`prompt-context` record is now `partial`.

WS4-4 completed focused acceptance on 2026-07-31. The 135-line
`SecondaryCompletionRouter` receives immutable route facts for workflow, task,
goal, memory, and approval-review completions. Fifteen direct tests cover
assigned, empty, missing, unhealthy, fallback, non-compatible, immutable,
logging, and failure routes at 27/27 executable lines. The historical
mesh-routing part is removed and marked `extracted`.

WS4-5 completed focused acceptance on 2026-07-31. The 179-line
`ExecutionSnapshotObserver` deduplicates immutable owner observations and
emits bounded shadow fields through a narrow port. Twelve direct tests cover
63/63 executable lines, while the detached-plan poison test proves A's initial
shadow entry keeps A's session context while B is visible. The
historical prompt-context part shrinks from 260 to 254 lines.

WS7-4 completed focused acceptance on 2026-07-31. The 380-line
`AnalysisOptionsLintEditGuard` now owns exact blocked-result construction
without changing its detector API. Seventeen direct tests cover 164/164
executable lines across exact payloads, YAML variants, structured diagnostics,
and process output. The notifier wrapper is gone, `command-guardrails` is
`partial`, and its historical part shrinks from 1,027 to 1,001 lines.

WS7-8 completed focused acceptance on 2026-07-31. The split
`CodingCommandOutputGuardrailService` now owns exact preflight-result
construction while project argument resolution remains at the owner-scoped
caller. Eight direct tests cover 43/43 facade executable lines. The notifier
wrapper is gone and the historical command-guardrails part shrinks from 1,001
to 963 lines.

WS7-5 completed focused acceptance on 2026-07-31. The 151-line
`GitTagFormatInspectionGuard` owns tag parsing, prior-inspection matching, and
exact blocked results from frozen owner-resolved inputs. Fourteen direct tests
cover 58/58 executable lines, including shell controls, inspection ordering,
nested immutability, and cross-repository poisoning. The historical
command-guardrails part shrinks from 963 to 859 lines.

WS5-8 completed focused acceptance on 2026-07-31. The 73-line
`ProcessStartResultPolicy` classifies stale non-duplicate `process_start`
results from explicit dispatch-time evidence before recording execution and
replay state. Eight direct tests cover malformed, failed, duplicate, boundary,
fresh, and stale results with exact diagnostic metadata. The `tool-loop-batch`
record is now `partial`.

WS5-1 completed focused acceptance on 2026-07-31. The 423-line
`CodingContinuationRecoveryPolicy` owns every recovery decision, payload,
prompt, and copy branch from immutable registered-owner facts. Twenty-two
direct tests cover all recovery codes, tool availability, English and CJK
markers, structured deferral, terminal blockers, partial command progress,
immutable inputs, and an owner/visible-thread poison case. The historical
adapter part shrinks from 444 to 126 lines and remains `partial`.

WS5-2 completed focused acceptance on 2026-07-31. The 268-line
`TurnFinalizationRecoveryPolicy` owns final-answer skip, completion/future
classification, evidence, candidate, and prefix decisions from immutable
owner results and explicit facts. Twenty direct tests cover the full decision
matrix, English and CJK markers, exact length limits, immutable inputs, and
owner/visible-generation poisoning. A Notifier integration test locks
generation-correct streamed-answer and tool-evidence selection. The historical
adapter part shrinks from 373 to 304 lines and remains `partial`.

WS5-4 completed focused acceptance on 2026-07-31. The 64-line
`CodingVerificationMutationSignature` computes stable ordered JSON signatures
from immutable owner tool results and an explicit owner project root. Nine
direct tests cover mutation eligibility, `already_applied`, Dart path
selection/resolution, ordering, duplicates, frozen inputs, and roots A/B over
identical evidence. The historical adapter part shrinks from 331 to 313 lines,
and `coding-verification-feedback` remains `partial`.

WS5-5 completed focused acceptance on 2026-07-31. The 281-line
`UnexecutedFinalAnswerToolRequestPolicy` produces immutable new results,
notice text, exit reason, and transform ID from explicit owner tool evidence.
Eighteen direct tests cover exact result payloads and IDs, malformed and
duplicate calls, bracketed/fenced/raw JSON, plan/command/file requests, every
notice gate, idempotence, immutable inputs, and owner/visible-thread poison.
The adapter checks the exact owner before analysis and application. The
historical part shrinks from 564 to 521 lines and remains `partial`.

The focused tree is 8,935 primary lines, 12,105 lines across 37 declared parts,
and 21,040 same-library lines, with exact shrink-only ceilings.
The manifest retains 43 historical records, and the canonical baseline records
71 ambient and 62 turn-reachable reads. Integrated full verification and the
exact-model live canary remain pending at tranche closure and are not claimed
by these focused-acceptance records.

## Corrective Prerequisites

| Slice | Task catalog | Goal | Start gate | Status |
|---|---|---|---|---|
| P1a | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner type and snapshot registry | Slices 2b1-2b7 complete | Complete |
| P1b | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner snapshot adoption | P1a complete | Complete |
| P2 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed turn tool evidence | P1a complete | Complete |
| P3a | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed exit, transform, claim, and shadow state | P2 complete | Complete |
| P3b | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed final completion evidence and explicit continuation handoff | P3a complete | Complete |
| P4 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Independent file mutation evidence | Slices 2b1-2b7 complete | Complete |
| P5a | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed approval cache | P1a complete | Complete |
| P5b | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed command/file/Git/SSH approvals | P1a complete | Complete |
| P5c | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed device/browser/Computer Use/participant approvals | P1a complete | Complete |
| P6 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed file rollback checkpoints | P1a complete | Complete |
| P7 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed background processes and monitoring | P1a complete | In progress |
| P8 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed SSH sessions | P1a complete | In progress |
| P9 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed subagent tasks | P1a complete | In progress |
| P10a | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Atomic streaming terminal metadata | Slices 2b1-2b7 complete | In progress |
| P10b | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed response metadata | P1a and P10a focused acceptance complete | In progress |
| P11 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed conversation taint | P1a complete | In progress |
| P12 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Sub-500-line command output guardrails | Slices 2b1-2b7 complete | Complete |
| P13 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Owner-keyed participant stop/pause control | P1a complete | In progress |
| P14 | `docs/chat_notifier_decomposition_prerequisite_codex_tasks.md` | Independent hidden-evidence scorer | Slices 2b1-2b7 complete | Complete |

## Extraction Workstreams

| Workstream | Task catalog | Approved sub-slices | Start gate | Status |
|---|---|---:|---|---|
| 4 | `docs/chat_notifier_decomposition_workstream_4_codex_tasks.md` | 6 | Slices 2a1-2a3 and 2b1-2b7 complete | In progress |
| 5 | `docs/chat_notifier_decomposition_workstream_5_codex_tasks.md` | 8 | Slices 2a1-2a3 and 2b1-2b7 complete | In progress |
| 6 | `docs/chat_notifier_decomposition_workstream_6_codex_tasks.md` | 20 | Slices 2a1-2a3 and 2b1-2b7 complete | In progress |
| 7 | `docs/chat_notifier_decomposition_workstream_7_codex_tasks.md` | 21 | Slices 2a1-2a3 and 2b1-2b7 complete | In progress |
| 8 | `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md` | 10 | Slices 2a1-2a3 and 2b1-2b7 complete | Planned |

The catalogs now contain 65 approved extraction slices. Workstream 6 uses
separate WS6-11a BLE and WS6-11b serial slices because one collaborator cannot
represent two independently transitioning historical manifest parts.

WS6-19 is a registry-last slice and has an additional ordering gate: WS6-1
through WS6-10, WS6-11a, WS6-11b, WS6-12 through WS6-18, WS8-2, and WS8-7
must be complete. The Workstream 8 question and goal-update handlers remove the
final notifier-bound conversation-tool bindings before the catalog can enforce
its no-`ChatNotifier` contract.

Additional hard gates are:

P3b now satisfies the completion-evidence gate for WS8-7; the ordering row is
retained to prevent regressions.

| Prerequisite | Required before |
|---|---|
| P1a | P1b, P2, P3a, P3b, P5a-P5c, P6-P11, P13, and owner-port work |
| P1b | WS4-1, WS4-2, WS4-3, WS4-5, WS5-1, WS5-4, WS5-6, WS5-7, WS6-2, WS6-7, WS6-10, WS6-18 |
| P2 | P3a, P3b, WS5-2, WS5-5, WS5-6, WS5-7, WS7-6, WS7-11, WS8-7 |
| P3a | P3b, WS5-5, WS5-6, WS5-7 |
| P3b | WS8-7 |
| P4 | WS5-4 |
| P5a, P5b, P5c, P11 | WS6-1 |
| P5b | WS6-3, WS6-4, WS6-5, WS6-6, WS6-7, WS6-8, WS6-9, WS6-10, WS6-12, WS6-13 |
| P5c | WS6-11a, WS6-11b, WS6-14, WS6-16, WS8-9 approval adapter |
| P6 | WS4-6, WS6-4 |
| P7 | WS6-6, WS6-18 |
| P8 | WS6-9 |
| P9 | WS6-17 |
| P10a | P10b |
| P10b | WS8-8 |
| P11 | WS6-1, WS8-9 |
| P12 | WS7-8 |
| P13 | WS8-10 |
| P14 | WS5-3 |
| WS8-1 | WS7-7, WS8-2 |
| WS6-1 | WS8-9 |

## Status Rules

- `Planned`: the task specification exists but implementation has not started.
- `In progress`: implementation has started and its own acceptance criteria are
  not yet all proven.
- `Complete`: the slice acceptance criteria, focused verification, applicable
  live canary, manifest transition, budgets, and handoff evidence are complete.
- `Deferred`: a documented stop condition prevents safe extraction. The task
  must name the missing prerequisite and may not disguise the dependency with a
  broad context object or callback.

Update this index in the same focused commit that changes a slice status.
