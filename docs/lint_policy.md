# Lint policy

`analysis_options.yaml` extends `package:flutter_lints`, which is deliberately a
minimal set — it leaves out most rules that catch real defects or enforce
mechanical consistency. This document records which extra rules Caverno turned
on, which it rejected, and why, so the next person does not re-litigate the
same measurements.

Every rule below was measured across the whole repository before being adopted:
enable it alone, count the violations, then check whether `dart fix` resolves
them. Rules that would have landed a large manual backlog, changed behaviour, or
contradicted an existing project convention were rejected with the evidence
kept here.

## Adopted

### Already satisfied — pure regression guards

Zero violations at adoption, so they cost nothing today and stop the pattern
from appearing tomorrow.

| Rule | Violations |
| --- | --- |
| `avoid_returning_null_for_void` | 0 |
| `avoid_type_to_string` | 0 |
| `literal_only_boolean_expressions` | 0 |
| `prefer_final_in_for_each` | 0 |
| `sized_box_shrink_expand` | 0 |
| `test_types_in_equals` | 0 |
| `throw_in_finally` | 0 |

### Mechanical consistency — fixed by `dart fix`

| Rule | Violations fixed |
| --- | --- |
| `directives_ordering` | 742 |
| `unnecessary_lambdas` | 77 |
| `type_annotate_public_apis` | 61 |
| `unnecessary_parenthesis` | 33 |
| `prefer_single_quotes` | 23 |
| `use_decorated_box` | 19 |
| `always_declare_return_types` | 2 |
| `use_colored_box` | 2 |
| `combinators_ordering` | 1 |
| `prefer_relative_imports` | 1 |
| `unnecessary_await_in_return` | 1 |

`directives_ordering` is the rule that motivated this pass: a misplaced import
in a review was caught by eye, not by tooling, because nothing enforced order.

## Rejected, with evidence

### `prefer_const_constructors` / `prefer_const_declarations` / `prefer_const_literals_to_create_immutables`

**Changes runtime behaviour.** `const` instances are canonicalized, so two
structurally identical values become `identical`. Applying the fix rewrote

```dart
BrowserSessionEpochSnapshot _sessionEpoch = BrowserSessionEpochSnapshot._(0);
```

to a `const` initializer, which made the coordinator's own snapshot identical to
any foreign snapshot carrying the same epoch. `BrowserSessionOwnershipCoordinator`
then accepted a foreign session where it previously returned `staleSession` —
a silent ownership defect that only the existing test caught.

367 violations. Const construction is still the cheapest Flutter rebuild win, so
this is worth revisiting — but per hunk, by hand, not as a sweep.

### `prefer_void_to_null`

**Does not compile.** Rewrote `Null _fail(...)` to `void _fail(...)` in
`embeddings_client.dart`, where the `Null` return type is deliberate so that
`return _fail(...)` satisfies a `Future<EmbeddingsResult?>` signature. 1
violation, 3 compile errors.

### `unnecessary_raw_strings`

Converts `r'...'` regex literals with no current escapes into ordinary strings.
Correct today, a trap tomorrow: the next `\d` added to such a pattern breaks
silently. 147 violations, all in regex-adjacent code.

### `omit_local_variable_types`

Contradicts the project convention of explicit type annotations over inference.
46 violations.

### `use_late_for_private_fields_and_variables`

Contradicts the project convention of keeping `late` to a minimum. 2 violations.

### `avoid_catching_errors`

The log sinks and audit trail deliberately catch `Object` so that logging can
never become a second failure. 21 violations, all intentional.

### `public_member_api_docs`

14,944 violations. Not actionable.

### `avoid_redundant_argument_values`

912 violations, and removing an explicitly-passed default often removes the
reader's only signal that the value was considered. Deferred.

## Deferred — valuable, needs manual work

| Rule | Violations | Note |
| --- | --- | --- |
| `avoid_dynamic_calls` | 203 | Real crash class; no auto-fix |
| `discarded_futures` | 158 | Overlaps `unawaited_futures`; noisy in tests |
| `no_adjacent_strings_in_list` | 113 | Mostly intentional message tables |
| `only_throw_errors` | 89 | Needs a per-site decision |
| `avoid_slow_async_io` | 70 | Worth doing; audit each call |
| `sort_constructors_first` | 154 | Moves large blocks; hurts `git blame` and pushes files past the size ratchet |
| `sort_unnamed_constructors_first` | 44 | Same as above |
| `close_sinks` | 21 | Directly relevant to past subscription-leak defects |
| `unawaited_futures` | 22 | |
| `join_return_with_assignment` | 8 | |
| `use_string_buffers` | 4 | |
| `use_named_constants` | 3 | |
| `cancel_subscriptions` | 2 | Directly relevant to past subscription-leak defects |
| `unnecessary_statements` | 2 | |

## Rules for running the fixes

1. **Never run bare `dart fix --apply`.** It applies every available fix, not
   just the rules this project enabled. Doing so removed a constructor
   parameter that `unused_element_parameter` wrongly believed unused — it was
   used by a redirecting constructor — and broke two files. Always pass
   `--code=<rule>`.
2. **Apply one rule at a time and analyze in between**, so any breakage is
   attributable to a single rule rather than to a 1,600-fix batch.
3. **Re-run `dart fix` until it converges.** Fixes cascade: `unnecessary_lambdas`
   turned a typed lambda into a tear-off, which made an import unused, which
   then needed `--code=unused_import`.
4. **`tool/fixtures/**` is excluded from analysis.** Those are frozen evaluation
   corpora whose content hash the rag2 extraction eval tests assert. A quote-style
   rewrite there invalidates the fixture instead of improving it.
