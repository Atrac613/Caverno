# RAG2 Batch Git Inventory Replay

Date: 2026-08-26
Status: contract Go; manifest integration not evaluated
Contract: `rag2-batch-git-inventory-contract-v1`

## Outcome

The bounded batch inventory reproduces the frozen per-path collector's typed
state and clean-revision semantics with exactly three Git processes for every
successful non-empty candidate set. Failures stop at the command that supplies
the rejecting evidence. The contract is Go on synthetic repositories only. It
is not connected to the manifest shadow or application, selects no source
scope, changes no limit, and authorizes no storage or retrieval.

## Contract Boundary

`Rag2BatchGitInventoryCollector` is constructed for one explicit
`CodingProject` and accepts no more than the frozen 2,048-file hard ceiling. It
validates every candidate path and rejects empty, duplicate, oversized, or
control-character-bearing candidate sets before Git.

For one valid non-empty set, it runs these shell-free argument arrays once:

1. `git --literal-pathspecs rev-parse --show-toplevel`;
2. `git --literal-pathspecs status --porcelain=v1 -z --untracked-files=all`;
3. `git --literal-pathspecs ls-files --stage -z`.

The first command requires the canonical selected project root to equal the
canonical repository root. The second and third commands return NUL-delimited
repository-wide inventories. The collector parses them completely, intersects
them with the validated bounded candidate set, and derives:

- `cleanTracked` when the path has one stage-zero index entry and no status;
- `modifiedTracked` when a tracked path has a status record;
- `untracked` when an untracked status record has no index entry; and
- a typed rejection for missing, conflicting, duplicated, malformed, or
  inconsistent evidence.

For clean tracked files, the stage-zero index object ID is the same blob the
per-path collector obtains through `HEAD:<path>` when status is clean. Staged
and working-tree changes do not consume that revision; they retain the frozen
working-tree-content semantics.

Each command has a ten-second timeout and a 4 MiB combined stdout/stderr
retention ceiling. Startup failure, timeout, output overflow, non-zero exit,
malformed UTF-8, malformed NUL records, root mismatch, zero clean object IDs,
and unmerged requested paths fail closed.

## Report Safety

The collection retains per-path `Rag2GitEvidence` only in memory for parity and
future adapter evaluation. Its JSON surface contains only:

- schema and contract identifiers;
- Go/No-Go and typed failure reason;
- requested and collected counts;
- the actual command count; and
- aggregate counts for clean tracked, modified tracked, and untracked states.

It omits repository-relative paths, object IDs, project roots, command stdout,
command stderr, and source text.

## Reproducible Evidence

A temporary real Git repository proves one three-command batch matches the
frozen per-path collector for:

- one clean tracked Markdown source and its exact blob revision;
- one modified tracked source;
- one untracked source with a space and Unicode character;
- one staged added source; and
- one staged rename whose target contains a space and Unicode character.

Injected process results additionally prove:

- the exact three repository-wide argument arrays do not vary with candidate
  count or state;
- report JSON contains no path, root, blob, stdout, stderr, or source payload;
- project-root mismatch stops after preflight;
- timeout and output overflow retain command-specific failure reasons;
- malformed status and index output fail closed;
- missing evidence and multi-stage conflict entries fail closed; and
- invalid, duplicate, and 2,049-path requests invoke zero Git commands.

No Caverno live batch was run. The source-scope contract selected no candidate
profile, and the complete 2,819-file snapshot exceeds the frozen hard ceiling.
Using a smaller profile for a live run would prematurely select a scope.

## Process-Cost Finding

The preceding source-scope measurement estimated 2,233-3,349 Git processes for
runtime-only and 3,145-4,717 for runtime plus top-level documentation. This
replay holds the Git process count at three for either in-bound candidate set.
That resolves the process-count question but does not resolve source coverage
or authorize either profile.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_batch_git_inventory_replay_test.dart \
  --test test/tool/rag2_git_evidence_collector_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The five batch tests and the 11-test focused collector subset pass. Project and
package static analysis, notification-relay tests, and all 90 focused RAG2
tests pass.

## Decision and Next Entry Condition

Freeze the three-command protocol, 2,048-candidate bound, timeout/output limits,
NUL parsers, typed state mapping, aggregate-only report, and current synthetic
parity result.

The next slice may replace the opt-in manifest shadow's per-path provider with
this batch inventory behind the existing manifest limits. It must reuse one
source inventory walk, preserve the manifest JSON schema and every selected
source/exclusion decision, prove three Git commands for an in-bound repository,
and prove zero Git commands when discovery limits fail. It must retain the
per-path collector as the frozen parity oracle.

That integration must not select a Caverno source scope, raise limits, add
storage, construct chunks, add retrieval, or enter an application path.
