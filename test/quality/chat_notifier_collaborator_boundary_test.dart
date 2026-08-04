import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/audit_chat_notifier_turn_scope.dart' as audit;

const String _fileSizeRatchetPath = 'test/quality/file_size_ratchet_test.dart';

const String _collaboratorMarkerPrefix =
    '// ChatNotifier decomposition collaborator:';

final RegExp _exactCollaboratorMarker = RegExp(
  r'^// ChatNotifier decomposition collaborator: '
  r'([a-z0-9]+(?:-[a-z0-9]+)*)$',
);

const Set<String> _forbiddenTypeNames = {
  'ChatNotifier',
  'ChatState',
  'Ref',
  'WidgetRef',
  'ProviderContainer',
};

const Set<String> _forbiddenZoneNames = {
  'TurnThread',
  'TurnGeneration',
  'TurnProjectRoot',
};

/// The original `b0c19fdb` inventory, frozen independently of the manifest.
///
/// A manifest edit cannot approve a new notifier part by editing the only copy
/// of the inventory. Slice 2a1 verifies the same revision's entrypoints; this
/// list is the separate Slice 2a2 architecture boundary.
const List<String> _historicalPartPaths = [
  'chat_notifier_approval_handlers.dart',
  'chat_notifier_ask_user_question.dart',
  'chat_notifier_ble_handlers.dart',
  'chat_notifier_browser_handlers.dart',
  'chat_notifier_cancellation.dart',
  'chat_notifier_coding_continuation_recovery.dart',
  'chat_notifier_command_guardrails.dart',
  'chat_notifier_computer_use_handlers.dart',
  'chat_notifier_context_surgery.dart',
  'chat_notifier_duplicate_recovery.dart',
  'chat_notifier_error_handling.dart',
  'chat_notifier_execution_runtime.dart',
  'chat_notifier_final_answer_recovery.dart',
  'chat_notifier_git_handlers.dart',
  'chat_notifier_local_file_handlers.dart',
  'chat_notifier_mesh_routing.dart',
  'chat_notifier_participant_turns.dart',
  'chat_notifier_serial_handlers.dart',
  'chat_notifier_skill_handlers.dart',
  'chat_notifier_routine_handlers.dart',
  'chat_notifier_ssh_handlers.dart',
  'chat_notifier_subagent_handlers.dart',
  'chat_notifier_python_attachment_repair.dart',
  'chat_notifier_unexecuted_action_recovery.dart',
  'chat_notifier_content_tool_result_format.dart',
  'chat_notifier_coding_verification_feedback.dart',
  'chat_notifier_python_handlers.dart',
  'chat_notifier_planning_research.dart',
  'chat_notifier_proposal_option_extraction.dart',
  'chat_notifier_proposal_parsing.dart',
  'chat_notifier_workflow_proposal_parser.dart',
  'chat_notifier_prompt_context.dart',
  'chat_notifier_tool_result_telemetry.dart',
  'chat_notifier_tool_handler_registry.dart',
  'chat_notifier_turn_rollback_handlers.dart',
  'chat_notifier_turn_finalization_recovery.dart',
  'chat_notifier_turn_exit.dart',
  'chat_notifier_response_finalization.dart',
  'chat_notifier_goal_auto_continue.dart',
  'chat_notifier_task_proposal_quality.dart',
  'chat_notifier_terminal_tool_response_policy.dart',
  'chat_notifier_tool_loop_batch.dart',
  'chat_notifier_task_proposal_parser.dart',
];

final class _BoundaryViolation implements Exception {
  const _BoundaryViolation(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _BoundaryReport {
  const _BoundaryReport({
    required this.historicalPartCount,
    required this.declaredPartCount,
    required this.statusSelectedPartCount,
    required this.markerIds,
    required this.budgetKeys,
  });

  final int historicalPartCount;
  final int declaredPartCount;
  final int statusSelectedPartCount;
  final Set<String> markerIds;
  final Set<String> budgetKeys;
}

final class _DiscoveredMarker {
  const _DiscoveredMarker({
    required this.id,
    required this.path,
    required this.line,
  });

  final String id;
  final String path;
  final int line;
}

final class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> forbiddenTypes = <String>{};
  final Set<String> forbiddenZones = <String>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (_forbiddenTypeNames.contains(name)) {
      forbiddenTypes.add(name);
    }
    if (_forbiddenZoneNames.contains(name)) {
      forbiddenZones.add(name);
    }
    super.visitSimpleIdentifier(node);
  }
}

final class _NamedTypeVisitor extends RecursiveAstVisitor<void> {
  final Set<String> forbiddenTypes = <String>{};

  @override
  void visitNamedType(NamedType node) {
    final name = node.name.lexeme;
    if (_forbiddenTypeNames.contains(name)) {
      forbiddenTypes.add(name);
    }
    super.visitNamedType(node);
  }
}

void main() {
  group('ChatNotifier collaborator boundary', () {
    test('the checked-in tree satisfies the manifest contract', () {
      final root = Directory.current;
      final manifest = audit.ChatNotifierDecompositionManifest.load(
        File(audit.defaultDecompositionManifestPath),
        expectedPartCount: 43,
      );

      final report = _validateRepositoryBoundary(
        root: root,
        manifest: manifest,
      );

      expect(report.historicalPartCount, 43);
      expect(report.declaredPartCount, 37);
      expect(report.statusSelectedPartCount, 37);
      expect(report.markerIds, {
        'analysis-options-lint-edit-guard',
        'ask-user-question-option-parser',
        'ask-user-question-policy',
        'ask-user-question-turn-cache',
        'background-process-tool-handler',
        'ble-connection-tool-handler',
        'browser-session-ownership-coordinator',
        'browser-tool-handler',
        'chat-tool-handler-catalog',
        'coding-command-output-guardrail-service',
        'coding-continuation-recovery-policy',
        'coding-verification-feedback-presentation',
        'coding-verification-mutation-signature',
        'command-diagnostic-verifier-replay-guard',
        'computer-use-action-policy',
        'computer-use-runtime-coordinator',
        'computer-use-tool-handler',
        'content-tool-failure-formatter',
        'content-tool-result-formatter',
        'context-surgery-observation-accumulator',
        'context-surgery-protected-path-policy',
        'create-routine-tool-handler',
        'duplicate-tool-result-recovery',
        'execution-snapshot-observer',
        'file-mutation-tool-handler',
        'file-rollback-tool-handler',
        'file-turn-rollback-service',
        'final-answer-claim-notice-applicator',
        'git-process-execution-coordinator',
        'git-tag-format-inspection-guard',
        'git-tool-handler',
        'git-write-confirmation-policy',
        'goal-auto-continue-decision-coordinator',
        'goal-auto-continue-safe-boundary-builder',
        'goal-auto-continue-tracker-registry',
        'goal-continuation-log-record-builder',
        'goal-update-tool-handler',
        'goal-validation-probe-guard',
        'local-command-tool-handler',
        'lsp-go-to-definition-tool-handler',
        'material-contract-assumption-guard',
        'model-edit-apply-telemetry-recorder',
        'model-switch-handoff-registry',
        'model-switch-settings-policy',
        'narrated-transcript-repair-planner',
        'participant-message-finalizer',
        'participant-tool-executor',
        'participant-turn-planner',
        'process-start-result-policy',
        'production-release-approval-policy',
        'project-scoped-read-tool-handler',
        'python-attachment-repair-policy',
        'python-script-tool-handler',
        'referenced-specification-loader',
        'request-tool-observation-collector',
        'run-tests-tool-handler',
        'runtime-sampler-feedback-recorder',
        'save-skill-tool-handler',
        'saved-task-target-scope-guard',
        'saved-validation-command-guard',
        'secondary-completion-router',
        'serial-connection-attempt-coordinator',
        'serial-connection-tool-handler',
        'ssh-session-ownership-coordinator',
        'ssh-tool-handler',
        'subagent-tool-handler',
        'timed-out-command-retry-guard',
        'tool-loop-exhaustion-policy',
        'turn-finalization-recovery-policy',
        'truncated-tool-call-arguments-guard',
        'turn-runtime',
        'turn-runtime-conversation-goal-adapter',
        'turn-runtime-goal-continuation-log-adapter',
        'turn-runtime-goal-tracker-adapter',
        'turn-runtime-owner-lease-registry',
        'turn-runtime-production-composition',
        'turn-tool-approval-coordinator',
        'unexecuted-file-mutation-before-command-guard',
        'unexecuted-final-answer-tool-request-policy',
        'verifier-replay-candidate-policy',
      });
      expect(
        report.budgetKeys,
        containsAll({
          'lib/features/chat/domain/services/'
              'coding_continuation_recovery_policy.dart',
          'lib/features/chat/domain/services/'
              'content_tool_result_formatter.dart',
          'lib/features/chat/domain/services/'
              'content_tool_failure_formatter.dart',
          'lib/features/chat/domain/services/'
              'coding_verification_feedback_presentation.dart',
          'lib/features/chat/domain/services/'
              'coding_verification_mutation_signature.dart',
          'lib/features/chat/domain/services/'
              'context_surgery_observation_accumulator.dart',
          'lib/features/chat/domain/services/'
              'context_surgery_protected_path_policy.dart',
          'lib/features/chat/domain/services/'
              'duplicate_tool_result_recovery.dart',
          'lib/features/chat/domain/services/file_mutation_tool_handler.dart',
          'lib/features/chat/domain/services/file_rollback_tool_handler.dart',
          'lib/features/chat/domain/services/file_turn_rollback_service.dart',
          'lib/features/chat/domain/services/local_command_tool_handler.dart',
          'lib/features/chat/domain/services/git_write_confirmation_policy.dart',
          'lib/features/chat/domain/services/'
              'final_answer_claim_notice_applicator.dart',
          'lib/features/chat/domain/services/'
              'narrated_transcript_repair_planner.dart',
          'lib/features/chat/domain/services/'
              'model_edit_apply_telemetry_recorder.dart',
          'lib/features/chat/domain/services/'
              'model_switch_handoff_registry.dart',
          'lib/features/chat/domain/services/model_switch_settings_policy.dart',
          'lib/features/chat/domain/services/process_start_result_policy.dart',
          'lib/features/chat/domain/services/'
              'python_attachment_repair_policy.dart',
          'lib/features/chat/domain/services/'
              'python_script_tool_handler.dart',
          'lib/features/chat/domain/services/'
              'referenced_specification_loader.dart',
          'lib/features/chat/domain/services/'
              'request_tool_observation_collector.dart',
          'lib/features/chat/domain/services/'
              'runtime_sampler_feedback_recorder.dart',
          'lib/features/chat/domain/services/'
              'saved_task_target_scope_guard.dart',
          'lib/features/chat/domain/services/'
              'create_routine_tool_handler.dart',
          'lib/features/chat/domain/services/'
              'save_skill_tool_handler.dart',
          'lib/features/chat/domain/services/tool_loop_exhaustion_policy.dart',
          'lib/features/chat/domain/services/'
              'turn_finalization_recovery_policy.dart',
          'lib/features/chat/domain/services/'
              'unexecuted_file_mutation_before_command_guard.dart',
          'lib/features/chat/domain/services/'
              'unexecuted_final_answer_tool_request_policy.dart',
        }),
      );
    });

    test('freezes additions, removals, and duplicates independently', () {
      expect(
        () => _validateFrozenHistoricalPaths(
          actualPaths: const ['one.dart', 'two.dart'],
          frozenPaths: const ['one.dart', 'two.dart'],
        ),
        returnsNormally,
      );
      expect(
        () => _validateFrozenHistoricalPaths(
          actualPaths: const ['one.dart', 'two.dart', 'three.dart'],
          frozenPaths: const ['one.dart', 'two.dart'],
        ),
        throwsA(_violationContaining('historical part paths changed')),
      );
      expect(
        () => _validateFrozenHistoricalPaths(
          actualPaths: const ['one.dart'],
          frozenPaths: const ['one.dart', 'two.dart'],
        ),
        throwsA(_violationContaining('historical part paths changed')),
      );
      expect(
        () => _validateFrozenHistoricalPaths(
          actualPaths: const ['one.dart', 'one.dart'],
          frozenPaths: const ['one.dart', 'two.dart'],
        ),
        throwsA(_violationContaining('duplicate current historical part path')),
      );
      expect(_historicalPartPaths, hasLength(43));
      expect(_historicalPartPaths.toSet(), hasLength(43));
    });

    test('enforces extracted and partial status lifecycle', () {
      final root = Directory.systemTemp.createTempSync(
        'collaborator-status-fixture-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      const providerDirectory = 'lib/features/chat/presentation/providers';
      _writeFixture(
        root,
        '$providerDirectory/chat_notifier_partial.dart',
        "part of 'chat_notifier.dart';\n",
      );
      _writeFixture(
        root,
        '$providerDirectory/chat_notifier_extracted.dart',
        "part of 'chat_notifier.dart';\n",
      );

      const collaborator = audit.DecompositionCollaborator(
        id: 'sample-collaborator',
        path: 'lib/features/chat/domain/services/sample.dart',
        sizeBudgetKey: 'lib/features/chat/domain/services/sample.dart',
      );
      expect(
        () => _validatePartLifecycle(
          root: root,
          providerDirectory: providerDirectory,
          parts: const [
            audit.DecompositionPart(
              id: 'partial',
              partPath: 'chat_notifier_partial.dart',
              entrypoints: [],
              status: 'partial',
              collaborators: [],
            ),
          ],
        ),
        throwsA(_violationContaining('partial but has no collaborator')),
      );
      expect(
        () => _validatePartLifecycle(
          root: root,
          providerDirectory: providerDirectory,
          parts: const [
            audit.DecompositionPart(
              id: 'extracted',
              partPath: 'chat_notifier_extracted.dart',
              entrypoints: [],
              status: 'extracted',
              collaborators: [collaborator],
            ),
          ],
        ),
        throwsA(
          _violationContaining('extracted but its old part still exists'),
        ),
      );

      File(
        p.join(root.path, providerDirectory, 'chat_notifier_extracted.dart'),
      ).deleteSync();
      expect(
        () => _validatePartLifecycle(
          root: root,
          providerDirectory: providerDirectory,
          parts: const [
            audit.DecompositionPart(
              id: 'partial',
              partPath: 'chat_notifier_partial.dart',
              entrypoints: [],
              status: 'partial',
              collaborators: [collaborator],
            ),
            audit.DecompositionPart(
              id: 'extracted',
              partPath: 'chat_notifier_extracted.dart',
              entrypoints: [],
              status: 'extracted',
              collaborators: [collaborator],
            ),
          ],
        ),
        returnsNormally,
      );
    });

    test('discovers markers independently and requires one-to-one mapping', () {
      final root = Directory.systemTemp.createTempSync(
        'collaborator-marker-fixture-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      const firstPath = 'lib/features/chat/domain/services/first.dart';
      const secondPath = 'lib/features/chat/domain/services/second.dart';
      _writeFixture(
        root,
        firstPath,
        '$_collaboratorMarkerPrefix first\nclass First {}\n',
      );

      expect(
        () => _validateMarkers(
          discovered: _discoverMarkers(root),
          expectedPathById: const {'first': firstPath},
        ),
        returnsNormally,
      );

      _writeFixture(
        root,
        secondPath,
        '$_collaboratorMarkerPrefix first\nclass Second {}\n',
      );
      expect(
        () => _validateMarkers(
          discovered: _discoverMarkers(root),
          expectedPathById: const {'first': firstPath},
        ),
        throwsA(_violationContaining('duplicate collaborator marker id')),
      );

      _writeFixture(
        root,
        secondPath,
        '$_collaboratorMarkerPrefix unmanifested\nclass Second {}\n',
      );
      expect(
        () => _validateMarkers(
          discovered: _discoverMarkers(root),
          expectedPathById: const {'first': firstPath},
        ),
        throwsA(_violationContaining('unmanifested collaborator marker')),
      );

      _writeFixture(
        root,
        secondPath,
        '  $_collaboratorMarkerPrefix malformed\nclass Second {}\n',
      );
      expect(
        () => _discoverMarkers(root),
        throwsA(_violationContaining('malformed collaborator marker')),
      );
    });

    test('rejects part-of and every forbidden import category', () {
      expect(
        () => _inspectCollaboratorSource(
          sourcePath: 'sample.dart',
          source: "part of 'chat_notifier.dart';\nclass Sample {}\n",
        ),
        throwsA(_violationContaining('part of')),
      );

      const imports = {
        "import 'chat_notifier.dart';": 'chat_notifier.dart',
        "import 'chat_state.dart';": 'chat_state.dart',
        "import '../presentation/providers/settings_provider.dart';":
            'provider library',
        "import 'package:flutter_riverpod/flutter_riverpod.dart';":
            'Riverpod library',
      };
      for (final entry in imports.entries) {
        expect(
          () => _inspectCollaboratorSource(
            sourcePath: 'sample.dart',
            source: '${entry.key}\nclass Sample {}\n',
          ),
          throwsA(_violationContaining(entry.value)),
          reason: entry.key,
        );
      }
    });

    test('rejects forbidden type and Zone references', () {
      for (final type in _forbiddenTypeNames) {
        expect(
          () => _inspectCollaboratorSource(
            sourcePath: 'sample.dart',
            source: 'void helper() { $type(); }\n',
          ),
          throwsA(_violationContaining('forbidden type reference')),
          reason: type,
        );
      }
      for (final zone in _forbiddenZoneNames) {
        expect(
          () => _inspectCollaboratorSource(
            sourcePath: 'sample.dart',
            source: 'void helper() { $zone.current; }\n',
          ),
          throwsA(_violationContaining('forbidden Zone reference')),
          reason: zone,
        );
      }
    });

    test('separately rejects forbidden types in public signatures', () {
      for (final type in _forbiddenTypeNames) {
        expect(
          () => _inspectCollaboratorSource(
            sourcePath: 'sample.dart',
            source: '$type expose($type value) => value;\n',
          ),
          throwsA(_violationContaining('public signature')),
          reason: type,
        );
      }
    });

    test('accepts valid collaborators and ignores comments and strings', () {
      const source = '''
import 'dart:convert';

// ChatNotifier decomposition collaborator: valid-sample
abstract final class ValidSample {
  static String format(String value) {
    // ChatNotifier ChatState Ref WidgetRef ProviderContainer are prose.
    const ignored = 'TurnThread TurnProjectRoot ChatNotifier';
    return jsonEncode({'value': value, 'ignored': ignored});
  }
}
''';
      expect(
        () => _inspectCollaboratorSource(
          sourcePath: 'valid_sample.dart',
          source: source,
        ),
        returnsNormally,
      );

      final formatter = File(
        'lib/features/chat/domain/services/'
        'content_tool_result_formatter.dart',
      );
      expect(formatter.existsSync(), isTrue);
      expect(
        () => _inspectCollaboratorSource(
          sourcePath: formatter.path,
          source: formatter.readAsStringSync(),
        ),
        returnsNormally,
      );
    });

    test('reads actual budget-map keys instead of comments or strings', () {
      const source = '''
const note = 'fake.dart';
// 'comment.dart': 10,
const Map<String, int> _lineBudgets = {
  'real.dart': 12,
};
const Map<String, int> _libraryLineBudgets = {
  'library.dart': 20,
};
''';

      expect(_budgetKeysFromSource(source, 'fixture.dart'), {
        'real.dart',
        'library.dart',
      });
    });

    test('participant turn progression delegates to its planner', () {
      final source = File(
        'lib/features/chat/presentation/providers/'
        'chat_notifier_participant_turns.dart',
      ).readAsStringSync();

      expect(source, contains('ParticipantTurnPlanner().start'));
      expect(source, contains('planner.advance('));
      expect(source, contains('ParticipantTurnRuntimeProjection'));
      expect(source, isNot(contains('nextSpeaker(')));
      expect(source, isNot(contains('normalizeParticipants(')));
    });
  });
}

_BoundaryReport _validateRepositoryBoundary({
  required Directory root,
  required audit.ChatNotifierDecompositionManifest manifest,
}) {
  _validateFrozenHistoricalPaths(
    actualPaths: manifest.parts.map((part) => part.partPath).toList(),
    frozenPaths: _historicalPartPaths,
  );

  final notifierPath = p.join(root.path, manifest.notifierLibraryPath);
  final notifierFile = File(notifierPath);
  if (!notifierFile.existsSync()) {
    throw _BoundaryViolation(
      'Notifier library does not exist: ${manifest.notifierLibraryPath}',
    );
  }
  final notifierUnit = _parseUnit(
    notifierFile.readAsStringSync(),
    manifest.notifierLibraryPath,
  );
  final declaredParts = notifierUnit.directives
      .whereType<PartDirective>()
      .map((directive) => directive.uri.stringValue)
      .whereType<String>()
      .where((partPath) => partPath.startsWith('chat_notifier_'))
      .toList(growable: false);
  _requireUnique(declaredParts, 'declared notifier part');

  final statusSelectedParts = manifest.parts
      .where((part) => audit.activePartStatuses.contains(part.status))
      .map((part) => part.partPath)
      .toList(growable: false);
  _requireSameValues(
    actual: declaredParts,
    expected: statusSelectedParts,
    description: 'current notifier part directives',
  );

  final providerDirectory = p.posix.dirname(manifest.notifierLibraryPath);
  _validatePartLifecycle(
    root: root,
    providerDirectory: providerDirectory,
    parts: manifest.parts,
  );

  final collaborators = manifest.parts
      .where((part) => audit.collaboratorStatuses.contains(part.status))
      .expand((part) => part.collaborators)
      .toList(growable: false);
  final budgetFile = File(p.join(root.path, _fileSizeRatchetPath));
  if (!budgetFile.existsSync()) {
    throw const _BoundaryViolation(
      'The file-size ratchet is missing, so collaborator budgets cannot be '
      'verified.',
    );
  }
  final budgetKeys = _budgetKeysFromSource(
    budgetFile.readAsStringSync(),
    _fileSizeRatchetPath,
  );
  for (final collaborator in collaborators) {
    final collaboratorFile = File(p.join(root.path, collaborator.path));
    if (!collaboratorFile.existsSync()) {
      throw _BoundaryViolation(
        'Collaborator path does not exist: ${collaborator.path}',
      );
    }
    if (!budgetKeys.contains(collaborator.sizeBudgetKey)) {
      throw _BoundaryViolation(
        'Collaborator ${collaborator.id} has undeclared size budget key '
        '${collaborator.sizeBudgetKey}.',
      );
    }
    _inspectCollaboratorSource(
      sourcePath: collaborator.path,
      source: collaboratorFile.readAsStringSync(),
    );
  }

  final expectedPathById = <String, String>{
    for (final collaborator in collaborators)
      collaborator.id: p.posix.normalize(collaborator.path),
  };
  final markers = _discoverMarkers(root);
  _validateMarkers(discovered: markers, expectedPathById: expectedPathById);

  return _BoundaryReport(
    historicalPartCount: _historicalPartPaths.length,
    declaredPartCount: declaredParts.length,
    statusSelectedPartCount: statusSelectedParts.length,
    markerIds: markers.map((marker) => marker.id).toSet(),
    budgetKeys: budgetKeys,
  );
}

void _validateFrozenHistoricalPaths({
  required List<String> actualPaths,
  required List<String> frozenPaths,
}) {
  _requireUnique(frozenPaths, 'frozen historical part');
  _requireUnique(actualPaths, 'current historical part');
  _requireSameValues(
    actual: actualPaths,
    expected: frozenPaths,
    description: 'historical part paths',
  );
}

void _validatePartLifecycle({
  required Directory root,
  required String providerDirectory,
  required List<audit.DecompositionPart> parts,
}) {
  for (final part in parts) {
    final oldPart = File(p.join(root.path, providerDirectory, part.partPath));
    switch (part.status) {
      case 'extracted':
        if (part.collaborators.isEmpty) {
          throw _BoundaryViolation(
            '${part.partPath} is extracted but has no collaborator.',
          );
        }
        if (oldPart.existsSync()) {
          throw _BoundaryViolation(
            '${part.partPath} is extracted but its old part still exists.',
          );
        }
      case 'partial':
        if (part.collaborators.isEmpty) {
          throw _BoundaryViolation(
            '${part.partPath} is partial but has no collaborator.',
          );
        }
        if (!oldPart.existsSync()) {
          throw _BoundaryViolation(
            '${part.partPath} is partial but its old part is missing.',
          );
        }
      case 'remaining':
      case 'keep':
      case 'deferred':
        if (!oldPart.existsSync()) {
          throw _BoundaryViolation(
            '${part.partPath} has status ${part.status} but is missing.',
          );
        }
      default:
        throw _BoundaryViolation(
          '${part.partPath} has unsupported status ${part.status}.',
        );
    }
  }
}

List<_DiscoveredMarker> _discoverMarkers(Directory root) {
  final chatRoot = Directory(p.join(root.path, 'lib/features/chat'));
  if (!chatRoot.existsSync()) {
    throw const _BoundaryViolation(
      'lib/features/chat is missing, so markers cannot be discovered.',
    );
  }
  final files =
      chatRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final markers = <_DiscoveredMarker>[];
  for (final file in files) {
    final relativePath = p.posix.normalize(
      p.relative(file.path, from: root.path).replaceAll(r'\', '/'),
    );
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (!line.contains('ChatNotifier decomposition collaborator:')) {
        continue;
      }
      final match = _exactCollaboratorMarker.firstMatch(line);
      if (match == null) {
        throw _BoundaryViolation(
          'Malformed collaborator marker at $relativePath:${index + 1}. '
          'Expected "$_collaboratorMarkerPrefix <collaborator-id>".',
        );
      }
      markers.add(
        _DiscoveredMarker(
          id: match.group(1)!,
          path: relativePath,
          line: index + 1,
        ),
      );
    }
  }
  return markers;
}

void _validateMarkers({
  required List<_DiscoveredMarker> discovered,
  required Map<String, String> expectedPathById,
}) {
  final byId = <String, _DiscoveredMarker>{};
  final byPath = <String, _DiscoveredMarker>{};
  for (final marker in discovered) {
    final previousId = byId[marker.id];
    if (previousId != null) {
      throw _BoundaryViolation(
        'Duplicate collaborator marker id ${marker.id}: '
        '${previousId.path}:${previousId.line} and '
        '${marker.path}:${marker.line}.',
      );
    }
    final previousPath = byPath[marker.path];
    if (previousPath != null) {
      throw _BoundaryViolation(
        'Multiple collaborator markers in ${marker.path}: '
        '${previousPath.id} and ${marker.id}.',
      );
    }
    byId[marker.id] = marker;
    byPath[marker.path] = marker;
    final expectedPath = expectedPathById[marker.id];
    if (expectedPath == null) {
      throw _BoundaryViolation(
        'Unmanifested collaborator marker ${marker.id} at ${marker.path}.',
      );
    }
    if (p.posix.normalize(marker.path) != p.posix.normalize(expectedPath)) {
      throw _BoundaryViolation(
        'Collaborator marker ${marker.id} is in ${marker.path}, but the '
        'manifest assigns it to $expectedPath.',
      );
    }
  }
  for (final entry in expectedPathById.entries) {
    if (!byId.containsKey(entry.key)) {
      throw _BoundaryViolation(
        'Manifest collaborator ${entry.key} is missing its marker in '
        '${entry.value}.',
      );
    }
  }
}

void _inspectCollaboratorSource({
  required String sourcePath,
  required String source,
}) {
  final unit = _parseUnit(source, sourcePath);
  if (unit.directives.whereType<PartOfDirective>().isNotEmpty) {
    throw _BoundaryViolation(
      '$sourcePath uses part of; decomposition collaborators must be '
      'independent libraries.',
    );
  }

  for (final directive in unit.directives.whereType<ImportDirective>()) {
    final uri = directive.uri.stringValue;
    if (uri == null) {
      throw _BoundaryViolation(
        '$sourcePath has a non-literal import URI, which cannot be audited.',
      );
    }
    final reason = _forbiddenImportReason(uri);
    if (reason != null) {
      throw _BoundaryViolation('$sourcePath imports forbidden $reason: $uri');
    }
  }

  final publicSignatureTypes = _publicSignatureForbiddenTypes(unit);
  if (publicSignatureTypes.isNotEmpty) {
    throw _BoundaryViolation(
      '$sourcePath exposes forbidden type(s) in a public signature: '
      '${publicSignatureTypes.toList()..sort()}.',
    );
  }

  final references = _ReferenceVisitor();
  unit.accept(references);
  if (references.forbiddenTypes.isNotEmpty) {
    throw _BoundaryViolation(
      '$sourcePath contains forbidden type reference(s): '
      '${references.forbiddenTypes.toList()..sort()}.',
    );
  }
  if (references.forbiddenZones.isNotEmpty) {
    throw _BoundaryViolation(
      '$sourcePath contains forbidden Zone reference(s): '
      '${references.forbiddenZones.toList()..sort()}.',
    );
  }
}

String? _forbiddenImportReason(String uri) {
  final normalized = uri.replaceAll(r'\', '/').toLowerCase();
  final basename = normalized.split('/').last;
  if (basename == 'chat_notifier.dart') {
    return 'chat_notifier.dart';
  }
  if (basename == 'chat_state.dart') {
    return 'chat_state.dart';
  }
  if (normalized.startsWith('package:flutter_riverpod/') ||
      normalized.startsWith('package:riverpod/') ||
      normalized.startsWith('package:hooks_riverpod/')) {
    return 'Riverpod library';
  }
  final segments = normalized.split('/');
  if (normalized.startsWith('package:provider/') ||
      segments.contains('providers') ||
      basename == 'provider.dart' ||
      basename.endsWith('_provider.dart') ||
      basename.endsWith('_providers.dart')) {
    return 'provider library';
  }
  return null;
}

Set<String> _publicSignatureForbiddenTypes(CompilationUnit unit) {
  final forbidden = <String>{};
  void inspect(AstNode? node) {
    if (node == null) return;
    final visitor = _NamedTypeVisitor();
    node.accept(visitor);
    forbidden.addAll(visitor.forbiddenTypes);
  }

  void inspectClassMembers(Iterable<ClassMember> members) {
    for (final member in members) {
      if (member is MethodDeclaration && _isPublicName(member.name.lexeme)) {
        inspect(member.returnType);
        inspect(member.typeParameters);
        inspect(member.parameters);
      } else if (member is ConstructorDeclaration) {
        final constructorName = member.name?.lexeme;
        if (constructorName == null || _isPublicName(constructorName)) {
          inspect(member.parameters);
          inspect(member.redirectedConstructor);
        }
      } else if (member is FieldDeclaration &&
          member.fields.variables.any(
            (variable) => _isPublicName(variable.name.lexeme),
          )) {
        inspect(member.fields.type);
      }
    }
  }

  void inspectClassNamePart(ClassNamePart namePart) {
    inspect(namePart.typeParameters);
    if (namePart is PrimaryConstructorDeclaration) {
      inspect(namePart.formalParameters);
    }
  }

  for (final declaration in unit.declarations) {
    if (declaration is FunctionDeclaration &&
        _isPublicName(declaration.name.lexeme)) {
      inspect(declaration.returnType);
      inspect(declaration.functionExpression.typeParameters);
      inspect(declaration.functionExpression.parameters);
    } else if (declaration is TopLevelVariableDeclaration &&
        declaration.variables.variables.any(
          (variable) => _isPublicName(variable.name.lexeme),
        )) {
      inspect(declaration.variables.type);
    } else if (declaration is ClassDeclaration &&
        _isPublicName(declaration.namePart.typeName.lexeme)) {
      inspectClassNamePart(declaration.namePart);
      inspect(declaration.extendsClause);
      inspect(declaration.withClause);
      inspect(declaration.implementsClause);
      inspectClassMembers(_classMembers(declaration.body));
    } else if (declaration is MixinDeclaration &&
        _isPublicName(declaration.name.lexeme)) {
      inspect(declaration.typeParameters);
      inspect(declaration.onClause);
      inspect(declaration.implementsClause);
      inspectClassMembers(declaration.body.members);
    } else if (declaration is EnumDeclaration &&
        _isPublicName(declaration.namePart.typeName.lexeme)) {
      inspectClassNamePart(declaration.namePart);
      inspect(declaration.withClause);
      inspect(declaration.implementsClause);
      inspectClassMembers(declaration.body.members);
    } else if (declaration is ExtensionDeclaration &&
        (declaration.name == null || _isPublicName(declaration.name!.lexeme))) {
      inspect(declaration.typeParameters);
      inspect(declaration.onClause);
      inspectClassMembers(declaration.body.members);
    } else if (declaration is GenericTypeAlias &&
        _isPublicName(declaration.name.lexeme)) {
      inspect(declaration.typeParameters);
      inspect(declaration.type);
    } else if (declaration is FunctionTypeAlias &&
        _isPublicName(declaration.name.lexeme)) {
      inspect(declaration.returnType);
      inspect(declaration.typeParameters);
      inspect(declaration.parameters);
    }
  }
  return forbidden;
}

Set<String> _budgetKeysFromSource(String source, String sourcePath) {
  final unit = _parseUnit(source, sourcePath);
  final keys = <String>{};
  for (final declaration
      in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final variable in declaration.variables.variables) {
      if (!{
        '_lineBudgets',
        '_libraryLineBudgets',
      }.contains(variable.name.lexeme)) {
        continue;
      }
      final initializer = variable.initializer;
      if (initializer is! SetOrMapLiteral) {
        throw _BoundaryViolation(
          '${variable.name.lexeme} in $sourcePath is not a map literal.',
        );
      }
      for (final element in initializer.elements) {
        if (element is! MapLiteralEntry) {
          throw _BoundaryViolation(
            '${variable.name.lexeme} in $sourcePath is not a map literal.',
          );
        }
        final entry = element;
        final key = entry.key;
        if (key is! StringLiteral || key.stringValue == null) {
          throw _BoundaryViolation(
            '${variable.name.lexeme} in $sourcePath has a non-string key.',
          );
        }
        keys.add(key.stringValue!);
      }
    }
  }
  if (keys.isEmpty) {
    throw _BoundaryViolation(
      '$sourcePath declares no shrink-only file or library budget keys.',
    );
  }
  return keys;
}

CompilationUnit _parseUnit(String source, String sourcePath) {
  final ParseStringResult result = parseString(
    content: source,
    path: sourcePath,
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    throw _BoundaryViolation(
      'Unable to parse $sourcePath: '
      '${result.errors.map((error) => error.message).join('; ')}',
    );
  }
  return result.unit;
}

void _requireUnique(List<String> values, String description) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw _BoundaryViolation('Duplicate $description path: $value.');
    }
  }
}

void _requireSameValues({
  required List<String> actual,
  required List<String> expected,
  required String description,
}) {
  final actualSet = actual.toSet();
  final expectedSet = expected.toSet();
  if (actualSet.length == expectedSet.length &&
      actualSet.containsAll(expectedSet)) {
    return;
  }
  final added = actualSet.difference(expectedSet).toList()..sort();
  final removed = expectedSet.difference(actualSet).toList()..sort();
  throw _BoundaryViolation(
    '$description changed; added=$added, removed=$removed.',
  );
}

bool _isPublicName(String name) => !name.startsWith('_');

Iterable<ClassMember> _classMembers(ClassBody body) {
  if (body is BlockClassBody) {
    return body.members;
  }
  return const <ClassMember>[];
}

Matcher _violationContaining(String text) => isA<_BoundaryViolation>().having(
  (error) => error.message.toLowerCase(),
  'message',
  contains(text.toLowerCase()),
);

void _writeFixture(Directory root, String relativePath, String source) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(source);
}
