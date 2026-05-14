# macOS Computer Use Element Grounding Release Roadmap

This roadmap extends the existing macOS Computer Use MVP and release gates with
element-grounded desktop control. The goal is to move from coordinate-first
Computer Use toward a product-ready flow that can observe UI elements, preserve
approval boundaries, and execute one user-approved action at a time with
stronger grounding.

The existing M31-M40 track remains the baseline for release evidence,
packaging, beta sign-off, and production launch gates. This document adds
M41-M52 for the next productization cycle.

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
| M31R | next | Evidence Baseline Refresh | Refresh the current Computer Use evidence baseline and clear the missing release artifact gate. | `bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs` passes and the artifact index points to the next blocker. |
| M41 | next | Accessibility Snapshot | Add a read-only AX snapshot tool for the front window or selected window. | `computer_accessibility_snapshot` returns bounded role, label, frame, enabled, focused, and redaction metadata without taking action. |
| M42 | later | Element Grounding | Connect screenshot observations with accessibility element candidates. | `computer_vision_observe` includes candidate element metadata that the model can cite when proposing an action. |
| M43 | later | Element-Targeted Actions | Allow approved actions to target an `element_id` before falling back to coordinates. | Fixture click, focus, and type flows pass without coordinate fallback when a valid element is available. |
| M44 | later | Approval UX Upgrade | Make the approval dialog element-aware. | Approval copy shows app, window, role, label, intended action, risk, exact text when relevant, and the latest observation context. |
| M45 | later | Safety Policy Hardening | Strengthen public-action, secure-field, credential, payment, and destructive-target handling. | Dangerous targets are blocked or require the appropriate separate approval before execution. |
| M46 | later | Element-Grounded LLM Evaluation | Extend the Computer Use LLM evaluation suite for element grounding. | Fixture and real-app screenshot scenarios pass target ambiguity, exact text, public-action boundary, refusal, and stale evidence checks. |
| M47 | later | Real-App Observe Pilot | Stabilize observe-only real-app workflows using element-aware evidence. | User-provided screenshots can produce M14-M18 handoffs with stable target, text-entry, public-action, and confirmation metadata. |
| M48 | later | User-Operated Action Pilot | Validate one real-app user-approved action cycle end to end. | Evidence records observe, approve, action, post-action observe, result intake, and post-action review for a safe target. |
| M49 | later | Privacy and Audit Release Pack | Bring audit, export, and support diagnostics to product-release quality. | Default exports redact screenshots, typed text, audio payloads, secrets, and raw payloads; explicit payload export is documented and gated. |
| M50 | later | Signed Beta | Run the element-grounded flow on a signed, notarized beta build. | Clean install, upgrade, permission grant, permission revocation, helper restart, XPC fallback observability, and a user-operated action cycle pass. |
| M51 | later | Production Launch Gate | Refresh the production launch gate with element-grounded evidence. | Signed artifact, notarization, helper identity, manual TCC, LLM eval, audit, emergency stop, privacy copy, support diagnostics, and beta sign-off are ready. |
| M52 | later | Product Release | Ship element-grounded Computer Use behind Advanced settings. | Computer Use remains default off, Advanced-enabled, reversible, supportable, and covered by rollback and support runbooks. |

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

M43 should make action execution prefer element targets:

- `computer_focus_window` can keep using `window_id`.
- `computer_click` accepts `element_id` plus target metadata.
- `computer_type_text` can focus an element before typing when an element target
  is provided.
- Coordinate fallback remains available, but the result must disclose when a
  fallback was used.
- Public-action and exact-text approvals remain enforced by the existing policy.

## Release Readiness Path

1. Refresh the evidence baseline with M31R.
2. Implement and verify M41 as read-only.
3. Add M42 observation grounding without action changes.
4. Add M43 element-targeted actions behind existing approval and arming gates.
5. Expand evaluation coverage in M46 before using real-app action pilots.
6. Run M48 only as a user-operated pilot.
7. Use M50-M51 for signed beta and production launch evidence.

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
