# macOS Computer Use Element Grounding Release Roadmap

This roadmap extends the existing macOS Computer Use MVP and release gates with
element-grounded desktop control. The goal is to move from coordinate-first
Computer Use toward a product-ready flow that can observe UI elements, preserve
approval boundaries, and execute one user-approved action at a time with
stronger grounding.

The existing M31-M40 track remains the baseline for release evidence,
packaging, beta sign-off, and production launch gates. This document adds
M41-M56 for the next productization cycle.

## Product Principles

- Computer Use remains off by default.
- macOS TCC grants remain user-operated.
- Desktop actions require explicit approval.
- Public actions require separate approval.
- Secure fields, credential prompts, payment flows, and destructive targets are
  blocked or require an additional explicit confirmation before execution.
- Every action cycle keeps the observe, approve, act, observe, and review
  boundary.
- Audit exports are redacted by default and require explicit user intent before
  exporting screenshots, typed text, audio payloads, or raw tool payloads.

## Milestones

| Milestone | Status | Name | Goal | Release gate |
| --- | --- | --- | --- | --- |
| M31R | done | Evidence Baseline Refresh | Refresh the current Computer Use evidence baseline and clear the missing release artifact gate. | `bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs` passes and the artifact index points to the next blocker. |
| M41 | done | Accessibility Snapshot | Add a read-only AX snapshot tool for the front window or selected window. | `computer_accessibility_snapshot` returns bounded role, label, frame, enabled, focused, and redaction metadata without taking action. |
| M42 | done | Element Grounding | Connect screenshot observations with accessibility element candidates. | `computer_vision_observe` includes candidate element metadata that the model can cite when proposing an action. |
| M43 | done | Element-Targeted Actions | Allow approved actions to target an `element_id` before falling back to coordinates. | Fixture click, focus, and type flows pass without coordinate fallback when a valid element is available. |
| M44 | done | Approval UX Upgrade | Make the approval dialog element-aware. | Approval copy shows app, window, role, label, intended action, risk, exact text when relevant, and the latest observation context. |
| M45 | done | Safety Policy Hardening | Strengthen public-action, secure-field, credential, payment, and destructive-target handling. | Dangerous targets are blocked or require the appropriate separate approval before execution. |
| M46 | done | Element-Grounded LLM Evaluation | Extend the Computer Use LLM evaluation suite for element grounding. | Fixture and real-app screenshot scenarios pass target ambiguity, exact text, public-action boundary, refusal, and stale evidence checks. |
| M47 | done | Real-App Observe Pilot | Stabilize observe-only real-app workflows using element-aware evidence. | User-provided screenshots can produce M14-M18 handoffs with stable target, text-entry, public-action, and confirmation metadata. |
| M48 | done | User-Operated Action Pilot | Validate one real-app user-approved action cycle end to end. | Evidence records observe, approve, action, post-action observe, result intake, and post-action review for a safe target. |
| M49 | done | Privacy and Audit Release Pack | Bring audit, export, and support diagnostics to product-release quality. | Default exports redact screenshots, typed text, audio payloads, secrets, and raw payloads; explicit payload export is documented and gated. |
| M50 | done | Signed Beta | Run the element-grounded flow on a signed, notarized beta build. | Clean install, upgrade, permission grant, permission revocation, helper restart, XPC fallback observability, and a user-operated action cycle pass. |
| M51 | done | Production Launch Gate | Refresh the production launch gate with element-grounded evidence. | Signed artifact, notarization, helper identity, manual TCC, element-grounded LLM eval, privacy/audit release pack, emergency stop, privacy copy, support diagnostics, and signed beta evidence are ready. |
| M52 | done | Product Release | Ship element-grounded Computer Use behind Advanced settings. | Computer Use remains default off, Advanced-enabled, reversible, supportable, and covered by rollback and support runbooks. |
| M53 | done | Post-Release Operations Guardrails | Keep released Computer Use guarded by scheduled operational review. | M52 evidence remains ready and support diagnostics, known issues, incidents, rollback readiness, hotfix triggers, and review cadence are signed off. |
| M54 | done | Rollout Expansion Gate | Decide whether the released Computer Use rollout can expand safely. | M53 evidence remains ready and expansion scope, cohort risk, support capacity, safety metrics, rollback pause, communications, ownership, and next review are signed off. |
| M55 | done | Post-Expansion Monitoring Gate | Review evidence after rollout expansion and decide whether to continue, hold, pause, or roll back. | M54 evidence remains ready and expansion scope, safety metrics, support load, incidents, rollback/pause readiness, owners, next review, and continuation decision are signed off. |
| M56 | done | Rollout Decision Handoff Gate | Hand off the approved M55 rollout continuation decision to the next user-operated branch. | M55 evidence remains ready and the decision branch, handoff owner, evidence archive, communications, risk controls, and next review are signed off. |

## M41 Scope

M41 is intentionally read-only. It should add observability without expanding
the action surface.

Implementation scope:

- Add a helper command that extracts a bounded accessibility tree from the
  front window or a requested window.
- Add a Dart service method for the helper command.
- Add the built-in MCP tool definition `computer_accessibility_snapshot`.
- Classify the new tool as a planning-allowed observation tool.
- Redact secure text fields and long values by default.
- Include stable element identifiers only for the current observation scope.
- Add focused tests for policy classification, tool definition shape, redaction
  rules, and static helper command coverage.

Out of scope:

- Clicking or typing by `element_id`.
- Automatic TCC grants.
- System Settings automation.
- Raw full AX tree export without bounds or redaction.

## M41 Acceptance Criteria

- `computer_accessibility_snapshot` is available when Computer Use tools are
  enabled.
- The tool returns `schemaName`, `observationId`, target window metadata,
  element count, redaction summary, and a bounded element list.
- Each element includes an `elementId`, role, label or title when safe, enabled
  state, focused state, frame, and child count.
- Secure text fields never expose values.
- Long labels and values are truncated with explicit truncation metadata.
- Planning mode allows the tool because it is read-only.
- Existing Computer Use action approval behavior is unchanged.

## M42-M43 Direction

M42 should join visual and accessibility evidence. The model should be able to
see both a screenshot and a small set of likely target elements before it asks
for an action.

M42 implementation status:

- `computer_vision_observe` now attempts helper-owned accessibility grounding
  for `front_window` and `window` observations that resolve to a `window_id`.
- The result includes `elementGrounding` with schema name, status, source tool,
  snapshot id, window id, coordinate space, redaction metadata, and bounded
  `candidateElements`.
- Candidate elements keep only citeable metadata: `elementId`, role, optional
  subrole, label, label source, frame, enabled/focused state, child count, and
  redaction flags.
- Failed or blocked accessibility grounding does not fail the screenshot
  observation. The result reports `elementGrounding.status` as `blocked`,
  `failed`, or `skipped` with a code.
- M42 does not add element-targeted execution. Approved actions may cite
  `target.elementId` as metadata, while coordinate execution remains unchanged.

M43 implementation status:

- `computer_click` accepts `element_id` plus `window_id`, resolves the element
  through helper-owned AX traversal, and tries AXPress before any coordinate
  fallback.
- `computer_type_text` accepts `element_id` plus `window_id` and focuses the
  resolved element before typing.
- `computer_focus_window` keeps `window_id` as the primary target and can focus
  a resolved element when `element_id` is provided.
- Coordinate fallback remains available and is disclosed through
  `elementTargeting.fallbackUsed`.
- Public-action and exact-text approvals remain enforced by the existing policy.

M44 implementation status:

- Pending Computer Use approvals now carry a target review summary and target
  details derived from `target` metadata, `element_id`, `window_id`, and the
  latest observation arguments.
- The approval sheet shows app, bundle id, window, element id, role, label,
  intended action, target risk, and coordinate fallback metadata when present.
- `computer_type_text` approvals show the exact text and character count in a
  bounded, selectable preview before the user can approve the action.
- The latest observation context is labeled explicitly and still shows
  observation id, coordinate space, source screenshot size, window id, and
  display id when available.
- Tool schemas and the system prompt now ask the model to include app and
  window metadata with element-targeted approval metadata when available.

M45 implementation status:

- Target safety classification now identifies `public_action`, `secure_field`,
  `credential`, `payment`, and `destructive` targets from explicit risk
  metadata and conservative role, label, and action tokens.
- Public actions keep the separate approval blocker, while secure fields,
  credential prompts, payment flows, and destructive controls are hard-blocked
  before helper execution.
- Approved actions with unresolved safety blockers return
  `code=action_policy_blocked` and include `approvalBlockers` instead of
  calling the helper.
- Tool schemas, observation policy copy, and the system prompt now tell the
  model to mark high-risk targets explicitly and to ask the user to handle
  blocked targets manually.
- Production policy required approvals and hard blocks now include the
  high-risk target refusal classes.

M46 implementation status:

- Added `tool/run_macos_computer_use_m46_element_grounded_llm_eval.sh` as a
  report-only evaluation runner for element-grounded Computer Use decisions.
- The M46 gate records
  `macos_computer_use_m46_element_grounded_llm_eval_summary` and
  `m46ElementGroundedLlmEvaluationGate` with per-scenario and per-coverage
  results.
- Evaluation coverage now checks element target disambiguation, exact
  text-to-target pairing, public-action approval blockers, M45 high-risk target
  refusal, stale observation recovery, and coordinate-only fallback refusal.
- The runner accepts fixture-suite responses for deterministic CI tests or
  live LLM screenshot inputs for fixture and real-app screenshots, while
  preserving the no-TCC and no-desktop-action boundary.
- Debug guidance now lists the M46 command and expected summary path beside the
  existing M36 evaluation command.

M47 implementation status:

- Added `tool/run_macos_computer_use_m47_real_app_observe_pilot.sh` as a
  report-only pilot runner for ready M14 real-app observe evidence.
- The M47 runner generates M15, M16, M17, and M18 handoffs from the selected
  M14 summary, using approved exact text, target label, and public-action label
  values while preserving no-TCC, no-LLM, and no-desktop-action boundaries.
- The M47 gate records `macos_computer_use_m47_real_app_observe_pilot` and
  `m47RealAppObservePilotGate`, validating stable text-entry target labels,
  exact text, public-action labels, separate public-action approval metadata,
  and M18 action-time confirmations.
- Debug guidance now lists the M47 pilot command and expected summary path.

M48 implementation status:

- Added `tool/run_macos_computer_use_m48_user_operated_action_pilot.sh` as a
  report-only pilot gate for one user-operated real-app action cycle.
- The M48 runner consumes ready M47 pilot evidence, resolves its M18 handoff,
  and records user-provided runtime evidence through M20, M22, and M23.
- The M48 gate records `macos_computer_use_m48_user_operated_action_pilot` and
  `m48UserOperatedActionPilotGate`, validating safe-target confirmation,
  stable approval metadata, public-action separate approval, fresh
  observation, succeeded user-operated action evidence, post-action
  observation, post-action review, and closed cycle outcome.
- Debug guidance now lists the M48 pilot command and expected summary path.

M49 implementation status:

- Added `tool/run_macos_computer_use_m49_privacy_audit_release_pack.sh` as a
  report-only release-pack gate for redacted Computer Use diagnostics and M48
  user-operated action-cycle evidence.
- The M49 runner accepts exported Computer Use diagnostics or a standalone
  `macos_computer_use_audit_privacy_controls` JSON file, then validates M37
  audit/privacy readiness, required event declarations, default redaction,
  explicit payload export requirements, and ordinary-diagnostics raw payload
  leak checks.
- The M49 gate records `macos_computer_use_m49_privacy_audit_release_pack` and
  `m49PrivacyAuditReleasePackGate`, validating redacted export review, privacy
  copy review, support diagnostics review, explicit payload export policy
  review, and separate approval if raw payload export is requested.
- Debug guidance now lists the M49 release-pack command and expected summary
  path.

M50 implementation status:

- Added `tool/run_macos_computer_use_m50_signed_beta_gate.sh` as a report-only
  signed beta gate for element-grounded Computer Use release evidence.
- The M50 gate consumes M7 signed artifact evidence, M33 packaging evidence,
  M46 element-grounded LLM evaluation, M48 user-operated action-cycle evidence,
  M49 privacy/audit release-pack evidence, and an M50 user-operated signed beta
  checklist.
- The M50 gate records `macos_computer_use_m50_signed_beta_gate` and
  `m50SignedBetaGate`, validating notarized beta build evidence, clean install,
  upgrade, permission grant, permission revocation, helper restart, XPC
  fallback observability, and the closed user-operated action cycle.
- Debug guidance now lists the M50 signed beta command and expected summary
  path.

M51 implementation status:

- Added `tool/run_macos_computer_use_m51_production_launch_gate.sh` as a
  report-only production launch gate for the element-grounded Computer Use
  release lane.
- The M51 gate consumes M7 signed artifact evidence, M33 packaging evidence,
  manual TCC evidence, M38 helper install/migration diagnostics, M46
  element-grounded LLM evaluation, M49 privacy/audit release-pack evidence,
  M50 signed beta gate evidence, and an M51 user-operated launch checklist.
- The M51 gate records `macos_computer_use_m51_production_launch_gate`,
  `launchReviewSummary`, and per-gate blockers for notarization, helper
  identity, manual TCC, element-grounded LLM readiness, privacy/audit release
  readiness, signed beta readiness, emergency stop, privacy copy, support
  diagnostics, and production launch boundaries.
- Debug guidance and the readiness artifact index now list the M51 production
  launch command, expected summary path, and next-step navigator transition
  from M50 to M51.

M52 implementation status:

- Added `tool/run_macos_computer_use_m52_product_release_rollout.sh` as a
  report-only product release rollout gate for element-grounded Computer Use.
- The M52 gate consumes M51 production launch evidence and an M52 user-operated
  product release checklist.
- The M52 gate records
  `macos_computer_use_m52_product_release_rollout`,
  `releaseRolloutSummary`, and `m52ProductReleaseGate`.
- The checklist covers default-off release, Settings > Advanced enablement,
  reversible disable path, emergency stop, rollback runbook, support runbook,
  privacy release notes, support diagnostics handoff, rollout owner,
  monitoring, and escalation evidence.
- Debug guidance and the readiness artifact index now list the M52 product
  release rollout command, expected summary path, and next-step navigator
  transition from M51 to M52.

M53 implementation status:

- Added `tool/run_macos_computer_use_m53_post_release_guardrails.sh` as a
  report-only post-release operations gate for element-grounded Computer Use.
- The M53 gate consumes M52 product release rollout evidence and an M53
  user-operated post-release checklist.
- The M53 gate records
  `macos_computer_use_m53_post_release_guardrails`,
  `postReleaseGuardrailsSummary`, and `m53PostReleaseGuardrailsGate`.
- The checklist covers review cadence, default-off state, Advanced-only
  enablement, support diagnostics review, known issues, incident review,
  rollback readiness, and hotfix or rollout-pause triggers.
- Debug guidance and the readiness artifact index now list the M53
  post-release guardrails command, expected summary path, and next-step
  navigator transition from M52 to M53.

M54 implementation status:

- Added `tool/run_macos_computer_use_m54_rollout_expansion_gate.sh` as a
  report-only rollout expansion gate for element-grounded Computer Use.
- The M54 gate consumes M53 post-release guardrail evidence and an M54
  user-operated rollout expansion checklist.
- The M54 gate records `macos_computer_use_m54_rollout_expansion_gate`,
  `rolloutExpansionSummary`, and `m54RolloutExpansionGate`.
- The checklist covers expansion scope, cohort risk, support capacity, safety
  metrics, rollback and rollout pause readiness, communications, ownership,
  escalation, and the next review schedule.
- Debug guidance and the readiness artifact index now list the M54 rollout
  expansion command, expected summary path, and next-step navigator transition
  from M53 to M54.

M55 implementation status:

- Added `tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh` as
  a report-only post-expansion monitoring gate for element-grounded Computer
  Use.
- The M55 gate consumes M54 rollout expansion evidence and an M55
  user-operated post-expansion monitoring checklist.
- The M55 gate records
  `macos_computer_use_m55_post_expansion_monitoring_gate`,
  `postExpansionMonitoringSummary`, and `m55PostExpansionMonitoringGate`.
- The checklist covers the observed expanded cohort, safety metrics, support
  load, incidents, complaints, regressions, rollback and rollout pause
  readiness, owner follow-up, next review, and the approved continuation
  decision.
- The continuation decision is one of `continue_expansion`,
  `hold_current_cohort`, `pause_rollout`, or `rollback_recommended`.
- Debug guidance and the readiness artifact index now list the M55
  post-expansion monitoring command, expected summary path, and next-step
  navigator transition from M54 to M55.

M56 implementation status:

- Added `tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh` as
  a report-only rollout decision handoff gate for element-grounded Computer
  Use.
- The M56 gate consumes M55 post-expansion monitoring evidence and an M56
  user-operated rollout decision handoff checklist.
- The M56 gate records
  `macos_computer_use_m56_rollout_decision_handoff_gate`,
  `rolloutDecisionHandoffSummary`, and `m56RolloutDecisionHandoffGate`.
- The handoff maps `continue_expansion` to `next_expansion_cycle_seed`,
  `hold_current_cohort` to `monitoring_cadence_hold`, `pause_rollout` to
  `rollout_pause_handoff`, and `rollback_recommended` to `rollback_handoff`.
- Debug guidance and the readiness artifact index now list the M56 rollout
  decision handoff command, expected summary path, and next-step navigator
  transition from M55 to M56.

## Release Readiness Path

1. Keep the refreshed M31R evidence baseline current.
2. Keep M41 and M42 as the observe contracts that provide current element
   candidates.
3. Use M43 element-targeted actions behind existing approval and arming gates.
4. Use M44 element-aware approval UI so users can review target identity,
   exact text, and latest observation context before execution.
5. Use M45 safety policy hardening to block or separate-approve high-risk
   targets before any helper-owned execution.
6. Use M46 evaluation coverage before using real-app action pilots.
7. Use M47 real-app observe pilot evidence before running M48.
8. Use M48 user-operated action pilot evidence before building M49 privacy and
   audit release packs.
9. Use M49 privacy and audit release-pack evidence before signed beta.
10. Use M50 signed beta evidence before refreshing the M51 production launch
    gate.
11. Use M51 production launch evidence before moving to the M52 product release
    rollout.
12. Use M52 product release rollout evidence before shipping element-grounded
    Computer Use to users.
13. Use M53 post-release guardrail evidence for scheduled operational review
    after product release.
14. Use M54 rollout expansion evidence before broadening the Computer Use
    rollout beyond the currently approved cohort.
15. Use M55 post-expansion monitoring evidence after expansion to decide
    whether to continue, hold, pause, or roll back the rollout.
16. Use M56 rollout decision handoff evidence to route the approved M55
    decision into the next user-operated rollout branch.

## Verification Commands

Baseline evidence:

```bash
bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs
```

Static checks for implementation milestones:

```bash
flutter analyze
flutter test test/core/services/macos_computer_use_tool_policy_test.dart
flutter test test/features/chat/presentation/providers/macos_computer_use_approval_copy_test.dart
```

Computer Use post-merge sanity:

```bash
bash tool/run_macos_computer_use_post_merge_sanity.sh
```

Runtime verification remains scoped by
`docs/macos_computer_use_mvp_checklist.md`: run TCC or real desktop action
verification only when the change touches runtime permission, capture, input,
overlay, helper identity, or helper process behavior.
