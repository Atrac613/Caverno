import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// LL36 structural enforcement: a lexical guard may trigger, it may not judge.
///
/// The guards below extract a *claim* from prose. That is a heuristic, and no
/// heuristic is allowed to decide terminal state — goal status, workflow task
/// completion, or a validation verdict. The roadmap asks for this to be
/// enforced "by the type/API shape, not by convention", so this test checks the
/// one thing Dart makes structural: **reachability through imports**. A guard
/// that cannot see `ConversationWorkflowTaskStatus` cannot set it, and no
/// review discipline is required to keep it that way.
///
/// The check is transitive. A direct-import check would have passed while
/// `CodingVerificationClaimGuard` reached the workflow entities through
/// `CodingVerificationFeedbackService` — which is exactly the drift this is
/// meant to catch, and is why the shared tool name now lives in
/// `coding_verification_evidence_contract.dart`.
///
/// **This list is deliberately not exhaustive over the codebase.** The two
/// prose inferences (`ConversationExecutionProgressInference`,
/// `ConversationGoalProgressInference`) legitimately produce terminal verdicts
/// as the documented fallback for when no mechanical evidence exists, and are
/// therefore not listed here. Their removal is gated on LL35's confirmation
/// rung existing to replace them — see
/// `docs/validation_status_three_paths_2026-07-22.md`.
const _advisoryOnlyGuards = <String>[
  'lib/features/chat/domain/services/analysis_options_lint_edit_guard.dart',
  'lib/features/chat/domain/services/coding_command_output_guardrail_service.dart',
  'lib/features/chat/domain/services/coding_verification_claim_guard.dart',
  'lib/features/chat/domain/services/final_answer_claim_detector.dart',
  'lib/features/chat/domain/services/narrated_transcript_claim_guard.dart',
  'lib/features/chat/domain/services/structured_coding_execution_deferral_detector.dart',
  'lib/features/chat/domain/services/unwritten_file_claim_guard.dart',
  'lib/features/chat/domain/services/workflow_tool_result_failure_detector.dart',
];

/// Libraries that define or persist terminal state. Reaching any of these from
/// a guard means the guard *could* set a verdict.
const _terminalStateLibraries = <String>[
  'lib/features/chat/domain/entities/conversation_workflow.dart',
  'lib/features/chat/domain/entities/conversation_goal.dart',
  'lib/features/chat/domain/entities/conversation.dart',
];

/// Symbols that decide terminal state, checked against the guard sources
/// themselves. Import reachability is the structural half; this catches a guard
/// that reintroduces a verdict by re-declaring the enum values as strings.
const _terminalStateSymbols = <String>[
  'ConversationWorkflowTaskStatus',
  'ConversationGoalStatus',
  'ConversationExecutionValidationStatus',
  'updateCurrentExecutionTaskProgress',
  'recordCurrentVerificationGeneration',
];

final RegExp _relativeImport = RegExp(r"^import\s+'([^':]+)';", multiLine: true);

/// Absolute, **normalized** paths reachable from [entryPath] through relative
/// imports.
///
/// Normalization is load-bearing, not tidiness: a relative import resolves to
/// `.../domain/services/../entities/conversation_workflow.dart`, which does not
/// end with `domain/entities/conversation_workflow.dart`. Without `p.normalize`
/// this function returns the leaking path and the caller's suffix match still
/// reports clean — the exact false pass this test was written to prevent, and
/// one it did produce on its first run.
Set<String> _transitiveImports(String entryPath) {
  final visited = <String>{};
  final pending = <String>[p.normalize(File(entryPath).absolute.path)];

  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!visited.add(current)) {
      continue;
    }
    final file = File(current);
    if (!file.existsSync()) {
      continue;
    }
    for (final match in _relativeImport.allMatches(file.readAsStringSync())) {
      // `dart:` and `package:` are excluded by the pattern's `[^':]+`.
      pending.add(p.normalize(p.join(file.parent.path, match.group(1)!)));
    }
  }
  return visited;
}

void main() {
  group('lexical guards stay advisory (LL36)', () {
    for (final guardPath in _advisoryOnlyGuards) {
      test('${guardPath.split('/').last} cannot reach terminal state', () {
        final guard = File(guardPath);
        expect(
          guard.existsSync(),
          isTrue,
          reason:
              '$guardPath is listed as an advisory-only guard but is missing. '
              'If it was renamed or removed, update _advisoryOnlyGuards — and '
              'if it was removed on the strength of its firing record, note '
              'that in the LL36 delete-by-measurement log.',
        );

        final reachable = _transitiveImports(guardPath);
        final leaks = <String>[];
        for (final library in _terminalStateLibraries) {
          final absolute = p.normalize(
            p.join(Directory.current.path, library),
          );
          expect(
            File(absolute).existsSync(),
            isTrue,
            reason:
                '$library is listed as terminal state but does not exist, so '
                'this check would silently pass. Update '
                '_terminalStateLibraries.',
          );
          if (reachable.any((path) => p.equals(path, absolute))) {
            leaks.add('$library (via the import graph)');
          }
        }

        expect(
          leaks,
          isEmpty,
          reason:
              '$guardPath transitively imports terminal-state libraries: '
              '${leaks.join(', ')}.\n'
              'A lexical guard may append a notice, inject a recovery hint or '
              'select a nudge; it may not set goal status, complete a task, or '
              'decide a validation verdict (LL36). If it needs a constant from '
              'a producer, extract the shared name into its own library the '
              'way coding_verification_evidence_contract.dart does — do not '
              'import the producer.',
        );
      });

      test('${guardPath.split('/').last} names no terminal-state symbol', () {
        final source = File(guardPath).readAsStringSync();
        final found = _terminalStateSymbols
            .where(source.contains)
            .toList(growable: false);

        expect(
          found,
          isEmpty,
          reason:
              '$guardPath references terminal-state symbols: '
              '${found.join(', ')}. Return an advisory assessment and let a '
              'grounded path decide (LL36).',
        );
      });
    }

    test('every listed guard is a real file under domain/services', () {
      // Guards against the list silently rotting into a no-op.
      expect(_advisoryOnlyGuards, isNotEmpty);
      for (final path in _advisoryOnlyGuards) {
        expect(
          path,
          startsWith('lib/features/chat/domain/services/'),
          reason:
              'The advisory-guard list is scoped to domain services. A guard '
              'living outside that layer already has more reach than this '
              'test can constrain.',
        );
      }
    });
  });
}
