import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';

void main() {
  test('defaults to unknown so a missed entry point stays visible', () {
    expect(ModelUsageRole.current, ModelUsageRole.unknown);
  });

  test('is visible to the body it wraps', () {
    ModelUsageRole.planning.runWith(() {
      expect(ModelUsageRole.current, ModelUsageRole.planning);
    });
  });

  test('propagates into async continuations', () async {
    final seen = Completer<ModelUsageRole>();
    ModelUsageRole.routine.runWith(() async {
      await Future<void>.delayed(Duration.zero);
      seen.complete(ModelUsageRole.current);
    });
    expect(await seen.future, ModelUsageRole.routine);
  });

  test('an inner role overrides the turn it was started from', () async {
    // The regression this design exists for: memory extraction is launched with
    // unawaited(...) from inside a chat turn's zone, so without its own zone it
    // would be booked as chat.
    final seen = Completer<ModelUsageRole>();
    ModelUsageRole.chat.runWith(() {
      unawaited(
        Future<void>.microtask(() {
          ModelUsageRole.memoryExtraction.runWith(() {
            seen.complete(ModelUsageRole.current);
          });
        }),
      );
    });
    expect(await seen.future, ModelUsageRole.memoryExtraction);
  });

  test(
    'an unclaimed async escape from a turn stays attributed to it',
    () async {
      // Documents the inheritance that makes the explicit role necessary.
      final seen = Completer<ModelUsageRole>();
      ModelUsageRole.chat.runWith(() {
        unawaited(
          Future<void>.microtask(() => seen.complete(ModelUsageRole.current)),
        );
      });
      expect(await seen.future, ModelUsageRole.chat);
    },
  );

  test('fromName round-trips and falls back to unknown', () {
    for (final role in ModelUsageRole.values) {
      expect(ModelUsageRole.fromName(role.name), role);
    }
    expect(ModelUsageRole.fromName('not-a-role'), ModelUsageRole.unknown);
  });
}
