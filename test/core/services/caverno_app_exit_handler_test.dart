import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:caverno/core/services/caverno_app_exit_handler.dart';
import 'package:caverno/features/chat/application/persistence/caverno_persistence_bootstrap.dart';
import 'package:caverno/features/chat/data/datasources/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a successful close allows exit and runs the closer once', () async {
    var closeCount = 0;
    final handler = CavernoAppExitHandler(
      closePersistence: () async {
        closeCount += 1;
      },
    );

    expect(await handler.handleExitRequest(), AppExitResponse.exit);
    expect(await handler.handleExitRequest(), AppExitResponse.exit);

    expect(closeCount, 1);
    expect(handler.isClosed, isTrue);
  });

  test('missing closer is treated as already ready to exit', () async {
    final handler = CavernoAppExitHandler();

    expect(await handler.handleExitRequest(), AppExitResponse.exit);
    expect(handler.isClosed, isTrue);
  });

  test('handleExitRequest waits until persistence close finishes', () async {
    final allowClose = Completer<void>();
    var finished = false;
    final handler = CavernoAppExitHandler(
      closePersistence: () async {
        await allowClose.future;
        finished = true;
      },
    );

    final request = handler.handleExitRequest();
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);

    allowClose.complete();
    expect(await request, AppExitResponse.exit);
    expect(finished, isTrue);
    expect(handler.isClosed, isTrue);
  });

  test('a failed close refuses exit and can be retried', () async {
    var closeCount = 0;
    final handler = CavernoAppExitHandler(
      closePersistence: () async {
        closeCount += 1;
        if (closeCount == 1) {
          throw StateError('close failed');
        }
      },
    );

    expect(await handler.handleExitRequest(), AppExitResponse.cancel);
    expect(handler.isClosed, isFalse);
    expect(await handler.handleExitRequest(), AppExitResponse.exit);
    expect(handler.isClosed, isTrue);
    expect(closeCount, 2);
  });

  test('concurrent exit requests share one in-flight close', () async {
    final allowClose = Completer<void>();
    var closeCount = 0;
    final handler = CavernoAppExitHandler(
      closePersistence: () async {
        closeCount += 1;
        await allowClose.future;
      },
    );

    final first = handler.handleExitRequest();
    final second = handler.handleExitRequest();
    allowClose.complete();

    expect(await first, AppExitResponse.exit);
    expect(await second, AppExitResponse.exit);
    expect(closeCount, 1);
  });

  test(
    'a failed CavernoPersistenceStorage close stays retryable through the handler',
    () async {
      final database = AppDatabase.memory();
      var closeCount = 0;
      final storage = await const CavernoPersistenceBootstrap().open(
        openDatabase: () async => database,
        conversationsMigrated: true,
        chatMemoryMigrated: true,
        readLegacyConversations: () => throw StateError('unexpected read'),
        readLegacyChatMemory: () => throw StateError('unexpected read'),
        markConversationsMigrated: () => throw StateError('unexpected marker'),
        markChatMemoryMigrated: () => throw StateError('unexpected marker'),
        closeDatabase: (database) async {
          closeCount += 1;
          if (closeCount == 1) {
            throw StateError('close failed');
          }
          await database.close();
        },
      );
      final handler = CavernoAppExitHandler(closePersistence: storage.close);

      expect(await handler.handleExitRequest(), AppExitResponse.cancel);
      expect(handler.isClosed, isFalse);
      expect(await handler.handleExitRequest(), AppExitResponse.exit);
      expect(handler.isClosed, isTrue);
      expect(closeCount, 2);
    },
  );

  test('cancelled exit restarts paused maintenance', () async {
    final events = <String>[];
    final handler = CavernoAppExitHandler(
      closePersistence: () async {
        events.add('close');
        throw StateError('close failed');
      },
    );

    final response = await withMaintenancePausedForExit(
      stopMaintenance: () => events.add('stop'),
      startMaintenance: () => events.add('start'),
      requestExit: handler.handleExitRequest,
    );

    expect(response, AppExitResponse.cancel);
    expect(events, ['stop', 'close', 'start']);
  });

  test('successful exit leaves maintenance stopped', () async {
    final events = <String>[];
    final handler = CavernoAppExitHandler(
      closePersistence: () async {
        events.add('close');
      },
    );

    final response = await withMaintenancePausedForExit(
      stopMaintenance: () => events.add('stop'),
      startMaintenance: () => events.add('start'),
      requestExit: handler.handleExitRequest,
    );

    expect(response, AppExitResponse.exit);
    expect(events, ['stop', 'close']);
  });
}
