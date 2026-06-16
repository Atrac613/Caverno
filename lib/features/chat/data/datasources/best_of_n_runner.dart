import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/best_of_n_coordinator.dart';
import '../../domain/services/coding_verification_feedback_service.dart';
import 'file_rollback_checkpoint_store.dart';

/// What a candidate generation produced: a short summary and the files it
/// changed (so verification knows what to test, and so the runner can tell
/// whether anything needs discarding).
class BestOfNGeneration {
  const BestOfNGeneration({required this.summary, required this.changedPaths});

  final String summary;
  final List<String> changedPaths;
}

/// Generates and applies candidate [index] to the working tree, returning what
/// it changed. Plugged in by the agent in a later slice; throwing marks a
/// generation failure (still discarded).
typedef BestOfNGenerationStep = Future<BestOfNGeneration> Function(int index);

/// Verifies the current working tree for a Best-of-N candidate.
abstract interface class BestOfNVerifier {
  Future<BestOfNVerification> verify(List<String> changedPaths);
}

/// Verifier backed by [CodingVerificationFeedbackService]: runs the project's
/// test verification over the candidate's changed paths and maps the snapshot
/// to a green/not-green verdict.
class CodingFeedbackBestOfNVerifier implements BestOfNVerifier {
  CodingFeedbackBestOfNVerifier({
    required this.service,
    required this.projectRoot,
    this.trigger = CodingVerificationTrigger.completionClaim,
  });

  final CodingVerificationFeedbackService service;
  final String projectRoot;
  final CodingVerificationTrigger trigger;

  @override
  Future<BestOfNVerification> verify(List<String> changedPaths) async {
    final run = await service.buildFeedbackRun(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
      trigger: trigger,
    );
    return mapSnapshot(run.snapshot);
  }

  /// Maps a verification snapshot to a Best-of-N verdict. Green requires a
  /// snapshot that ran and passed with no failures; `unknown` (e.g. no test
  /// target for the changed files) is not green, so Best-of-N never keeps a
  /// candidate that was not actually verified.
  static BestOfNVerification mapSnapshot(CodingVerificationSnapshot? snapshot) {
    if (snapshot == null) {
      return const BestOfNVerification(
        passed: false,
        summary: 'no verification snapshot',
      );
    }
    final passed =
        snapshot.validationStatus ==
            ConversationExecutionValidationStatus.passed &&
        snapshot.failedCount == 0;
    return BestOfNVerification(
      passed: passed,
      summary:
          'validation=${snapshot.validationStatus.name} '
          'passed=${snapshot.passedCount} failed=${snapshot.failedCount}'
          '${snapshot.reason == null ? '' : ' reason=${snapshot.reason}'}',
    );
  }
}

/// LL7 [BestOfNRunner] that brackets each candidate in an LL2 file-turn
/// checkpoint and verifies it with a [BestOfNVerifier].
///
/// Each candidate runs inside its own named turn checkpoint, so a non-winning
/// candidate is undone by rolling that checkpoint back. The discard is
/// turn-id-scoped: it only rolls back when the most recent checkpoint is this
/// candidate's, so a candidate that made no edits never reverts an unrelated
/// (e.g. pre-existing user) checkpoint, and a candidate that threw mid-edit
/// still has its partial edits rolled back (the checkpoint was finalized in a
/// `finally`).
class CheckpointVerificationBestOfNRunner implements BestOfNRunner {
  CheckpointVerificationBestOfNRunner({
    required this.checkpointStore,
    required this.verifier,
    required this.generate,
    this.checkpointIdPrefix = 'best_of_n_',
  });

  final FileRollbackCheckpointStore checkpointStore;
  final BestOfNVerifier verifier;
  final BestOfNGenerationStep generate;
  final String checkpointIdPrefix;

  List<String> _lastChangedPaths = const [];

  String _checkpointId(int index) => '$checkpointIdPrefix$index';

  @override
  Future<String> generateCandidate(int index) async {
    _lastChangedPaths = const [];
    checkpointStore.beginFileTurnCheckpoint(_checkpointId(index));
    try {
      final generation = await generate(index);
      _lastChangedPaths = List<String>.unmodifiable(generation.changedPaths);
      return generation.summary;
    } finally {
      // Finalize the checkpoint even on error, so partial edits are captured
      // and can be rolled back by discardCandidate.
      checkpointStore.endFileTurnCheckpoint();
    }
  }

  @override
  Future<BestOfNVerification> verify(int index) {
    return verifier.verify(_lastChangedPaths);
  }

  @override
  Future<void> discardCandidate(int index) async {
    final preview = await checkpointStore.previewLastFileTurnCheckpoint();
    if (preview == null || preview.turnId != _checkpointId(index)) {
      // This candidate captured no edits; the top checkpoint (if any) belongs
      // to something else and must not be touched.
      return;
    }
    await checkpointStore.rollbackLastFileTurnCheckpoint();
  }

  @override
  Future<void> keepCandidate(int index) async {
    // The winner's edits stay in place; its checkpoint remains on the stack so
    // the user can still roll the turn back through the normal LL2 affordance.
  }
}
