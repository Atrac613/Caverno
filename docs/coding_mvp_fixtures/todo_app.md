# CMVP-1 · TODO app

Difficulty: **Starter** · Core skill: CRUD + local persistence + a runnable CLI

The canonical fixture. Small enough to always finish, but it still forces the
model to make and follow through on real decisions: a data model, persistence,
and a usable command surface. Most "looks done but isn't" failures show up here
as tasks that vanish after the program exits.

## Brief

> Build a small command-line TODO app. I want to add tasks, see my list, mark a
> task done, and delete one. My tasks should still be there the next time I run
> it. Keep it to one simple program I can run in a terminal.

## Scope

In scope:

- Add, list, complete, and delete tasks from the command line.
- Persist tasks between runs to a local file.
- A short usage/help message.

Out of scope:

- Due dates, priorities, tags, sub-tasks.
- Any GUI, web server, or database engine.
- Multi-user or sync.

## Functional requirements

1. `add <text>` appends a new task with an unfinished state and prints the
   created task (including a stable id).
2. `list` prints all tasks with their id and a done/undone marker; an empty list
   prints a friendly "no tasks" message, not a blank line or an error.
3. `done <id>` marks the task complete; an unknown id prints a clear error and
   exits non-zero.
4. `delete <id>` removes the task; an unknown id prints a clear error and exits
   non-zero.
5. State persists to a local file (e.g. JSON) created on first write; a missing
   or empty file is treated as an empty list, not a crash.
6. Running with no arguments (or `help`) prints usage.

## Acceptance criteria

- [ ] Adding two tasks then listing shows both, each with a distinct id.
- [ ] `done` on an existing id makes that task show as completed in the next
      `list`; the other task stays undone.
- [ ] `delete` on an existing id removes only that task.
- [ ] After completing/deleting, a *fresh process run* of `list` reflects the
      change — state survived process exit (this is the criterion models miss).
- [ ] Unknown id for `done`/`delete` produces a clear message and a non-zero
      exit code, not a stack trace.
- [ ] First-ever run (no state file yet) does not crash.
- [ ] No feature outside the scope list was added.

## Suggested verification

Language-neutral behavioral walk-through (adapt the invocation to the chosen
stack):

```bash
# fresh dir, no state file
<run> add "buy milk"        # -> prints a task with an id, e.g. 1
<run> add "write report"    # -> id 2
<run> list                  # -> both tasks, both undone
<run> done 1
<run> list                  # -> task 1 done, task 2 undone
# NEW process — proves persistence, not in-memory state:
<run> list                  # -> task 1 still done
<run> delete 2
<run> list                  # -> only task 1 remains
<run> done 999; echo "exit=$?"   # -> clear error, exit non-zero
```

If the model wrote tests, run them too, but the persistence criterion must be
checked across *separate process invocations* — an in-process test can pass while
real persistence is broken.

## Common failure modes

- **In-memory only**: full CRUD works within one run but nothing is saved, so a
  second run starts empty. The single most common "as intended" miss here.
- **Completion claimed while broken**: model says the app is done without ever
  running it; `list` on a fresh dir crashes on the missing state file.
- **Silent unknown-id**: `done 999` is a no-op that exits 0 instead of erroring.
- **Scope creep**: due dates, priorities, or a whole web UI appear unrequested,
  turning a starter MVP into something that no longer fits the tool loop.
- **Non-stable ids**: ids are list indexes that shift after a delete, so a later
  `done <id>` hits the wrong task.
