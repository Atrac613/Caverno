import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_observer.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:test/test.dart';

void main() {
  group('ExecutionSnapshotObserver', () {
    test('ignores non-coding workspaces', () async {
      final fixture = _fixture();

      for (final workspaceMode in [
        WorkspaceMode.chat,
        WorkspaceMode.routines,
      ]) {
        await fixture.observer.observe(
          _observation(workspaceMode: workspaceMode),
        );
      }

      expect(fixture.port.callCount, 0);
      expect(fixture.diagnostics, isEmpty);
    });

    test('records the first bounded observation for its owner', () async {
      final fixture = _fixture();
      const context = _LogContext('conversation-a');
      final timestamp = DateTime.utc(2026, 7, 30, 10, 15);
      final snapshot = _snapshot(latestDiagnostic: 'private diagnostic');

      await fixture.observer.observe(
        _observation(
          snapshot: snapshot,
          logContext: context,
          timestamp: timestamp,
        ),
      );

      expect(fixture.port.records, hasLength(1));
      final record = fixture.port.records.single;
      expect(identical(record.owner, context), isTrue);
      expect(record.event.timestamp, timestamp);
      expect(record.event.contractHash, 'contract-hash');
      expect(record.event.workflowStage, 'implement');
      expect(record.event.action, 'execute');
      expect(record.event.activeTaskRef, snapshot.activeTaskRef);
      expect(record.event.taskStatus, 'inProgress');
      expect(record.event.validationStatus, 'failed');
      expect(record.event.completedTaskCount, 1);
      expect(record.event.totalTaskCount, 3);
      expect(record.event.unresolvedQuestionCount, 2);
      expect(record.event.requiresValidation, isTrue);
      expect(record.event.hasDiagnostic, isTrue);
    });

    test('emits the diagnostic before invoking the persistence port', () async {
      final lifecycle = <String>[];
      final fixture = _fixture(
        onDiagnostic: (_) => lifecycle.add('diagnostic'),
        onRecord: () => lifecycle.add('persist'),
      );

      await fixture.observer.observe(_observation());

      expect(lifecycle, ['diagnostic', 'persist']);
    });

    test(
      'suppresses an unchanged observation for the same conversation',
      () async {
        final fixture = _fixture();
        final observation = _observation();

        await fixture.observer.observe(observation);
        await fixture.observer.observe(observation);

        expect(fixture.port.callCount, 1);
        expect(fixture.diagnostics, hasLength(1));
      },
    );

    test('records a changed snapshot for the same conversation', () async {
      final fixture = _fixture();

      await fixture.observer.observe(_observation());
      await fixture.observer.observe(
        _observation(
          snapshot: _snapshot(action: ExecutionSnapshotAction.verify),
        ),
      );

      expect(fixture.port.records, hasLength(2));
      expect(fixture.port.records.last.event.action, 'verify');
    });

    test(
      'keys only the latest observation by conversation and snapshot',
      () async {
        final fixture = _fixture();
        final snapshot = _snapshot();

        await fixture.observer.observe(_observation(snapshot: snapshot));
        await fixture.observer.observe(
          _observation(
            conversationId: 'conversation-b',
            snapshot: snapshot,
            logContext: const _LogContext('conversation-b'),
          ),
        );
        await fixture.observer.observe(_observation(snapshot: snapshot));

        expect(fixture.port.records, hasLength(3));
        expect(
          fixture.port.records.map((record) => record.owner.conversationId),
          ['conversation-a', 'conversation-b', 'conversation-a'],
        );
      },
    );

    test('diagnoses but does not persist when logging is disabled', () async {
      final fixture = _fixture();
      final snapshot = _snapshot();

      await fixture.observer.observe(
        _observation(snapshot: snapshot, loggingEnabled: false),
      );
      await fixture.observer.observe(_observation(snapshot: snapshot));

      expect(fixture.port.callCount, 0);
      expect(fixture.diagnostics, hasLength(1));
    });

    test(
      'contains log-port failures and keeps the observation deduplicated',
      () async {
        final fixture = _fixture(portFailure: StateError('log unavailable'));
        final observation = _observation();

        await expectLater(fixture.observer.observe(observation), completes);
        await fixture.observer.observe(observation);

        expect(fixture.port.callCount, 1);
        expect(fixture.port.records, isEmpty);
        expect(fixture.diagnostics, hasLength(1));
      },
    );

    test(
      'contains diagnostic failures and still attempts bounded persistence',
      () async {
        final fixture = _fixture(
          diagnosticFailure: StateError('diagnostic unavailable'),
        );
        final observation = _observation();

        await expectLater(fixture.observer.observe(observation), completes);
        await fixture.observer.observe(observation);

        expect(fixture.diagnostics, hasLength(1));
        expect(fixture.port.callCount, 1);
        expect(fixture.port.records, hasLength(1));
      },
    );

    // The field list is asserted whole rather than by substring: this line is
    // read by triage tooling, so a field appearing, vanishing or changing
    // order is a change to an interface, not an implementation detail.
    // `assumptions=` joined it in ANA0 PR 5a, when blocking assumptions
    // stopped being counted as open questions and the two became tellable
    // apart in a log.
    test('keeps the existing redacted diagnostic summary format', () async {
      final fixture = _fixture();
      final snapshot = _snapshot(
        action: ExecutionSnapshotAction.repair,
        activeTaskId: null,
        activeTaskStatus: null,
        latestDiagnostic: 'Bearer private-diagnostic-token',
        commandDiagnosticStreak: 2,
      );

      await fixture.observer.observe(_observation(snapshot: snapshot));

      expect(
        fixture.diagnostics.single,
        '[ExecutionShadow] contract=contract-hash stage=implement '
        'action=repair activeTaskRef=none taskStatus=none '
        'validation=failed tasks=1/3 questions=2 assumptions=0 '
        'requiresValidation=true hasDiagnostic=true diagnosticStreak=2',
      );
      expect(
        fixture.diagnostics.single,
        isNot(contains('private-diagnostic-token')),
      );
    });

    test('captures an immutable snapshot of every collection field', () {
      final constraints = <String>['keep constraint'];
      final acceptanceCriteria = <String>['keep criterion'];
      final targetFiles = <String>['lib/keep.dart'];
      final remainingTaskIds = <String>['task-keep'];
      final clarificationQuestions = <String>['keep question'];

      final observation = _observation(
        snapshot: _snapshot(
          constraints: constraints,
          acceptanceCriteria: acceptanceCriteria,
          activeTaskTargetFiles: targetFiles,
          remainingTaskIds: remainingTaskIds,
          clarificationQuestions: clarificationQuestions,
        ),
      );

      constraints[0] = 'poisoned constraint';
      acceptanceCriteria[0] = 'poisoned criterion';
      targetFiles[0] = 'lib/poisoned.dart';
      remainingTaskIds[0] = 'task-poisoned';
      clarificationQuestions[0] = 'poisoned question';

      expect(observation.snapshot.constraints, ['keep constraint']);
      expect(observation.snapshot.acceptanceCriteria, ['keep criterion']);
      expect(observation.snapshot.activeTaskTargetFiles, ['lib/keep.dart']);
      expect(observation.snapshot.remainingTaskIds, ['task-keep']);
      expect(observation.snapshot.clarificationQuestions, ['keep question']);
      expect(
        () => observation.snapshot.constraints.add('later poison'),
        throwsUnsupportedError,
      );
      expect(
        () => observation.snapshot.acceptanceCriteria.add('later poison'),
        throwsUnsupportedError,
      );
      expect(
        () => observation.snapshot.activeTaskTargetFiles.add('later poison'),
        throwsUnsupportedError,
      );
      expect(
        () => observation.snapshot.remainingTaskIds.add('later poison'),
        throwsUnsupportedError,
      );
      expect(
        () => observation.snapshot.clarificationQuestions.add('later poison'),
        throwsUnsupportedError,
      );
    });

    test('callback log port forwards the exact owner and event', () async {
      const context = _LogContext('conversation-a');
      final event = ExecutionShadowEvent.fromSnapshot(
        snapshot: _snapshot(),
        timestamp: DateTime.utc(2026, 7, 31),
      );
      _LogContext? seenOwner;
      ExecutionShadowEvent? seenEvent;
      final port = CallbackExecutionShadowLogPort<_LogContext>((
        owner,
        receivedEvent,
      ) async {
        seenOwner = owner;
        seenEvent = receivedEvent;
      });

      await port.record(context, event);

      expect(seenOwner, same(context));
      expect(seenEvent, same(event));
    });
  });
}

typedef _Fixture = ({
  ExecutionSnapshotObserver<_LogContext> observer,
  _RecordingLogPort port,
  List<String> diagnostics,
});

_Fixture _fixture({
  Object? portFailure,
  Object? diagnosticFailure,
  void Function(String message)? onDiagnostic,
  void Function()? onRecord,
}) {
  final port = _RecordingLogPort(failure: portFailure, onRecord: onRecord);
  final diagnostics = <String>[];
  return (
    observer: ExecutionSnapshotObserver<_LogContext>(
      logPort: port,
      diagnosticLog: (message) {
        diagnostics.add(message);
        onDiagnostic?.call(message);
        if (diagnosticFailure case final failure?) {
          throw failure;
        }
      },
    ),
    port: port,
    diagnostics: diagnostics,
  );
}

ExecutionSnapshotObservation<_LogContext> _observation({
  String conversationId = 'conversation-a',
  WorkspaceMode workspaceMode = WorkspaceMode.coding,
  ExecutionSnapshot? snapshot,
  bool loggingEnabled = true,
  _LogContext logContext = const _LogContext('conversation-a'),
  DateTime? timestamp,
}) {
  return ExecutionSnapshotObservation(
    conversationId: conversationId,
    workspaceMode: workspaceMode,
    snapshot: snapshot ?? _snapshot(),
    loggingEnabled: loggingEnabled,
    logContext: logContext,
    timestamp: timestamp ?? DateTime.utc(2026, 7, 30),
  );
}

ExecutionSnapshot _snapshot({
  ExecutionSnapshotAction action = ExecutionSnapshotAction.execute,
  String? activeTaskId = 'task-a',
  ConversationWorkflowTaskStatus? activeTaskStatus =
      ConversationWorkflowTaskStatus.inProgress,
  String? latestDiagnostic,
  int commandDiagnosticStreak = 0,
  List<String> constraints = const <String>[],
  List<String> acceptanceCriteria = const <String>[],
  List<String> activeTaskTargetFiles = const <String>[],
  List<String> remainingTaskIds = const <String>[],
  List<String> clarificationQuestions = const <String>[],
}) {
  return ExecutionSnapshot(
    contractHash: 'contract-hash',
    workflowStage: ConversationWorkflowStage.implement,
    action: action,
    activeTaskId: activeTaskId,
    activeTaskStatus: activeTaskStatus,
    validationStatus: ConversationExecutionValidationStatus.failed,
    completedTaskCount: 1,
    remainingTaskCount: 2,
    unresolvedQuestionCount: 2,
    requiresValidation: true,
    latestDiagnostic: latestDiagnostic,
    constraints: constraints,
    acceptanceCriteria: acceptanceCriteria,
    activeTaskTargetFiles: activeTaskTargetFiles,
    remainingTaskIds: remainingTaskIds,
    clarificationQuestions: clarificationQuestions,
    commandDiagnosticStreak: commandDiagnosticStreak,
  );
}

final class _LogContext {
  const _LogContext(this.conversationId);

  final String conversationId;
}

typedef _RecordedShadow = ({_LogContext owner, ExecutionShadowEvent event});

final class _RecordingLogPort implements ExecutionShadowLogPort<_LogContext> {
  _RecordingLogPort({this.failure, this.onRecord});

  final Object? failure;
  final void Function()? onRecord;
  final List<_RecordedShadow> records = [];
  int callCount = 0;

  @override
  Future<void> record(_LogContext owner, ExecutionShadowEvent event) async {
    callCount += 1;
    onRecord?.call();
    if (failure case final failure?) {
      throw failure;
    }
    records.add((owner: owner, event: event));
  }
}
