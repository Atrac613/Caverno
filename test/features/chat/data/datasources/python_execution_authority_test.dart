import 'dart:async';

import 'package:caverno/features/chat/data/datasources/python_execution_authority.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:test/test.dart';

void main() {
  group('PythonExecutionAuthority', () {
    test('consumes an exact permit once and releases in two phases', () async {
      final authority = PythonExecutionAuthority<String>();
      final owner = _owner();
      final permit = authority
          .reserve(
            owner: owner,
            identity: 'exact-execution',
            ownerIsCurrent: () => true,
          )
          .permit!;

      final result = await permit.runEffect(() async => 'completed');

      expect(result, 'completed');
      expect(authority.acknowledgeExecution(permit), isTrue);
      expect(authority.acknowledgeCleanup(permit), isTrue);
      expect(authority.prepareRelease(permit), isTrue);
      expect(authority.release(permit), isTrue);
      expect(authority.pendingRecovery, isNull);
      expect(
        () => permit.runEffect(() async => 'replayed'),
        throwsA(isA<PythonExecutionEffectPermitExpired>()),
      );
    });

    test('does not clear a receipt while its effect is still active', () async {
      final authority = PythonExecutionAuthority<String>();
      final permit = authority
          .reserve(
            owner: _owner(),
            identity: 'in-flight-execution',
            ownerIsCurrent: () => true,
          )
          .permit!;
      final started = Completer<void>();
      final release = Completer<void>();
      final pending = permit.runEffect(() async {
        started.complete();
        await release.future;
      });
      await started.future;

      final receipt = authority.retainRecovery(permit)!;

      expect(authority.pendingRecovery, same(receipt));
      expect(authority.clearRecovery(receipt), isFalse);
      release.complete();
      await pending;
      expect(authority.clearRecovery(receipt), isTrue);
    });

    test('rejects a foreign receipt with the same public identity', () async {
      final first = PythonExecutionAuthority<String>();
      final firstPermit = first
          .reserve(
            owner: _owner(),
            identity: 'shared-identity',
            ownerIsCurrent: () => true,
          )
          .permit!;
      await firstPermit.runEffect(() async {});
      final receipt = first.retainRecovery(firstPermit)!;

      final second = PythonExecutionAuthority<String>();
      final secondPermit = second
          .reserve(
            owner: _owner(),
            identity: 'shared-identity',
            ownerIsCurrent: () => true,
          )
          .permit!;
      await secondPermit.runEffect(() async {});
      final foreignReceipt = second.retainRecovery(secondPermit)!;

      expect(first.clearRecovery(foreignReceipt), isFalse);
      expect(
        first.reconcileRecovery(
          receipt: receipt,
          observedIdentity: 'different-identity',
        ),
        isFalse,
      );
      expect(first.pendingRecovery, same(receipt));
    });
  });
}

ChatTurnOwner _owner() {
  return ChatTurnOwner(
    conversationId: 'python-authority-conversation',
    interactionGeneration: 3,
  );
}
