# LL37 Reviewed Continuation Slice

## Task

- Goal: Turn a terminal route-diverse LL37 aggregate into a deterministic,
  privacy-filtered repair packet that crosses the continuation boundary only
  after an explicit user copy action.
- User-visible behavior: A converged refutation in the idle-maintenance history
  shows its frozen objective, acceptance contract, concrete gap set, and a
  `Copy repair nudge` action. Unverifiable or inconsistent evidence shows a
  user-decision requirement and never produces a repair nudge.
- Non-goals: Automatic task mutation, automatic LL13/Routine retries, inline
  chat verification, model calls, worktree writes, parallel fan-out,
  strategist passes, or changing the objective and acceptance criteria.

## Context

- Affected components: LL37 vote aggregation, a new pure domain continuation
  policy, and the idle-maintenance verdict history UI.
- Related docs: `docs/local_llm_agent_roadmap.md` LL37 and
  `docs/ll37_second_verifier_route_codex_task.md`.
- Reference pattern: The existing history UI is read-only and already omits
  changed-file contents, raw prompts, and raw verifier responses.
- Release gate: The interactive chat feature must remain unable to import LL37
  panel or continuation-policy code.

## Implementation Notes

- Build the review packet only from the persisted route-validated aggregate.
- Freeze one normalized objective and ordered acceptance contract across all
  counted votes. Contract disagreement requires a user decision.
- A repair nudge requires a terminal converged `refuted` aggregate with concrete
  contradiction findings. Deduplicate and sort gaps deterministically, and
  assign content-derived stable gap IDs.
- The anti-ratchet text must limit the repair to prior blocking gaps, forbid
  objective/criteria mutation, require fresh implementation evidence, and say
  that a new objection may block only for a concrete defect or unmet gating
  criterion. Style, robustness, and test-construction preferences are
  non-blocking.
- `notRefuted` produces no action. `unverifiable`, stalled, capped, malformed,
  or contract-inconsistent aggregates produce a user-decision state and no
  nudge.
- The copy action is the only boundary crossing in this slice. Merely opening
  the page has no clipboard, persistence, task, or model side effect.

## Similar-Pattern Search

- Search terms: `Clipboard.setData`, `GoalContinuation`, `autoContinue`,
  `manual review`, `objective_verify`, and `worktreeAgentTask`.
- Inspected modules: idle-maintenance debug UI, goal auto-continuation runtime,
  candidate adoption manual-review gates, and LL13 task registry/launcher.
- Follow-up found: A future explicitly approved adapter may submit the copied
  packet to a new LL13 repair task. Reusing or mutating the completed source
  task is intentionally excluded because terminal LL13 tasks have no safe
  resume contract.

## Acceptance Criteria

- Equivalent route order produces the same gap IDs and repair packet.
- A converged refutation exposes only objective, criteria, finding metadata,
  candidate ID, and anti-ratchet instructions; it excludes changed-file
  contents, implementation evidence bodies, raw prompts, and raw responses.
- Objective or acceptance-contract disagreement suppresses the nudge.
- Non-refuted results have no action; unverifiable results require a user
  decision and have no copy action.
- Copying requires an explicit button press and copies the exact previewed
  packet. No task is queued or modified.
- Interactive chat code cannot import the continuation policy.

## Verification

```bash
fvm flutter test \
  test/features/maintenance/domain/services/ll37_objective_continuation_policy_test.dart \
  test/features/maintenance/presentation/pages/idle_maintenance_debug_page_test.dart \
  test/widget_test.dart
fvm flutter analyze
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Implemented deterministic continuation review, stable gap IDs,
  privacy-filtered anti-ratchet packets, explicit copy-only UI, and structural
  isolation from interactive chat.
- Focused tests: 29 passed across the domain policy, debug-page widget,
  maintenance-stage boundary, and translation parity suites. `fvm flutter
  analyze` reported no issues.
- Full gate: `tool/codex_verify.sh` passed with 7,345 Flutter tests and 10
  notification-relay tests; root and package analyzers and generated-file
  checks were clean. The first full run exposed one unrelated Settings widget
  flake; its isolated rerun and both subsequent complete gates passed.
- Risks: A copied packet still requires the user to select a destination and
  start a new task. This slice deliberately does not infer that authority.
