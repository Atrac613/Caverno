import 'dart:convert';

import 'package:caverno/core/services/macos_computer_use_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_computer_use_tool_handler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInComputerUseToolHandler', () {
    test('owns the exact ordered family and schemas', () {
      final unavailable = BuiltInComputerUseToolHandler();
      final available = BuiltInComputerUseToolHandler(
        computerUseService: _RecordingMacosComputerUseService(),
      );

      expect(BuiltInComputerUseToolHandler.toolNames, const [
        'computer_get_permissions',
        'computer_request_permissions',
        'computer_open_system_settings',
        'computer_vision_observe',
        'computer_accessibility_snapshot',
        'computer_list_displays',
        'computer_screenshot',
        'computer_list_windows',
        'computer_focus_window',
        'computer_screenshot_window',
        'computer_move_mouse',
        'computer_click',
        'computer_drag',
        'computer_scroll',
        'computer_type_text',
        'computer_press_key',
        'computer_switch_space',
        'computer_start_system_audio_recording',
        'computer_stop_system_audio_recording',
      ]);
      expect(
        available.definitions.map(_definitionName),
        BuiltInComputerUseToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(available.isAvailable, isTrue);
      expect(available.handles('computer_click'), isTrue);
      expect(available.handles('computer_custom_action'), isTrue);
      expect(available.handles('browser_click'), isFalse);
      expect(
        sha256
            .convert(utf8.encode(jsonEncode(available.definitions)))
            .toString(),
        'fb9b07ab383c7bb19676ef799b0173500eff7012d98d804a1cbaeeda0548d99e',
      );
    });

    test('returns the existing unavailable result for the namespace', () async {
      final handler = BuiltInComputerUseToolHandler();

      for (final name in [
        'computer_get_permissions',
        'computer_custom_action',
      ]) {
        final result = await handler.execute(name: name, arguments: const {});
        expect(result.toolName, name);
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'macOS computer use tools are unavailable');
      }
    });

    test('forwards every operation with compatible arguments', () async {
      final computerUse = _RecordingMacosComputerUseService();
      final handler = BuiltInComputerUseToolHandler(
        computerUseService: computerUse,
      );

      for (final name in BuiltInComputerUseToolHandler.toolNames) {
        final arguments = switch (name) {
          'computer_request_permissions' => <String, dynamic>{
            'accessibility': false,
            'screen_capture': false,
            'screenCapture': true,
          },
          'computer_open_system_settings' => <String, dynamic>{},
          _ => <String, dynamic>{'marker': name},
        };
        final result = await handler.execute(name: name, arguments: arguments);
        expect(result.isSuccess, isTrue);
      }

      expect(
        computerUse.calls.map((call) => call.name),
        BuiltInComputerUseToolHandler.toolNames,
      );
      expect(computerUse.calls[0].arguments, isEmpty);
      expect(computerUse.calls[1].arguments, {
        'accessibility': false,
        'screen_capture': false,
      });
      expect(computerUse.calls[2].arguments, {'section': 'privacy'});
      for (
        var index = 3;
        index < BuiltInComputerUseToolHandler.toolNames.length - 1;
        index += 1
      ) {
        expect(computerUse.calls[index].arguments, {
          'marker': BuiltInComputerUseToolHandler.toolNames[index],
        });
      }
      expect(computerUse.calls.last.arguments, isEmpty);

      await handler.execute(
        name: 'computer_request_permissions',
        arguments: const {},
      );
      await handler.execute(
        name: 'computer_request_permissions',
        arguments: const {'screenCapture': false},
      );
      expect(computerUse.calls[19].arguments, {
        'accessibility': true,
        'screen_capture': true,
      });
      expect(computerUse.calls[20].arguments, {
        'accessibility': true,
        'screen_capture': false,
      });
    });

    test('normalizes failures and preserves service exceptions', () async {
      final computerUse = _RecordingMacosComputerUseService(
        results: const {
          'computer_click': '{"ok":false,"error":"click failed"}',
          'computer_screenshot': '{"ok":false}',
        },
        errors: {'computer_drag': StateError('drag failed')},
      );
      final handler = BuiltInComputerUseToolHandler(
        computerUseService: computerUse,
      );

      final failed = await handler.execute(
        name: 'computer_click',
        arguments: const {},
      );
      final fallback = await handler.execute(
        name: 'computer_screenshot',
        arguments: const {},
      );
      final unknown = await handler.execute(
        name: 'computer_custom_action',
        arguments: const {},
      );

      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, 'click failed');
      expect(fallback.isSuccess, isFalse);
      expect(fallback.errorMessage, 'Computer use tool failed');
      expect(jsonDecode(unknown.result), {
        'ok': false,
        'code': 'tool_not_available',
        'error':
            'No matching computer use tool is available: computer_custom_action',
      });
      await expectLater(
        handler.execute(name: 'computer_drag', arguments: const {}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'drag failed',
          ),
        ),
      );
      await expectLater(
        handler.execute(
          name: 'computer_request_permissions',
          arguments: const {'accessibility': 1},
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });
}

String _definitionName(Map<String, dynamic> tool) {
  return (tool['function']! as Map<String, dynamic>)['name']! as String;
}

final class _RecordingMacosComputerUseService extends MacosComputerUseService {
  _RecordingMacosComputerUseService({
    this.results = const {},
    this.errors = const {},
  });

  final Map<String, String> results;
  final Map<String, Object> errors;
  final List<({String name, Map<String, dynamic> arguments})> calls = [];

  @override
  bool get isAvailable => true;

  String _record(String name, Map<String, dynamic> arguments) {
    calls.add((name: name, arguments: Map<String, dynamic>.from(arguments)));
    final error = errors[name];
    if (error != null) throw error;
    return results[name] ?? jsonEncode({'ok': true, 'tool': name});
  }

  @override
  Future<String> getPermissions() async {
    return _record('computer_get_permissions', {});
  }

  @override
  Future<String> requestPermissions({
    bool accessibility = true,
    bool screenCapture = true,
  }) async {
    return _record('computer_request_permissions', {
      'accessibility': accessibility,
      'screen_capture': screenCapture,
    });
  }

  @override
  Future<String> openSystemSettings({required String section}) async {
    return _record('computer_open_system_settings', {'section': section});
  }

  @override
  Future<String> visionObserve(Map<String, dynamic> arguments) async {
    return _record('computer_vision_observe', arguments);
  }

  @override
  Future<String> accessibilitySnapshot(Map<String, dynamic> arguments) async {
    return _record('computer_accessibility_snapshot', arguments);
  }

  @override
  Future<String> listDisplays(Map<String, dynamic> arguments) async {
    return _record('computer_list_displays', arguments);
  }

  @override
  Future<String> listWindows(Map<String, dynamic> arguments) async {
    return _record('computer_list_windows', arguments);
  }

  @override
  Future<String> focusWindow(Map<String, dynamic> arguments) async {
    return _record('computer_focus_window', arguments);
  }

  @override
  Future<String> screenshot(Map<String, dynamic> arguments) async {
    return _record('computer_screenshot', arguments);
  }

  @override
  Future<String> screenshotWindow(Map<String, dynamic> arguments) async {
    return _record('computer_screenshot_window', arguments);
  }

  @override
  Future<String> moveMouse(Map<String, dynamic> arguments) async {
    return _record('computer_move_mouse', arguments);
  }

  @override
  Future<String> click(Map<String, dynamic> arguments) async {
    return _record('computer_click', arguments);
  }

  @override
  Future<String> drag(Map<String, dynamic> arguments) async {
    return _record('computer_drag', arguments);
  }

  @override
  Future<String> scroll(Map<String, dynamic> arguments) async {
    return _record('computer_scroll', arguments);
  }

  @override
  Future<String> typeText(Map<String, dynamic> arguments) async {
    return _record('computer_type_text', arguments);
  }

  @override
  Future<String> switchSpace(Map<String, dynamic> arguments) async {
    return _record('computer_switch_space', arguments);
  }

  @override
  Future<String> pressKey(Map<String, dynamic> arguments) async {
    return _record('computer_press_key', arguments);
  }

  @override
  Future<String> startSystemAudioRecording(
    Map<String, dynamic> arguments,
  ) async {
    return _record('computer_start_system_audio_recording', arguments);
  }

  @override
  Future<String> stopSystemAudioRecording() async {
    return _record('computer_stop_system_audio_recording', {});
  }
}
