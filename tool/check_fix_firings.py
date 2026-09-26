#!/usr/bin/env python3
"""Report whether a shipped harness change has actually fired in a session log.

A harness change that only passes its unit tests is unproven: the path it
touches may simply never be reached in real turns. This walks the session-log
corpus for the signature each change leaves behind -- an LL33 transform id
where the change records one, otherwise the prose it put in front of the model
-- and reports, per change, whether it has been observed and how many logs even
ran on a build capable of producing it.

Every hit is qualified by git ancestry, so a signature found in a log from a
build that predates the change is reported as a coincidence rather than as a
confirmation.

Extend SIGNATURES when a change ships. A row is worth adding when the change
leaves a distinctive string in the log; changes whose only evidence is absence
(a notice that stops appearing) do not fit this instrument.

Two corpora are scanned, and kept apart. Real sessions answer "has this fired
in use"; the live canaries under build/integration_test_reports answer the
weaker but distinct question "is this path reachable at all". Merging them would
let a fixture pass for usage; omitting the canaries -- which is what this tool
did until 2026-09-12 -- reports a path as unobserved after a canary has just
proved it, which is how ANA2's closed evidence gap kept reading as open.

Reading a "not yet observed" row, after the 2026-09-13 audit of every one of
them. Three separate things wear that label, and only the first is a problem:

1. **The row cannot fire.** Both instances found were the row's own fault, not
   the code's: one matched a JSON key without the space `json.dumps` puts there,
   and three qualified against a commit that only exists on an unmerged branch,
   so no main-built log could ever count (two of those three had in fact been
   firing in real sessions for twelve days). Check the literal against a real log
   and the commit with `git merge-base --is-ancestor`.
2. **The trigger has never occurred.** `noop_write_notice` is the clean example:
   312 writes are logged across the corpus and not one reports
   `"changed": false`, so the condition, not the notice, is what is missing. Look
   for the *trigger* in the corpus before suspecting the path.
3. **The condition has not co-occurred in one turn.** `saved_validation_final_text`
   needs a printed call in a final-only response after a saved validation
   succeeded; both populations exist in the corpus, and its notifier call site is
   covered by a notifier test, so the wiring is exercised and the ordering simply
   has not happened.

The case that motivated the audit was none of these: ANA3's `accept_task` was
unreachable behind six stacked blocks while its unit tests passed, and what gave
it away was a *canary* that constructed the condition on purpose. When a row with
plenty of eligible logs stays dark and the trigger does appear in the corpus, that
is when to build one.

Usage:
    python3 tool/check_fix_firings.py [--dir LOG_DIR] [--repo REPO]
                                      [--canary-dir DIR] [--no-canaries]

Honors CAVERNO_SESSION_LOG_DIR; defaults to ~/.caverno/session_logs for real
sessions and <repo>/build/integration_test_reports for canary runs. Passing
--dir scans only that directory, as a real-session corpus.
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys

# name -> commit that introduced it, what it does, and the log evidence that
# proves it ran. A row carries exactly one of two evidence keys:
#
#   "match"      receives the whole log serialized as one JSON string. Use it
#                when the only trace a change leaves is prose it put in front
#                of the model.
#   "transform"  names an LL33 post-LLM transform id, read structurally from
#                `turnExit.transforms`. Prefer it whenever the change records
#                one: that is the channel LL33 added so a guard firing is a
#                direct signal instead of an inference from leaked notice
#                prose, and it cannot be fired by a log that merely quotes the
#                notice -- including one produced by reading this repo.
_JSON_STRING = r'"(?:[^"\\]|\\.)*"'
_INTERNAL_GREP_RESULT = re.compile(
    r'\{"command": "grep (?:[^"\\]|\\.)*", "working_directory": ' + _JSON_STRING
    + r', "exit_code": -?\d+, "stdout": ' + _JSON_STRING
    + r', "stderr": ' + _JSON_STRING + r', "executed_internally": true'
)
_GIT_NATIVE_PIPELINE_REFUSAL = re.compile(
    r'"(?:error|errorMessage)": "git_execute_command accepts one git '
    r'subcommand per call and runs without a shell'
)

_TOOL_ARGUMENT_TYPE_REJECTION = re.compile(
    r'"code": "invalid_tool_argument_type"'
)
_ARGUMENT_TRAILING_TEXT_REJECTION = re.compile(r'"trailing_text": "')


def _closer_only_argument_dispatched(blob):
    """Whether a logged tool result ran with an argument that was a JSON
    array or object followed only by closing brackets.

    The decode leaves no marker of its own: the tool result keeps the call's
    original arguments, so the stringified value is still there. A result for
    such a call that is not the type guard's rejection means it was decoded
    and dispatched.
    """
    try:
        entries = json.loads(blob)
    except ValueError:
        return False
    decoder = json.JSONDecoder()
    for entry in entries if isinstance(entries, list) else []:
        request = entry.get("request") if isinstance(entry, dict) else None
        for result in (request or {}).get("toolResults") or []:
            payload = _decoded_result(result.get("result")) or {}
            if payload.get("code") == "invalid_tool_argument_type":
                continue
            for value in (result.get("arguments") or {}).values():
                if not isinstance(value, str):
                    continue
                text = value.strip()
                if not text.startswith(("[", "{")):
                    continue
                try:
                    _, end = decoder.raw_decode(text)
                except ValueError:
                    continue
                rest = text[end:].strip()
                if rest and set(rest) <= set("}] \n\t"):
                    return True
    return False


_ANCHORED_SEARCH_HIT = re.compile(
    r'"query": "\^(?:[^"\\]|\\.)*", "matches": \["'
)
_GIT_ADD_CHANGE_LABEL = re.compile(
    r'"changesSinceCapture": \[(?:"(?:[^"\\]|\\.)*", )*"git add '
)


def _recovery_carries_earlier_results(blob):
    """Whether a loop-limit recovery request held more than the last batch.

    Before 0070aff8f the recovery request carried exactly the batch that had
    just run, so any result id outside the last two responses' tool calls
    (the batch that ran, and the calls left pending at the limit) is the
    carry. Edit-mismatch recovery could already attach an older read_file,
    so a pre-fix build matching this reads as a coincidence, not a firing.
    """
    try:
        entries = json.loads(blob)
    except ValueError:
        return False
    recent_calls = []
    for entry in entries:
        request = entry.get("request") or {}
        messages = request.get("messages") or []
        last = messages[-1].get("content") if messages else None
        if isinstance(last, str) and "bounded tool loop limit" in last:
            sent = {result.get("id") for result in request.get("toolResults") or []}
            ran = set().union(*recent_calls)
            if sent - ran - {None}:
                return True
        calls = (entry.get("response") or {}).get("toolCalls") or []
        if calls:
            recent_calls = (recent_calls + [{call.get("id") for call in calls}])[-2:]
    return False


def _decoded_result(result):
    if isinstance(result, dict):
        return result
    if isinstance(result, str):
        try:
            decoded = json.loads(result)
        except ValueError:
            return None
        return decoded if isinstance(decoded, dict) else None
    return None


def _write_file_content_rejected(blob):
    """Whether a write_file call was answered with the type guard's rejection
    of its content.

    Before 5bfffa75c that call threw in a guard ahead of dispatch and left no
    tool result, so the rejection existing at all is the change firing.
    """
    try:
        entries = json.loads(blob)
    except ValueError:
        return False
    for entry in entries if isinstance(entries, list) else []:
        request = entry.get("request") if isinstance(entry, dict) else None
        for result in (request or {}).get("toolResults") or []:
            if result.get("name") != "write_file":
                continue
            payload = _decoded_result(result.get("result")) or {}
            if (
                payload.get("code") == "invalid_tool_argument_type"
                and payload.get("argument") == "content"
            ):
                return True
    return False


def _refused_commit_then_ran(blob):
    """Whether a commit refused for an unread diff later ran in the same log.

    Before 6ab0621de the refusal was filed as an executed commit, so the
    identical commit re-issued after `diff --cached` was deduplicated and the
    refusal replayed (session dd50d110). Only the declared refusal names its
    origin, and only a later result for the same command carrying an exit
    code is the retry actually running.
    """
    try:
        entries = json.loads(blob)
    except ValueError:
        return False
    refused = set()
    seen = set()
    for entry in entries:
        for result in (entry.get("request") or {}).get("toolResults") or []:
            if result.get("id") in seen or result.get("name") != "git_execute_command":
                continue
            seen.add(result.get("id"))
            command = (result.get("arguments") or {}).get("command")
            payload = _decoded_result(result.get("result")) or {}
            if (
                payload.get("code") == "commit_without_diff_inspection_blocked"
                and payload.get("result_origin") == "refusal"
            ):
                refused.add(command)
            elif command in refused and "exit_code" in payload:
                return True
    return False


def _pending_question_put_to_user(blob):
    """Whether an ask_user_question left at the loop limit reached the user.

    Before 4e482cb4b the limit sent a recovery prompt telling the model not to
    ask for confirmation. Now the pending question runs before finalization,
    so the next streamed request is the tool-less final answer, with no
    loop-limit recovery prompt in between.
    """
    try:
        entries = json.loads(blob)
    except ValueError:
        return False
    streamed = [
        entry
        for entry in entries
        if str(entry.get("operation", "")).startswith("stream")
        and "request" in entry
    ]
    for current, following in zip(streamed, streamed[1:]):
        calls = (current.get("response") or {}).get("toolCalls") or []
        if not any(call.get("name") == "ask_user_question" for call in calls):
            continue
        if following.get("operation") != "streamChatCompletion":
            continue
        messages = (following.get("request") or {}).get("messages") or []
        if not any(
            "bounded tool loop limit" in str(message.get("content", ""))
            for message in messages
        ):
            return True
    return False


SIGNATURES = {
    "failed_read_digest": {
        "commit": "5e7f8ebb",
        "what": "failed read reported as FAILED, not as gathered context",
        "match": lambda s: "— FAILED (" in s,
    },
    "command_exit_status": {
        "commit": "982a1671",
        "what": "command digest line carries its exit status",
        "match": lambda s: "` (exit " in s or "` (last exit " in s,
    },
    "trailing_unchanged_run": {
        "commit": "982a1671",
        "what": "unchanged flagged from the trailing run of inspections",
        "match": lambda s: "(unchanged — the last " in s,
    },
    "abort_notice_shell_work": {
        "commit": "11badd76",
        "what": "abort notice reports commands that ran cleanly",
        "match": lambda s: "Already ran successfully in this turn:" in s,
    },
    "release_approval_token": {
        "commit": "ef6af66d",
        "what": "release approval decided by an issued token, not by wording",
        # The blocked-release payload names the token it issued, and that
        # payload rides into the next request, so the token is the durable
        # trace. The shadow-divergence line is app log only.
        "match": lambda s: "approval token rel-" in s,
    },
    "honest_inspection_digest": {
        "commit": "0265fe04",
        "what": "digest stops claiming inspection output is still readable",
        "match": lambda s: "Inspections already made this turn" in s,
    },
    "mutation_digest_section": {
        "commit": "6ffb9e5ef",
        # Was 99c05391 for twelve days, which is on an unmerged branch: every
        # main-built log failed the ancestry check, so all three rows read
        # "logs on a build that could produce it: 0" and could never be proven.
        # A signature has to qualify against the commit that shipped the string,
        # not the one that wrote it.
        "what": "digest names the files the turn changed",
        "match": lambda s: "Files this turn changed" in s,
    },
    "unchecked_mutation_notice": {
        "commit": "6ffb9e5ef",
        # Was 99c05391 for twelve days, which is on an unmerged branch: every
        # main-built log failed the ancestry check, so all three rows read
        # "logs on a build that could produce it: 0" and could never be proven.
        # A signature has to qualify against the commit that shipped the string,
        # not the one that wrote it.
        "what": "digest says an edit has had no command or check since",
        "match": lambda s: "no command or check has run since" in s,
    },
    "noop_write_notice": {
        "commit": "6ffb9e5ef",
        # Was 99c05391 for twelve days, which is on an unmerged branch: every
        # main-built log failed the ancestry check, so all three rows read
        # "logs on a build that could produce it: 0" and could never be proven.
        # A signature has to qualify against the commit that shipped the string,
        # not the one that wrote it.
        "what": "digest flags a write that changed nothing",
        "match": lambda s: "no-op: the file was already exactly this" in s,
    },
    "blocked_mutation_notice": {
        "commit": "ab994dec",
        "what": "turn that changed no files says so",
        "match": lambda s: "blocked_mutation_notice" in s
        or "File change check: this turn changed no files" in s,
    },
    "anabasis_parent_boundary": {
        "commit": "0e60696e",
        "what": "the Anabasis parent is refused a mutation and delegates instead",
        # Observed 2026-09-04, session 459bd75f: the parent called write_file,
        # read the refusal, and switched to spawn_subagent inside the same
        # request -- no repeat, so the refusal wording needs no work. The child
        # then edited successfully, which is delegation being the parent's only
        # route to effect rather than a restriction on the work.
        "match": lambda s: "anabasis_parent_authority_refused" in s,
    },
    "anabasis_delegation_refused": {
        "commit": "8102fab4",
        "what": "planned delegation names a task the plan does not offer",
        # The refusal half of the admission gate: it proves the queue reached
        # the parent, was consulted, and was answered with something the plan
        # does not currently offer. It does not prove planned work was ever
        # delegated -- anabasis_delegation_admitted below carries that.
        "match": lambda s: "anabasis_delegation_not_ready" in s,
    },
    "anabasis_delegation_admitted": {
        "commit": "8102fab4",
        "what": "a ready saved task is selected and its contract reaches the child",
        # The accepted half, and the one ANA2's standing evidence gap is
        # actually about: a planned parent selecting planned work and handing
        # a child its saved scope. It leaves a trace because the admitted
        # prompt does not stay in the parent -- AnabasisDelegationAdmission
        # appends the contract to the child's prompt, and child requests are
        # logged under usageRole "subagent" like any other request.
        "match": lambda s: "Saved task contract (authoritative scope)" in s,
    },
    "saved_validation_final_text": {
        "commit": "8102fab4",
        "what": "a printed tool call after saved validation is replaced, not run",
        # A final-only response carries no execution authority, so a printed
        # call in it is an action promise nobody kept. Seeing this line means
        # a real turn ended that way and the promise was withdrawn instead of
        # being read as work done.
        "match": lambda s: "The saved validation command succeeded. "
        "No additional tool call was executed." in s,
    },
    "anabasis_acceptance_refused": {
        "commit": "161e784d4",
        "what": "the parent is refused an acceptance and told what is outstanding",
        # The readable half of the acceptance gate, and the one that proves the
        # parent tried. Five codes share this prefix on purpose; matching the
        # shared key rather than one of them means any of the five counts.
        "match": lambda s: '"code":"acceptance_' in s
        or '"code": "acceptance_' in s,
    },
    "anabasis_acceptance_elicited": {
        "commit": "271774739",
        "what": "a settled parent turn is asked to record the judgement it has",
        # The eleventh worktree run had the evidence, had the time, and reported
        # its judgement in prose. The remedy is the update_goal one: a turn whose
        # only available action is the bookkeeping call. The prompt is the
        # durable trace -- a hidden turn's instruction is logged like any other
        # request, and this phrase appears nowhere else.
        "match": lambda s: "Record the judgement now by calling accept_task"
        in s,
    },
    "clarify_required_next_action": {
        "commit": "040ed08db",
        "what": "a plan with an unsettled question asks the model for answers",
        # The counting fix's only real consumer is the prompt. Until the count
        # was derived from the spec, a plan whose questions nobody had opened
        # projected `execute` and listed none of them, so this line could not
        # appear for the case it exists for. `live_open_question_execution` is
        # the scenario that produces it, because no other live plan left a
        # question open.
        "match": lambda s: "Required next action: clarify" in s,
    },
    "acceptance_evidence_in_prompt": {
        "commit": "8f9fd731f",
        "what": "an accepted task tells the next turn what it was accepted on",
        # ANA3 PR 2b's claim is that the judgement stops being something the
        # next turn redoes from the same files, and the prompt said `[accepted]`
        # and nothing else until this line: rationale and evidence were written
        # and read by no production code. Needs an acceptance to exist first, so
        # it trails anabasis_acceptance_recorded by construction.
        "match": lambda s: "accepted on: " in s,
    },
    "anabasis_premise_lapsed": {
        "commit": "447779ef3",
        "what": "an acceptance is barred because a premise is no longer confirmed",
        # ANA2's contradiction policy reaching the moment it decides something.
        # It could not fire before: DelegatedPremiseAudit had no production
        # caller, and mayParentAccept's lapsedPremises was passed only by its
        # own test. Expect this one to stay dark for a while -- it needs a user
        # to decline an assumption a delegated task stood on, which the canaries
        # do not construct. Read it as case 2 in this file's header (the trigger
        # has not occurred), not as case 1.
        "match": lambda s: "acceptance_premise_lapsed" in s,
    },
    "anabasis_acceptance_recorded": {
        "commit": "161e784d4",
        "what": "the parent records a semantic acceptance of a delegated task",
        # ANA3 PR 2b's whole point: the judgement stops being something the
        # next turn has to redo from the same files. The success payload names
        # the task, so this is the durable trace.
        "match": lambda s: '"accepted_task_id"' in s,
    },
    "delegated_results_named": {
        "commit": "0c5b6d756",
        "what": "the parent is told which children are waiting to be judged",
        # The block the parent had to invent ids in place of. Matching the header
        # rather than a child id means an empty list counts too: rendering
        # "- none" is the same fix, and a run where nothing was delegated still
        # proves the block reached a real parent turn.
        "match": lambda s: "Delegated results awaiting your judgement" in s,
    },
    "subagent_task_unknown": {
        "commit": "f59c47e9a",
        "what": "an unknown child id is answered with the ids that exist",
        # The turn-survival rule shipped beside this one leaves no string at all
        # -- its evidence is an abort that does not happen -- so this row is the
        # closest thing to a witness for both: the refusal it names is one of the
        # codes that now keeps a turn alive.
        "match": lambda s: "subagent_task_unknown" in s,
    },
    "policy_refusal_not_approval": {
        "commit": "f6bc075eb",
        "what": "an aborting policy refusal is named as one, not as an approval",
        # The branch that was wrong is the one worth watching. A refusal used to
        # abort with "was blocked by approval ... Approve it manually" and
        # "Reason: null", which sent the reader after a dialog that does not
        # exist and printed null over the refusal's own required_action. Match
        # the new wording rather than the absence of the old: an absence fires
        # on every log that never aborted at all.
        "match": lambda s: "was refused by policy (" in s,
    },
    # "parent_records_its_own_judgement" was registered here on 2026-09-12 and
    # withdrawn the same day, twice wrong. It matched '"name":"accept_task"',
    # which this tool never sees: it serializes each record with json.dumps, so
    # every key reads '"name": "accept_task"' with a space -- the row could not
    # fire at all. (The acceptance_refused row above carries both spellings, so
    # the lesson was already in this file and I did not read it.) Fixing the
    # spacing would have made it worse: the tool *catalog* carries that same
    # key, so it would fire on any log that merely offers accept_task. And the
    # question it asked is already answered: an attempt is recorded
    # (anabasis_acceptance_recorded), refused by the handler
    # (anabasis_acceptance_refused), or refused before it
    # (anabasis_parent_boundary) -- three rows that partition it.
    "material_assumption_confirmation": {
        "commit": "0e60696e",
        "what": "a material contract assumption stops a mutation and is asked about",
        # The refusal is what the guard emits, and it is the half that reaches
        # the log: the answer arrives through an approval, not through a model
        # request. Seeing this code at all means the marks a plan wrote
        # travelled all the way to a refused tool call, which no unit test can
        # establish -- ANA0 measured the model marking assumptions, never a
        # real turn being held by one.
        "match": lambda s: "material_contract_assumption_unconfirmed" in s,
    },
    "lsp_definition_tool_offered": {
        "commit": "6259e77f1",
        "what": "the symbol-navigation tool reaches the model's tool list",
        # Deliberately the tool-catalog key that the withdrawn
        # parent_records_its_own_judgement row above was rejected for matching.
        # There the catalog contaminated the question, because what was being
        # asked was whether the parent *used* accept_task. Here being offered
        # at all IS the fix: lsp_go_to_definition had a definition but no
        # BuiltInToolInfo entry, so the initial tool-search selection dropped
        # it from 2026-06-19 until this commit. Before it, the string appears
        # in 1 of 158 logs, and that one is a personal-eval replay fixture
        # built long before the fix, so ancestry reports it as the coincidence
        # it is. Verified against both: the fixture matches, session c79826af
        # does not, and the Dart sources spell the key with single quotes so a
        # read_file or search_files of this repo cannot fire it.
        #
        # This row says the tool is on offer. It does NOT say the model chose
        # to call it -- that is a separate question and needs its own row keyed
        # on a lookup result, not on the name.
        "match": lambda s: '"name": "lsp_go_to_definition"' in s,
    },
    "pending_action_length_recovery": {
        "commit": "7284c8f86",
        "what": "a turn cut off before it acted on anything is resumed",
        # The first row keyed on a transform rather than on prose, and the
        # reason the key exists. PendingActionLengthRecoveryPolicy shipped long
        # before it could fire: its gate read the finish reason recorded for
        # the turn, which the regenerated answer's `stop` had already
        # overwritten (3d1671b1b), and then still required incomplete evidence
        # that a turn which had only *looked* at things could not leave behind
        # (7284c8f86). Both commit bodies say "still unverified live", because
        # the check they name is an app-log line this instrument cannot read.
        #
        # It fired the same day it became reachable: session 63d9042e, build
        # 7284c8f86 -- the very commit -- carries the whole chain in one
        # turnExit, pending_action_length_recovery ->
        # coding_continuation_recovery_length_truncated_pending_action, and the
        # turn exits on pending_batch_executed. A truncated turn resumed and
        # ran tools, which is the claim the policy exists to make.
        "transform": "pending_action_length_recovery",
    },
    "skill_carried_past_its_turn": {
        "commit": "73cc602d7",
        "what": "the skill a turn works from is repeated into that turn",
        # A load_skill result lives for exactly the turn that produced it.
        # Session fd153d88 is the cost: the skill was loaded in turn 2, the
        # write it governed happened in turn 4, and from turn 3 the request
        # carried only the skill's *name* -- the index -- so the notes went to
        # the repository root against a convention the skill states.
        #
        # Keyed on the prompt rather than on a transform, because nothing is
        # transformed: the carry is context the request now holds. The literal
        # spans the two adjacent string literals the builder concatenates, so
        # no source spells it contiguously and reading the repository cannot
        # fire it -- the builder's test pins it the same way, split, for that
        # reason. This file is the sole exception, as it is for every row here:
        # an instrument has to spell what it looks for.
        #
        # be857297 shipped the builder and could not fire; 73cc602d7 is the
        # wiring, which is what makes the row reachable at all.
        "match": lambda s: "here because a tool result" in s,
    },
    "read_carry_across_file_write": {
        "commit": "67009e4c7",
        "what": "earlier reads carried across a file write, labelled with it",
        # The key exists only on a carried result that predates a write. Unlike
        # prose it is matched as a real JSON key: json.dumps escapes the quotes
        # of the same text inside a tool result, so reading this repository
        # cannot fire it.
        "match": lambda s: '"changesSinceCapture": [' in s,
    },
    "internal_grep": {
        "commit": "da23ce7b4",
        "what": "grep answered by the internal executor, not a SEC4.4g prompt",
        # Before this commit a grep result could only come from the shell, so
        # a structured tool result pairing a grep command with
        # executed_internally is the change itself. Matched on the decoded
        # result object: the same text inside a tool-result string is
        # escaped by json.dumps, so quoting it cannot fire the row.
        "match": lambda s: _INTERNAL_GREP_RESULT.search(s) is not None,
    },
    "git_native_pipeline_refusal": {
        "commit": "44f774e71",
        "what": "git pipeline refusal leads with git-native options, not a shell",
        # Whether this matters is the follow-up question: after the refusal,
        # did the model switch to rev-list --count / -n / --format, or fall
        # through to local_execute_command and a SEC4.4g prompt? Matched as a
        # real JSON key on the decoded result, so reading git_tools.dart,
        # where the text is a single-quoted Dart literal split across lines,
        # cannot fire it.
        "match": lambda s: _GIT_NATIVE_PIPELINE_REFUSAL.search(s) is not None,
    },
    "tool_argument_type_guard": {
        "commit": "e2ccdcfb4",
        "what": "mistyped built-in tool argument returned as a failure, not a throw",
        # Before this commit the same call threw and ended the turn, leaving
        # no tool result at all, so the structured code is the change itself.
        # Matched as a real JSON key on the decoded result; the Dart source
        # spells it with single quotes and quoted text is escaped.
        "match": lambda s: _TOOL_ARGUMENT_TYPE_REJECTION.search(s) is not None,
    },
    "write_file_content_type_rejection": {
        "commit": "5bfffa75c",
        "what": "write_file content object rejected as a tool result, not a dispatch error",
        # The tool_argument_type_guard row above matches any rejection, so an
        # ask_user_question rejection reported it fired while this path, the
        # one it was built for, still threw. Read structurally.
        "match": _write_file_content_rejected,
    },
    "argument_trailing_closer_decode": {
        "commit": "8e38cc36e",
        "what": "stringified array/object ending in a stray closer is decoded and dispatched",
        # Session b41b57fa: options as "[...]}" was rejected three times and
        # the turn aborted. The success branch has no marker, so it is read
        # structurally from the tool result's original arguments.
        "match": _closer_only_argument_dispatched,
    },
    "argument_trailing_text_rejection": {
        "commit": "8e38cc36e",
        "what": "type-guard rejection names the text after a complete JSON value",
        # The rejection branch of the same change: the rest of the arguments
        # object written inside options. Matched as a real JSON key on the
        # decoded result; the Dart source spells it with single quotes.
        "match": lambda s: _ARGUMENT_TRAILING_TEXT_REJECTION.search(s)
        is not None,
    },
    "search_files_line_anchor": {
        "commit": "a92ece3e3",
        "what": "anchored search_files query (e.g. ^version:) finds its line",
        # Before this commit an anchored query matched only lines containing
        # the caret literally, which no corpus query ever did (66 of 66 came
        # back empty), so a decoded result pairing a ^-query with a non-empty
        # match list is the change firing.
        "match": lambda s: _ANCHORED_SEARCH_HIT.search(s) is not None,
    },
    "carry_across_git_add": {
        "commit": "93819b505",
        "what": "reads carried past git add, labelled with it",
        # The label exists only because of this change: before it, git add
        # ended the carry, so no carried result could name one. Matched as the
        # real JSON key on a logged tool result, so quoted text cannot fire it.
        "match": lambda s: _GIT_ADD_CHANGE_LABEL.search(s) is not None,
    },
    "loop_limit_recovery_carry": {
        "commit": "0070aff8f",
        "what": "loop-limit recovery request carries earlier results, not the last batch alone",
        "match": _recovery_carries_earlier_results,
    },
    "guard_refusal_not_executed": {
        "commit": "6ab0621de",
        "what": "commit refused for an unread diff runs once the diff is read",
        "match": _refused_commit_then_ran,
    },
    "loop_limit_question_to_user": {
        "commit": "4e482cb4b",
        "what": "ask_user_question pending at the loop limit reaches the user",
        "match": _pending_question_put_to_user,
    },
}

for _name, _signature in SIGNATURES.items():
    # A row carrying neither key, or both, is the failure this instrument is
    # least able to report: it goes dark and reads as "the code never ran".
    if ("match" in _signature) == ("transform" in _signature):
        raise SystemExit(
            f"signature {_name} must carry exactly one of match/transform"
        )

_ANCESTRY_CACHE = {}


def build_contains(commit, fix_commit, repo):
    """Whether the build at `commit` contains `fix_commit`, per git ancestry.

    Asking git rather than inferring an order from the logs: a change that
    never shipped as a build of its own never appears as a build commit, and
    any ordering guessed from log appearance sorts it last -- which reads as
    "no log could contain it" for changes that are in fact running.

    Returns None when either commit is unknown to the repo, which must be
    reported as unknown rather than folded into either verdict.
    """
    key = (commit, fix_commit)
    if key in _ANCESTRY_CACHE:
        return _ANCESTRY_CACHE[key]
    verdict = None
    try:
        for ref in (commit, fix_commit):
            if subprocess.run(
                ["git", "-C", repo, "cat-file", "-e", f"{ref}^{{commit}}"],
                capture_output=True,
            ).returncode != 0:
                _ANCESTRY_CACHE[key] = None
                return None
        verdict = (
            subprocess.run(
                [
                    "git",
                    "-C",
                    repo,
                    "merge-base",
                    "--is-ancestor",
                    fix_commit,
                    commit,
                ],
                capture_output=True,
            ).returncode
            == 0
        )
    except OSError:
        verdict = None
    _ANCESTRY_CACHE[key] = verdict
    return verdict


def turn_exit_transforms(entries):
    """Every LL33 post-LLM transform id this log recorded.

    Read structurally from `turnExit.transforms` rather than from the
    serialized blob. Python's `json.dumps` separators are not the Dart
    writer's, so a literal tuned to one spelling silently never matches the
    other -- which is the first of the three faults the 2026-09-13 audit found
    behind a "not yet observed" row.
    """
    found = set()
    for entry in entries:
        turn_exit = entry.get("turnExit")
        if not isinstance(turn_exit, dict):
            continue
        for transform in turn_exit.get("transforms") or ():
            if isinstance(transform, str):
                found.add(transform)
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dir",
        default=os.path.expanduser(
            os.environ.get("CAVERNO_SESSION_LOG_DIR", "~/.caverno/session_logs")
        ),
    )
    parser.add_argument("--repo", default=os.getcwd())
    parser.add_argument(
        "--canary-dir",
        default=None,
        help="Live canary report root (default: <repo>/build/integration_test_reports).",
    )
    parser.add_argument(
        "--no-canaries",
        action="store_true",
        help="Scan real sessions only.",
    )
    args = parser.parse_args()

    # An explicit --dir means "scan exactly this", which is what the canary
    # runners pass to judge one run in isolation.
    explicit_dir = any(arg.startswith("--dir") for arg in sys.argv[1:])
    roots = [(args.dir, "wild")]
    if not args.no_canaries and not explicit_dir:
        canary_dir = args.canary_dir or os.path.join(
            args.repo, "build", "integration_test_reports"
        )
        if os.path.isdir(canary_dir):
            roots.append((canary_dir, "canary"))

    logs = []
    for root, origin in roots:
        for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
            logs.append((path, origin))
    logs.sort(key=lambda row: os.path.getmtime(row[0]))
    if not logs:
        print(f"no session logs under {args.dir}", file=sys.stderr)
        return 1

    hits = {name: [] for name in SIGNATURES}
    eligible = {name: 0 for name in SIGNATURES}

    for path, origin in logs:
        try:
            with open(path, encoding="utf-8") as handle:
                entries = [json.loads(line) for line in handle if line.strip()]
        except (OSError, ValueError):
            continue
        if not entries:
            continue
        # Grounded only: a log carrying no real LLM exchange proves nothing.
        if not any("request" in e and "response" in e for e in entries):
            continue
        commit = entries[0].get("build", {}).get("commit", "?")
        blob = json.dumps(entries, ensure_ascii=False)
        transforms = turn_exit_transforms(entries)
        for name, signature in SIGNATURES.items():
            could = build_contains(commit, signature["commit"], args.repo)
            if could:
                eligible[name] += 1
            matched = (
                signature["transform"] in transforms
                if "transform" in signature
                else signature["match"](blob)
            )
            if matched:
                hits[name].append(
                    (os.path.basename(path)[:8], commit, could, origin)
                )

    scanned = ", ".join(
        f"{sum(1 for _, o in logs if o == origin)} {origin}"
        for _, origin in roots
    )
    print(f"scanned {len(logs)} logs ({scanned})\n")
    unproven = 0
    for name, signature in SIGNATURES.items():
        rows = hits[name]
        confirmed = [row for row in rows if row[2] is True]
        wild = [row for row in confirmed if row[3] == "wild"]
        canary = [row for row in confirmed if row[3] == "canary"]
        stale = [row for row in rows if row[2] is False]
        unknown = [row for row in rows if row[2] is None]
        if not wild:
            unproven += 1
        # Three verdicts, because "reachable" and "used" are different claims
        # and only the first is what a canary can establish.
        if wild:
            verdict = "FIRED"
        elif canary:
            verdict = "FIRED (canary only)"
        else:
            verdict = "not yet observed"
        print(f"[{verdict}] {name}  ({signature['commit']})")
        print(f"    {signature['what']}")
        print(f"    logs on a build that could produce it: {eligible[name]}")
        for log, commit, _, origin in confirmed:
            print(f"    confirmed: {log} (build {commit}, {origin})")
        for log, commit, _, _origin in stale:
            print(
                f"    IGNORED: {log} (build {commit} predates it — the "
                f"signature is a coincidence, not a confirmation)"
            )
        for log, commit, _, _origin in unknown:
            print(f"    UNKNOWN BUILD: {log} (build {commit} not in this repo)")
        print()

    canary_only = sum(
        1
        for name in SIGNATURES
        if not [r for r in hits[name] if r[2] is True and r[3] == "wild"]
        and [r for r in hits[name] if r[2] is True and r[3] == "canary"]
    )
    print(f"{len(SIGNATURES) - unproven}/{len(SIGNATURES)} observed in the wild")
    if canary_only:
        print(f"{canary_only} more proved reachable by a canary only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
