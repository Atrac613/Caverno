---
name: Git commit split
description: Split one commit into focused commits. Read the full diff with `git show <sha>` first — `--stat` only names files and is not enough to group them.
whenToUse: Use when asked to split, divide, or break up a commit, or to separate unrelated changes that were committed together. Read the commit's content before planning anything; do not plan a split from `git show --stat`.
---

# Splitting a commit

## Read the content before anything else

```
git show <sha>
```

Without `--stat`. A summary form (`--stat`, `--name-only`, `--numstat`,
`--name-status`) reports file names and line counts while hiding what changed,
and grouping changes is exactly the decision those forms cannot support. A
turn that only ran `git show --stat` cannot say whether two files belong in the
same commit, so it ends up either guessing or stopping.

If the diff is large, read it in pieces (`git show <sha> -- <path>`) rather than
falling back to a summary.

## Propose the grouping, then confirm

Splitting rewrites history, and how to group is the user's call, not yours.
Once you have read the diff, state the groups you propose and what each commit
message would be, then ask before touching anything. For example:

```
1. chore(flutter): bump FVM pin to 3.47.0
   .fvmrc, .vscode/settings.json, README.md
2. chore(deps): regenerate lockfiles for the new SDK
   pubspec.lock, packages/gs1_grpc/example/pubspec.lock
3. chore(lint): exclude generated platform directories from analysis
   analysis_options.yaml
```

Use `ask_user_question` when the grouping is genuinely ambiguous. Do not create
a branch and hand the rest back with instructions — either do the split after
confirmation, or say plainly that you need the grouping decided first.

## Perform the split

Work on a new branch so the original commit stays reachable:

```
git switch -c <branch> <sha>
git reset --mixed HEAD~1
```

`--mixed` keeps every change in the working tree and unstages it. Do not use
`--hard`: that discards the very changes you are splitting.

Then, for each group in order:

```
git add <paths for this group>
git commit -m "<type>(<scope>): <summary>"
```

Use `git add -p` when one file carries changes belonging to different groups.
After the last group, `git status --short` must be empty — anything left means
a change was dropped from every group.

Use `git_execute_command` for each git write. Chaining git writes inside
`local_execute_command` is rejected, and the whole chain then fails.

## Verify, then report

```
git log --oneline <sha>~1..HEAD
git diff <sha> HEAD
```

The second command must print nothing: the split must preserve the tree
exactly. If it prints anything, a change was lost or altered — fix it before
reporting.

Say what the original branch now points at, and confirm with the user before
moving or resetting it. Leaving the old commit reachable is the safe default.
