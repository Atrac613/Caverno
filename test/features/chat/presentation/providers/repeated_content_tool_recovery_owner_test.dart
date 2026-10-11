import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop/repeated_content_tool_recovery_plan.dart';
import 'package:caverno/features/chat/presentation/providers/tool_dedupe_keys.dart';
import 'package:caverno/features/chat/presentation/providers/turn_tool_result_ledger.dart';
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = ChatTurnOwner(conversationId: 'a', interactionGeneration: 1);
  final b = ChatTurnOwner(conversationId: 'b', interactionGeneration: 1);
  final nextA = ChatTurnOwner(conversationId: 'a', interactionGeneration: 2);
  const repeat = ToolCallData(
    name: 'read_file',
    arguments: {'path': 'README.md'},
  );
  ToolResultInfo evidence(
    String id, {
    String path = 'README.md',
    String payload = 'ok',
  }) => ToolResultInfo(
    id: id,
    name: 'read_file',
    arguments: {'path': path},
    result: payload,
  );
  RepeatedContentToolRecoveryPlan? recover(
    TurnToolResultLedger ledger,
    ChatTurnOwner owner,
    List<String> selected,
  ) => RepeatedContentToolRecoveryPlan.assess(
    [repeat],
    previousSuccessfulResult: (call) {
      final key = ToolDedupeKeys.toolCall(
        call.name,
        call.arguments,
        projectRoot: '/fixture/project',
      );
      final previous = ledger.lastSuccessfulContentWhere(
        owner,
        (item) =>
            ToolDedupeKeys.toolResult(item, projectRoot: '/fixture/project') ==
            key,
      );
      if (previous != null) selected.add(previous.id);
      return previous;
    },
  );

  test(
    'reuses newest matching success while excluding failures and other owners',
    () {
      final ledger = TurnToolResultLedger()
        ..addContent(a, evidence('old'))
        ..addContent(a, evidence('new', path: '/fixture/project/README.md'))
        ..addContent(a, evidence('failed', payload: '{"error":"failed"}'))
        ..addContent(a, evidence('other-path', path: 'OTHER.md'))
        ..addContent(b, evidence('other-owner'));
      final selected = <String>[];
      expect(recover(ledger, a, selected), isNotNull);
      expect(selected, ['new']);
      expect(recover(ledger, nextA, selected), isNull);
      expect(ledger.content(a), hasLength(4));
      expect(ledger.content(b), hasLength(1));
    },
  );
  test(
    'completed evidence, failed content and mismatched paths are not reused',
    () {
      final ledger = TurnToolResultLedger()
        ..setCompleted(a, [evidence('completed')])
        ..addContent(a, evidence('failed', payload: '{"error":"failed"}'))
        ..addContent(a, evidence('other-path', path: 'OTHER.md'));
      final selected = <String>[];
      expect(recover(ledger, a, selected), isNull);
      expect(selected, isEmpty);
    },
  );
  test('expired or disposed owner evidence cannot be reused', () {
    var now = DateTime(2026);
    final ledger =
        TurnToolResultLedger(
            retention: const Duration(seconds: 1),
            now: () => now,
          )
          ..addContent(a, evidence('expired'))
          ..publish(a)
          ..addContent(b, evidence('disposed'));
    ledger.dispose(b);
    final selected = <String>[];
    expect(recover(ledger, b, selected), isNull);
    now = now.add(const Duration(seconds: 1));
    expect(recover(ledger, a, selected), isNull);
    expect(selected, isEmpty);
  });
}
