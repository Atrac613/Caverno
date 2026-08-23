# SEC4.6i Conversation Attachment Deletion

Status: completed on 2026-08-23.

## Task

- Goal: delete durable attachments when their owning conversation is deleted.
- User-visible behavior: deleting a conversation also removes its persisted
  original images, videos, and large-file copies when no retained conversation
  references the same file.
- Non-goals: deleting unsent composer drafts, changing the seven-day orphan
  sweep, or finalizing platform privacy declarations.

## Context

- Affected components: attachment storage, conversation deletion paths, and
  focused storage/notifier regressions.
- Related finding: SA-18 in `docs/security_audit_2026-08-14.md`.
- Reference behavior: messages store original-image and video paths directly;
  large files use the composer's canonical attached-file marker.
- Release gate: SEC4.6 data protection and lifecycle.

## Implementation Notes

- Collect attachment paths before deleting conversation state.
- Apply the same cleanup to single, active-scope, and coding-project deletion.
- Preserve files still referenced by a retained conversation.
- Normalize references before comparison so equivalent path spellings preserve
  shared files.
- Restrict physical deletion to regular files directly inside Caverno's
  managed attachment directory; ignore outside, nested, missing, and linked
  paths.
- Keep cleanup best-effort after the persisted conversation is removed.
- No generated files, migrations, or new dependencies are required.

## Similar-Pattern Search

- Search terms: `deleteConversation`, `deleteScopedConversations`,
  `deleteConversationsForProject`, `originalImagePath`, `videoPath`,
  `Attached file`, `AttachmentStorageService`, and `deleteConversationArtifacts`.
- Files inspected: all conversation deletion paths, message persistence,
  composer image/video/large-file creation, artifact cleanup, and attachment
  age sweeping.
- Follow-up tasks found: final iOS privacy-manifest and platform-disclosure
  reconciliation is the remaining bounded SA-18 slice.

## Acceptance Criteria

- Single-conversation deletion schedules all owned attachment types for cleanup.
- Scope and project deletion use the same cleanup boundary.
- A path referenced by a retained conversation is not deleted.
- Outside, nested, missing, linked, and duplicate paths cannot escape or break
  the storage boundary.
- Existing conversation, artifact, process, and semantic-index cleanup remains
  unchanged.

## Verification

```bash
fvm flutter test --no-pub \
  test/core/services/attachment_storage_service_test.dart \
  test/features/chat/presentation/providers/conversations_notifier_test.dart
fvm flutter analyze --no-pub
tool/codex_verify.sh --no-codegen \
  --test test/core/services/attachment_storage_service_test.dart \
  --test test/features/chat/presentation/providers/conversations_notifier_test.dart
```

## Handoff Notes

- Summary: conversation deletion now removes unshared, managed original-image,
  video, and large-file attachments through a fail-safe storage boundary.
- Tests run: focused storage/notifier regressions, static analysis, and the
  repository verification gate.
- Risks or follow-ups: unsent or legacy unreferenced files remain covered by the
  seven-day sweep. Complete SA-18 by reconciling final platform privacy
  declarations with the implemented data flows.
