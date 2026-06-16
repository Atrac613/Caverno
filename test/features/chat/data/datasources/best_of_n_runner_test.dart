import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/best_of_n_runner.dart';
import 'package:caverno/features/chat/data/datasources/file_rollback_checkpoint_store.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/best_of_n_coordinator.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';

CodingVerificationSnapshot _snapshot(
  ConversationExecutionValidationStatus status, {
  int passed = 0,
  int failed = 0,
  String? reason,
}) {
  return CodingVerificationSnapshot(
    providerName: 'test',
    projectRoot: '/tmp/project',
    changedPaths: const ['lib/a.dart'],
    trigger: CodingVerificationTrigger.completionClaim,
    validationStatus: status,
    targetBatches: const [],
    failures: const [],
    telemetry: const CodingVerificationTelemetry(durationMs: 0, attempts: []),
    passedCount: passed,
    failedCount: failed,
    skippedCount: 0,
    reason: reason,
  );
}

/// Verifier returning queued verdicts, recording the changed paths it saw.
class _QueuedVerifier implements BestOfNVerifier {
  _QueuedVerifier(this._verdicts);
  final List<bool> _verdicts;
  int _calls = 0;
  final List<List<String>> seenChangedPaths = [];

  @override
  Future<BestOfNVerification> verify(List<String> changedPaths) async {
    seenChangedPaths.add(changedPaths);
    final passed = _verdicts[_calls];
    _calls += 1;
    return BestOfNVerification(passed: passed, summary: 'verdict $passed');
  }
}

void main() {
  group('CodingFeedbackBestOfNVerifier.mapSnapshot', () {
    test('green only when the snapshot ran and passed', () {
      expect(
        CodingFeedbackBestOfNVerifier.mapSnapshot(
          _snapshot(ConversationExecutionValidationStatus.passed, passed: 3),
        ).passed,
        isTrue,
      );
      expect(
        CodingFeedbackBestOfNVerifier.mapSnapshot(
          _snapshot(ConversationExecutionValidationStatus.failed, failed: 1),
        ).passed,
        isFalse,
      );
      expect(
        CodingFeedbackBestOfNVerifier.mapSnapshot(
          _snapshot(
            ConversationExecutionValidationStatus.unknown,
            reason: 'no_test_target',
          ),
        ).passed,
        isFalse,
        reason: 'unverified is not green',
      );
      expect(CodingFeedbackBestOfNVerifier.mapSnapshot(null).passed, isFalse);
    });
  });

  group('CheckpointVerificationBestOfNRunner', () {
    late Directory tempDir;
    late File target;
    late FileRollbackCheckpointStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('best_of_n_runner_test_');
      target = File('${tempDir.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('original');
      store = FileRollbackCheckpointStore();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // Simulates the agent editing [target]: snapshot the prior content (as the
    // filesystem tools do before a write), then write the new content.
    BestOfNGenerationStep editingGenerator(String Function(int) contentFor) {
      return (index) async {
        store.push(
          TextFileSnapshot(
            path: target.path,
            exists: true,
            content: target.readAsStringSync(),
          ),
        );
        target.writeAsStringSync(contentFor(index));
        return BestOfNGeneration(
          summary: 'edited a.dart',
          changedPaths: [target.path],
        );
      };
    }

    test('discards a non-winning candidate, restoring the file', () async {
      final runner = CheckpointVerificationBestOfNRunner(
        checkpointStore: store,
        verifier: _QueuedVerifier([false]),
        generate: editingGenerator((i) => 'candidate $i'),
      );

      await runner.generateCandidate(0);
      expect(target.readAsStringSync(), 'candidate 0');
      final verification = await runner.verify(0);
      expect(verification.passed, isFalse);
      await runner.discardCandidate(0);

      expect(target.readAsStringSync(), 'original', reason: 'no residue');
    });

    test('keeps a winning candidate in place', () async {
      final runner = CheckpointVerificationBestOfNRunner(
        checkpointStore: store,
        verifier: _QueuedVerifier([true]),
        generate: editingGenerator((i) => 'winner $i'),
      );

      await runner.generateCandidate(0);
      await runner.keepCandidate(0);

      expect(target.readAsStringSync(), 'winner 0');
    });

    test(
      'a no-edit candidate never rolls back a pre-existing checkpoint',
      () async {
        // A prior user turn edited the file and sits on the checkpoint stack.
        store.beginFileTurnCheckpoint('user_turn');
        store.push(
          TextFileSnapshot(
            path: target.path,
            exists: true,
            content: 'original',
          ),
        );
        target.writeAsStringSync('user edit');
        store.endFileTurnCheckpoint();

        final runner = CheckpointVerificationBestOfNRunner(
          checkpointStore: store,
          verifier: _QueuedVerifier([false]),
          generate: (index) async =>
              const BestOfNGeneration(summary: 'no changes', changedPaths: []),
        );

        await runner.generateCandidate(0);
        await runner.discardCandidate(0);

        // The user's edit must survive: discard was scoped to the candidate's
        // own (absent) checkpoint, not the user's.
        expect(target.readAsStringSync(), 'user edit');
      },
    );

    test('verify receives the candidate changed paths', () async {
      final verifier = _QueuedVerifier([false]);
      final runner = CheckpointVerificationBestOfNRunner(
        checkpointStore: store,
        verifier: verifier,
        generate: editingGenerator((i) => 'c$i'),
      );

      await runner.generateCandidate(0);
      await runner.verify(0);

      expect(verifier.seenChangedPaths.single, [target.path]);
      await runner.discardCandidate(0);
    });

    test(
      'drives a full coordinator run: candidate 0 reverted, 1 kept',
      () async {
        final runner = CheckpointVerificationBestOfNRunner(
          checkpointStore: store,
          verifier: _QueuedVerifier([false, true]),
          generate: editingGenerator((i) => 'candidate $i'),
        );

        final report = await const BestOfNCoordinator().run(
          maxCandidates: 3,
          runner: runner,
        );

        expect(report.winnerIndex, 1);
        expect(report.hasResidueRisk, isFalse);
        // The winning candidate 1's edit remains on disk.
        expect(target.readAsStringSync(), 'candidate 1');
      },
    );
  });
}
