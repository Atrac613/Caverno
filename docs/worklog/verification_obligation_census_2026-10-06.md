# Verification obligation census (2026-10-06)

## Question

A failed command blocks a coding turn unless an allowlist
(`VerificationMetadataQueryPolicy`, `LiteralEnvironmentInspectionPolicy`)
proves it a probe. Four Watcher farm sessions in a row (1afd70a6, d27e7528,
016d4d5e, 64bbc516) had a finished subtask rejected because a new probe shape
missed that allowlist and the repair recovery then demanded the probe pass.

The proposal measured here inverts the default for completion evidence: a
failed command becomes an obligation only when it exercised the project. That
means a test runner, a build or analyzer, a project file, an inline program
that imports a project module or reads a project file, or a request to a local
server.

## Method

`tool/verification_obligation_census.py` reads the coding corpus
(`~/.caverno/session_logs/coding`, 134 grounded logs), deduplicates tool
results by id, and parses payloads. It collects:

- every command a repair recovery demanded (`capturedEvidence.unresolvedVerification`);
- every project subtask "rejected by the harness", with the finished turn's
  last demand;
- every distinct failed command execution, refusals and harness results
  excluded.

Each command is classified by a prototype of the proposed rule. The prototype
was corrected twice against what it misread. It had counted version probes as
test runs and missed inline programs that check `LOGGING.md`. It had also read
`-m pip` and `.venv/bin/pip` as project code.

The failed commands were then run through the current Dart
`CommandVerificationReconciliation.isVerification`, with every fix on
`fix/pytest-never-started-verification` through 377a05601, to compare the two
rules.

## Results

Repair demands: 19 distinct commands. 12 exercised the project and 7 were
observations. Six of the seven are probe shapes that later fixes already
recognise (2b1f450d6, 0a9fd4fcf, 377a05601, and a4d9f490a's version probes).
The remaining one is 64bbc516's breakdown of a probe,
`echo "== part 1 =="; ls -a; echo "exit=$?" ...`, which the model wrote only
because the probe had been demanded.

Harness rejections: 6. Three were caused by an observation demand, all of them
probe shapes now fixed. The other three had other causes, each fixed separately:
pytest launch failures (077816251), phantom guardrail diagnostics (502fd597f),
and a brace in a claim notice (bc0d018f8).

Failed commands, current rule against the proposal (149 distinct):

| current \ proposed | exercised the project | observation |
|---|---|---|
| verification | 99 | 1 |
| not verification | 16 | 33 |

- The proposal would stop counting one failure: the 64bbc516 breakdown.
- It would start counting 16. Eleven of them are `bash tool/release_ios_macos.sh`
  runs, which are release actions, not checks, and which have their own gates.
  The other five are arguably real checks that the current rule misses:
  - `pytest ... && python3 - <<'EOF'` heredoc chains (3), which the classifier
    rates as a workspace mutation;
  - `rm -f watcher.log && python watcher.py --dry-run`;
  - `pip install ...; python3 -m pytest -q`.

## Decision

Do not invert the default. Against this corpus it would remove one obligation,
and that one only arose from a probe that is already fixed. It would add eleven
wrong ones. Its "exercised the project" test (interpreter plus relative path,
imports, quoted file names) is no less lexical than the allowlist it would
replace.

Keep adding probe shapes when a log shows one, and rerun this census to see
whether the allowlist still covers the corpus.

## Open

- A pytest run chained with a heredoc check is not treated as a verification at
  all, so a failing heredoc assertion does not block completion. 64bbc516 rec 52
  failed this way. The same check later passed on its own, so no harm was seen
  yet.

## Rerun

```bash
python3 tool/verification_obligation_census.py --json build/verification_obligation_census.json
```

The comparison with the current Dart rule needs a scratch test that loads the
JSON and calls `CommandVerificationReconciliation.isVerification` on each
failure.
