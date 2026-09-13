# Conversation Fork Roadmap

Scope, acceptance criteria, and dated evidence for this track.
[Cross-track priorities](roadmap.md#active-focus) remain in the main
roadmap; dated investigation notes below preserve the implementation history.

## Conversation Fork Track

Conversation fork lets the user branch a new thread from any point in an
existing conversation. Chat fork is a pure history operation; coding fork must
also reproduce the on-disk/git state at the fork point, so it is a strict
superset gated on the LL2 checkpoint and LL13 worktree machinery. These
milestones use `FORK<number>` and are documented here rather than in the Local
LLM roadmap because they are a user-facing conversation-threading feature rather
than local-LLM execution work.

### FORK1: Chat Conversation Fork

Status: `next`

Scope:
- From any message in a chat-mode conversation, create a new conversation that
  copies the message history up to and including that message.
- Add `parentConversationId` and a fork-origin descriptor (fork message id and
  index) to `Conversation`; the child is independent and the parent is never
  mutated by child edits.
- Trim fork-point-invalid state from the copy: drop streaming/incomplete
  messages and any checkpoints or turn diffs recorded after the fork index.
- Surface a per-message "fork here" affordance and show the parent/child
  relationship in the conversation drawer.

Acceptance criteria:
- Forking at message N yields a new conversation containing `messages[0..N]` and
  the conversation-level metadata valid at that point.
- Editing or continuing the child does not change the parent, and vice versa.
- The new linkage fields round-trip through the drift repository.
- The drawer makes the fork relationship discoverable.
- Focused tests cover the fork builder, metadata trimming, and persistence.

Dependencies:
- New `Conversation` fields require a Freezed regeneration
  (`dart run build_runner build --delete-conflicting-outputs`).

Next action:
- Add the linkage fields, a fork path reusing `_createConversation`/`save`, and
  the per-message fork affordance.

### FORK2: Coding Conversation Fork

Status: `later`

Scope:
- Fork a coding-mode conversation at message N and reproduce the working-tree
  and git state as of that turn into an isolated git worktree/branch, reusing
  the LL13 worktree machinery seeded from the parent's turn commit or the LL2
  file checkpoint at the fork point.
- Never share a worktree between the parent and the fork; assign the fork a
  fresh `worktreePath`/branch while carrying `projectId`.
- Define a non-git fallback (file snapshot copy) and a clear collision policy
  when the project is not a git repository.

Acceptance criteria:
- Forking a coding thread creates a new conversation bound to a new
  worktree/branch whose tree matches the fork-point state.
- The parent worktree is untouched by the fork.
- The flow degrades safely (documented boundary or snapshot fallback) when the
  project is not a git repository.
- Verification follows the LL13 worktree-agent evidence style plus focused
  fork-point reproduction tests.

Dependencies:
- FORK1 (linkage + chat fork), LL2 (file checkpoints), LL13 (git worktrees).

Next action:
- Gate on FORK1 shipping, then seed a worktree from the fork-point commit or LL2
  checkpoint and bind it to the forked conversation.

### FORK3: Fork Tree Navigation And Compare

Status: `later`

Scope:
- Add a fork-tree view in the drawer, jump-to-parent navigation, and a
  parent-vs-fork comparison.
- Reuse the existing `TurnDiff` rendering for the compare view.

Acceptance criteria:
- The user can see the fork tree, jump to a fork's parent, and compare a fork
  against its parent.
- The compare view reuses existing diff rendering rather than a new diff stack.

Next action:
- Start after FORK1 and FORK2 ship.
