---
name: GitHub PR conflict resolution
description: Resolve merge conflicts on a pull request with the gh CLI. Never fetch a GitHub URL with http_get or search_web — use gh.
whenToUse: Use when asked to fix conflicts, rebase, or update the branch of a GitHub pull request, including when the request is just a PR URL. Reach for gh immediately; do not open the URL with http_get or search the web for it.
---

# Resolving conflicts on a pull request

## Start with gh, never with the web

A pull request URL is not a web page to fetch. `http_get` on a private
repository returns a 404 login page, which adds untrusted remote content to the
turn and causes later shell and git actions to be denied. `search_web` cannot
see a private PR either.

The first action is always `gh`:

```
gh pr view <number> --repo <owner>/<repo> --json number,title,state,headRefName,baseRefName,mergeable,url
```

`mergeable` tells you whether a conflict actually exists before you touch
anything.

## Choose one of two strategies, and stay in it

**A. Server-side update (preferred when the PR just needs the base merged in).**

```
gh pr update-branch <number> --repo <owner>/<repo> --rebase
```

GitHub rewrites the branch on the remote. Your local clone is now **behind and
holding the old commits**. If you intend to keep working locally afterwards,
you must re-sync before doing anything else:

```
gh pr checkout <number>
```

Never push a local branch you have not re-synced after a server-side update.
That push discards the rebase GitHub just performed.

**B. Local resolution (required when files genuinely conflict).**

```
gh pr checkout <number>
git fetch origin <base-branch>
git rebase origin/<base-branch>
```

Resolve each conflicted file, `git add` it, then `git rebase --continue`.

## Pushing the result

Use `git_execute_command` for every git write. Chaining a git write inside
`local_execute_command` (for example `gh pr checkout 1 && git push ...`) is
rejected and the whole chain, including the `gh` part, does not run.

A rebase rewrites history, so the push needs force. Before forcing, confirm the
remote holds nothing you would discard:

```
git log --oneline origin/<branch>..HEAD
git log --oneline HEAD..origin/<branch>
```

If the second command prints anything, **stop**: those commits would be
destroyed. Integrate them first. Running a bare `git fetch` and retrying
`--force-with-lease` does not make this safe — fetching only refreshes the
lease reference while the commits stay discarded.

When the second command is empty:

```
git push --force-with-lease origin HEAD:<branch>
```

## Report honestly

Read the push output before claiming anything. `+ old...new (forced update)`
where `new` is an *older* commit than `old` means you reverted the branch, not
that you resolved the conflict. Verify with `gh pr view <number> --json
mergeable` and say plainly if the conflict is still there.
