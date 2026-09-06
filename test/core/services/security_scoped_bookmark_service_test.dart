import 'package:caverno/core/services/security_scoped_bookmark_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannel channel;
  late List<MethodCall> calls;

  setUp(() {
    channel = const MethodChannel('test.caverno/security_scoped_bookmarks');
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'pickDirectory':
              return <String, Object?>{
                'path': '/tmp/picked-project',
                'bookmark': 'bookmark-from-panel',
              };
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('macOS pickDirectory uses the bookmark channel', () async {
    final service = SecurityScopedBookmarkService(
      channel: channel,
      isMacOS: true,
      fallbackDirectoryPicker: ({String? initialDirectory}) async {
        fail('macOS should not fall back to FilePicker');
      },
    );

    final pick = await service.pickDirectory(
      initialDirectory: '/Users/me/Projects',
    );

    expect(pick.path, '/tmp/picked-project');
    expect(pick.bookmark, 'bookmark-from-panel');
    expect(pick.error, isNull);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'pickDirectory');
    expect(calls.single.arguments, {'initialDirectory': '/Users/me/Projects'});
  });

  test('non-macOS pickDirectory uses the fallback picker', () async {
    String? fallbackInitialDirectory;
    final service = SecurityScopedBookmarkService(
      channel: channel,
      isMacOS: false,
      fallbackDirectoryPicker: ({String? initialDirectory}) async {
        fallbackInitialDirectory = initialDirectory;
        return '/tmp/fallback-project';
      },
    );

    final pick = await service.pickDirectory(initialDirectory: '/tmp');

    expect(pick.path, '/tmp/fallback-project');
    expect(pick.bookmark, isNull);
    expect(pick.isCancelled, isFalse);
    expect(fallbackInitialDirectory, '/tmp');
    expect(calls, isEmpty);
  });

  test(
    'macOS pickDirectory returns cancelled when the user dismisses',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });

      final service = SecurityScopedBookmarkService(
        channel: channel,
        isMacOS: true,
        fallbackDirectoryPicker: ({String? initialDirectory}) async {
          fail('a cancelled macOS picker must not fall back to FilePicker');
        },
      );

      final pick = await service.pickDirectory();
      expect(pick.isCancelled, isTrue);
      expect(pick.error, isNull);
      expect(calls.single.method, 'pickDirectory');
    },
  );

  test(
    'macOS pickDirectory reports native errors separately from cancel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'picker_busy',
              message: 'A directory picker is already open.',
            );
          });

      final service = SecurityScopedBookmarkService(
        channel: channel,
        isMacOS: true,
        fallbackDirectoryPicker: ({String? initialDirectory}) async {
          fail('a failed macOS picker must not fall back to FilePicker');
        },
      );

      final pick = await service.pickDirectory();
      expect(pick.isCancelled, isFalse);
      expect(pick.path, isNull);
      expect(pick.error, 'A directory picker is already open.');
    },
  );

  test('macOS pickDirectory falls back when the plugin is missing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw MissingPluginException('not implemented');
        });

    final service = SecurityScopedBookmarkService(
      channel: channel,
      isMacOS: true,
      fallbackDirectoryPicker: ({String? initialDirectory}) async {
        return '/tmp/missing-plugin-fallback';
      },
    );

    final pick = await service.pickDirectory();
    expect(pick.path, '/tmp/missing-plugin-fallback');
    expect(pick.error, isNull);
  });

  test(
    'macOS pickDirectory keeps a path when the panel bookmark fails',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return <String, Object?>{
              'path': '/tmp/picked-project',
              'bookmarkError': 'bookmark data unavailable',
            };
          });

      final service = SecurityScopedBookmarkService(
        channel: channel,
        isMacOS: true,
        fallbackDirectoryPicker: ({String? initialDirectory}) async {
          fail('a panel bookmark failure must not fall back to FilePicker');
        },
      );

      final pick = await service.pickDirectory();
      expect(pick.path, '/tmp/picked-project');
      expect(pick.bookmark, isNull);
      expect(pick.error, isNull);
      expect(pick.isCancelled, isFalse);
    },
  );

  test(
    'macOS pickDirectory treats a payload error as failure, not cancel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return <String, Object?>{'error': 'sheet failed to present'};
          });

      final service = SecurityScopedBookmarkService(
        channel: channel,
        isMacOS: true,
        fallbackDirectoryPicker: ({String? initialDirectory}) async {
          fail('a payload error must not fall back to FilePicker');
        },
      );

      final pick = await service.pickDirectory();
      expect(pick.isCancelled, isFalse);
      expect(pick.path, isNull);
      expect(pick.error, 'sheet failed to present');
    },
  );

  test('macOS pickDirectory rejects unexpected payloads', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return 42;
        });

    final service = SecurityScopedBookmarkService(
      channel: channel,
      isMacOS: true,
      fallbackDirectoryPicker: ({String? initialDirectory}) async {
        fail('an unexpected payload must not fall back to FilePicker');
      },
    );

    final pick = await service.pickDirectory();
    expect(pick.isCancelled, isFalse);
    expect(pick.error, 'Directory picker returned an unexpected result');
  });
}
