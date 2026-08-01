import 'package:caverno/features/chat/data/datasources/ble_serialized_connect_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/ble_connection_runtime_contract.dart';
import 'package:test/test.dart';

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 11,
  );
  late BleConnectionRuntimeIdentity identity;

  setUp(() {
    identity = BleConnectionRuntimeIdentity(
      owner: owner,
      toolCallId: 'call-ble',
      toolName: 'ble_connect',
      deviceId: 'device-a',
    );
  });

  test(
    'returns exact connected acknowledgement after lifecycle checks',
    () async {
      final runner = _Runner();
      final lifecycleIdentities = <BleConnectionRuntimeIdentity>[];
      final adapter = BleSerializedConnectRuntimeAdapter(
        runner: runner,
        acknowledgeOwner: (received) {
          lifecycleIdentities.add(received);
          return BleOwnerLifecycleAcknowledgement(
            identity: received,
            disposition: BleOwnerLifecycleDisposition.current,
          );
        },
      );

      final acknowledgement = await adapter.connect(identity);

      expect(
        acknowledgement.disposition,
        BleSerializedConnectDisposition.connected,
      );
      expect(acknowledgement.identity, identity);
      expect(runner.identities, [identity]);
      expect(lifecycleIdentities, [identity, identity]);
    },
  );

  test('preserves an exact owner-expired rollback outcome', () async {
    final runner = _Runner();
    final dispositions = [
      BleOwnerLifecycleDisposition.current,
      BleOwnerLifecycleDisposition.ownerExpired,
    ];
    final adapter = BleSerializedConnectRuntimeAdapter(
      runner: runner,
      acknowledgeOwner: (received) => BleOwnerLifecycleAcknowledgement(
        identity: received,
        disposition: dispositions.removeAt(0),
      ),
    );

    final acknowledgement = await adapter.connect(identity);

    expect(
      acknowledgement.disposition,
      BleSerializedConnectDisposition.ownerExpired,
    );
    expect(runner.ownerChecks, 2);
  });

  test('treats poisoned lifecycle identities as effect uncertain', () async {
    final poisoners =
        <BleConnectionRuntimeIdentity Function(BleConnectionRuntimeIdentity)>[
          (received) => BleConnectionRuntimeIdentity(
            owner: ChatTurnOwner(
              conversationId: 'conversation-b',
              interactionGeneration: received.owner.interactionGeneration,
            ),
            toolCallId: received.toolCallId,
            toolName: received.toolName,
            deviceId: received.deviceId,
          ),
          (received) => BleConnectionRuntimeIdentity(
            owner: received.owner,
            toolCallId: 'other-call',
            toolName: received.toolName,
            deviceId: received.deviceId,
          ),
          (received) => BleConnectionRuntimeIdentity(
            owner: received.owner,
            toolCallId: received.toolCallId,
            toolName: received.toolName,
            deviceId: 'device-b',
          ),
        ];

    for (final poison in poisoners) {
      final runner = _Runner();
      final adapter = BleSerializedConnectRuntimeAdapter(
        runner: runner,
        acknowledgeOwner: (received) => BleOwnerLifecycleAcknowledgement(
          identity: poison(received),
          disposition: BleOwnerLifecycleDisposition.current,
        ),
      );

      final acknowledgement = await adapter.connect(identity);

      expect(
        acknowledgement.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(acknowledgement.identity, identity);
    }
  });

  test('treats uncertain or throwing lifecycle checks as uncertain', () async {
    final uncertain = BleSerializedConnectRuntimeAdapter(
      runner: _Runner(),
      acknowledgeOwner: (received) => BleOwnerLifecycleAcknowledgement(
        identity: received,
        disposition: BleOwnerLifecycleDisposition.effectUncertain,
      ),
    );
    final throwing = BleSerializedConnectRuntimeAdapter(
      runner: _Runner(),
      acknowledgeOwner: (received) => throw StateError('owner unavailable'),
    );

    final uncertainResult = await uncertain.connect(identity);
    final throwingResult = await throwing.connect(identity);

    expect(
      uncertainResult.disposition,
      BleSerializedConnectDisposition.effectUncertain,
    );
    expect(
      throwingResult.disposition,
      BleSerializedConnectDisposition.effectUncertain,
    );
  });

  test(
    'records rollback errors and classifies the effect as uncertain',
    () async {
      final rollbackError = StateError('disconnect failed');
      final runner = _Runner()..rollbackError = rollbackError;
      final observed = <(BleConnectionRuntimeIdentity, Object)>[];
      final adapter = BleSerializedConnectRuntimeAdapter(
        runner: runner,
        acknowledgeOwner: _current,
        onRollbackError: (received, error) {
          observed.add((received, error));
        },
      );

      final acknowledgement = await adapter.connect(identity);

      expect(
        acknowledgement.disposition,
        BleSerializedConnectDisposition.effectUncertain,
      );
      expect(acknowledgement.errorMessage, 'Bad state: disconnect failed');
      expect(observed, [(identity, rollbackError)]);
    },
  );

  test('keeps an explicit failed attempt distinct from uncertainty', () async {
    final runner = _Runner()
      ..outcome = BleConnectAttemptRunOutcome.failed(
        StateError('connect failed'),
      );
    final adapter = BleSerializedConnectRuntimeAdapter(
      runner: runner,
      acknowledgeOwner: _current,
    );

    final acknowledgement = await adapter.connect(identity);

    expect(acknowledgement.disposition, BleSerializedConnectDisposition.failed);
    expect(acknowledgement.errorMessage, 'Bad state: connect failed');
  });

  test('classifies an untyped runner throw as effect uncertain', () async {
    final runner = _Runner()..throwOnRun = true;
    final adapter = BleSerializedConnectRuntimeAdapter(
      runner: runner,
      acknowledgeOwner: _current,
    );

    final acknowledgement = await adapter.connect(identity);

    expect(
      acknowledgement.disposition,
      BleSerializedConnectDisposition.effectUncertain,
    );
    expect(acknowledgement.errorMessage, contains('runner failed'));
  });
}

BleOwnerLifecycleAcknowledgement _current(
  BleConnectionRuntimeIdentity identity,
) {
  return BleOwnerLifecycleAcknowledgement(
    identity: identity,
    disposition: BleOwnerLifecycleDisposition.current,
  );
}

final class _Runner implements BleConnectAttemptRunner {
  final List<BleConnectionRuntimeIdentity> identities = [];
  BleConnectAttemptRunOutcome outcome =
      const BleConnectAttemptRunOutcome.connected();
  Object? rollbackError;
  bool throwOnRun = false;
  int ownerChecks = 0;

  @override
  Future<BleConnectAttemptRunOutcome> run(
    BleConnectionRuntimeIdentity identity, {
    required bool Function() ownerIsCurrent,
    required void Function(Object error) onRollbackError,
  }) async {
    identities.add(identity);
    if (throwOnRun) throw StateError('runner failed after dispatch');
    ownerChecks += 1;
    if (!ownerIsCurrent()) {
      return const BleConnectAttemptRunOutcome.ownerExpired();
    }
    final rollbackFailure = rollbackError;
    if (rollbackFailure != null) onRollbackError(rollbackFailure);
    ownerChecks += 1;
    if (!ownerIsCurrent()) {
      return const BleConnectAttemptRunOutcome.ownerExpired();
    }
    return outcome;
  }
}
