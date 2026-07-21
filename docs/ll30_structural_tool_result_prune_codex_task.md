# LL30 Structural Tool-Result Prune

## Task

- Goal: Add the first LL30 compaction pre-pass: de-duplicate identical old
  tool results and replace old result bodies with informative one-line
  summaries before `ConversationCompactionService` builds its artifact.
- User-visible behavior: None. Compacted context retains more useful tool facts
  while using fewer estimated prompt tokens.
- Non-goals: Token-budget tail selection, tool-call argument truncation,
  attachment eviction, anti-thrashing state, or per-request pruning.

## Context

- Affected files or components: `ConversationCompactionService`, a new pure
  domain helper beside it, focused tests, and a synthetic measurement tool.
- Related docs: `docs/local_llm_agent_roadmap.md` LL30,
  `docs/reread_loop_mechanism_2026-07-21.md`, and
  `docs/edit_anchor_recovery_measurement_2026-07-21.md`.
- Reference implementation or pattern: Hermes structural pruning and Grok
  Build's graduated tool-result pruning, with Caverno's compaction-boundary
  firing point preserved for prefix stability.
- Known quirks, compatibility rules, or release gates: Tool-result messages
  use `[Tool: name]`, `Arguments: <JSON>`, and `Result:` sections. Messages that
  do not parse as rendered results must remain unchanged.

## Implementation Notes

- Preferred approach: Build a pure `ConversationToolResultPruner` that parses
  rendered sections, walks newest-to-oldest for exact duplicate detection, and
  emits one line per result with the tool name, key argument, and outcome.
  Apply it only to the older messages already selected for compaction.
- Constraints: No LLM call, no persistence change, no mutation of recent
  messages, and no dependency outside the Dart SDK.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `formatToolResults`, `ToolLoopContextDigest`,
  `_budgetToolResultPayload`, `ConversationCompactionService`, and
  `recentMessagesToKeep`.
- Files or modules inspected: `tool_result_prompt_builder.dart`,
  `tool_loop_context_digest.dart`, `conversation_compaction_service.dart`, and
  their focused tests.
- Follow-up tasks found: Parsed tool-call argument truncation, token-budget
  protected tails, attachment eviction wording, and ineffective-pass back-off.

## Acceptance Criteria

- Required behavior: One-line summaries retain the tool name, the most useful
  argument, and the parsed outcome; older exact duplicates carry an explicit
  back-reference to the newer result.
- Edge cases: Multiple tool sections in one message are handled in order;
  malformed and non-result sections are preserved verbatim; unrelated messages
  are unchanged.
- Failure paths: Invalid argument or result JSON falls back to bounded text
  facts without throwing.
- Accessibility, localization, or platform expectations: None. Developer-only
  English output.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_tool_result_pruner_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_compaction_service_test.dart
fvm dart run tool/measure_compaction_structural_prune.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a pure structural pruner, wired it only into the older message
  slice immediately before compaction summary construction, and preserved
  malformed or prose-prefixed lookalikes verbatim.
- Tests run: `tool/codex_verify.sh` completed successfully with clean analysis
  and 3,937 Flutter tests passing. The synthetic measurement reduced estimated
  prompt tokens from 29,499 to 222 (99.2%) for twelve identical large
  `read_file` results.
- Coverage or low-coverage notes: The synthetic result is an intentionally
  duplicate-heavy upper-bound fixture, not an observed production savings
  estimate.
- Risks or follow-ups: Parsed tool-call argument truncation, token-budget tails,
  attachment eviction, and ineffective-pass back-off remain separate LL30
  slices. The next measurement should replay the 23 no-edit read-heavy sessions
  before choosing among them.
