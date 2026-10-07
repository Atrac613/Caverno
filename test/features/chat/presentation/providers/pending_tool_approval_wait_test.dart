import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/approval_wait_ledger.dart';
import 'package:caverno/features/chat/presentation/providers/pending_tool_approvals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late ApprovalWaitLedger ledger;
  late PendingToolApprovalRegistry registry;
  final owner = ChatTurnOwner(conversationId: 'c1', interactionGeneration: 1);

  setUp(() {
    now = DateTime(2026, 10, 1, 9);
    ledger = ApprovalWaitLedger(clock: () => now);
    registry = PendingToolApprovalRegistry(waitLedger: ledger);
  });

  PendingFileOperation request(String id) => PendingFileOperation(
    owner: owner,
    id: id,
    operation: 'write',
    path: 'README.md',
    preview: '',
    reason: null,
    completer: Completer<bool>(),
  );

  test('times an approval until it is answered', () async {
    final pending = request('a1');
    registry.register(pending);
    now = now.add(const Duration(seconds: 30));
    expect(ledger.waitedMs('c1'), 30000);

    registry.take<PendingFileOperation>(owner: owner, id: 'a1');
    pending.completer.complete(true);
    await pending.completer.future;
    now = now.add(const Duration(seconds: 30));

    expect(ledger.waitedMs('c1'), 30000);
  });

  test('stops timing when the owner is cancelled', () async {
    final pending = request('a2');
    registry.register(pending);
    now = now.add(const Duration(seconds: 5));
    registry.cancelOwner(owner);
    await pending.completer.future;
    now = now.add(const Duration(minutes: 5));

    expect(ledger.waitedMs('c1'), 5000);
  });
}
