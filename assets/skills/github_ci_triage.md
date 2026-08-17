---
name: GitHub CI failure triage
description: Find and fix a failing CI check on a pull request with the gh CLI. Never fetch a GitHub URL with http_get or search_web — use gh.
whenToUse: Use when asked to fix a failing CI check, a red build, or a failing GitHub Actions run, including when the request is just a PR URL. Reach for gh immediately; do not open the URL with http_get or search the web for it.
---

# Triaging a failing CI check

## Start with gh, never with the web

`http_get` on a private pull request returns a 404 login page, which adds
untrusted remote content to the turn and causes later shell and git actions to
be denied. `search_web` cannot see a private PR. Use `gh` as the first action.

## The path to the error is three commands, not a search

Run them in order and stop as soon as you have the failing step's output.

```
gh pr checks <number> --repo <owner>/<repo>
```

This prints each check with its state and a run URL. Take the run id and job id
from the URL of the failing row
(`.../actions/runs/<run-id>/job/<job-id>`), then:

```
gh run view <run-id> --repo <owner>/<repo> --job <job-id> --log-failed
```

`--log-failed` prints only the failing step. Use the full `--log` only when
`--log-failed` is empty — a full job log can be tens of thousands of tokens.

You now have the error. **Do not run these commands again.** Their output does
not change between attempts, and re-issuing them with a reworded reason costs a
full round trip while telling you nothing new. If you need a detail you already
fetched, re-read it from the earlier tool result.

## Stop investigating and start fixing

Once the failing step's output names a cause, move to the fix. Continuing to
inspect the PR after the cause is known is the single most common way this task
is wasted.

Classify the cause, then act:

- **Dependency resolution** (`pub get` fails, "version solving failed",
  "depends on X ^1.0.0"): the conflict is between constraints in
  `pubspec.yaml` files. Read them, identify the incompatible pair named in the
  error, and adjust or pin the constraint. For a Dependabot PR this usually
  means the bumped package is not yet compatible; say so plainly if the fix is
  to wait rather than to patch.
- **Analyze/lint** (`flutter analyze`, lint rule ids): fix each reported file
  and line, then re-run the same command locally to confirm.
- **Test failure**: read the failing test name and assertion from the log, fix
  the code or the test, then re-run just that test file.
- **Build/toolchain** (SDK version, missing platform): compare the workflow
  file under `.github/workflows/` against the local toolchain version.

## Verify before reporting

Re-run the same command CI ran, locally, and read its exit status. Report the
cause, what you changed, and the local verification result. If you did not
change a file, say that no fix was applied and why — never describe an
investigation as a fix.
