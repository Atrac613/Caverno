import 'dart:convert';

import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/features/chat/data/datasources/built_in_browser_tool_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BuiltInBrowserToolHandler', () {
    test('owns the exact ordered family and schemas', () {
      final unavailable = BuiltInBrowserToolHandler();
      final available = BuiltInBrowserToolHandler(
        browserService: _FakeBrowserSessionService(),
      );

      expect(BuiltInBrowserToolHandler.toolNames, const [
        'browser_open',
        'browser_snapshot',
        'browser_get_content',
        'browser_screenshot',
        'browser_wait',
        'browser_navigate_history',
        'browser_close',
        'browser_fill',
        'browser_click',
        'browser_submit',
        'browser_eval',
        'browser_save_data',
      ]);
      expect(
        available.definitions.map(_definitionName),
        BuiltInBrowserToolHandler.toolNames,
      );
      expect(unavailable.isAvailable, isFalse);
      expect(available.isAvailable, isTrue);
      expect(available.handles('browser_click'), isTrue);
      expect(available.handles('browser_export_state'), isTrue);
      expect(available.handles('web_search'), isFalse);
      expect(_required(available.definitions[0]), ['url']);
      expect(_required(available.definitions[7]), ['value']);
      expect(_required(available.definitions[10]), ['script']);
      expect(_required(available.definitions[11]), ['filename', 'data']);
    });

    test('returns the existing unavailable result for the namespace', () async {
      final handler = BuiltInBrowserToolHandler();

      for (final name in ['browser_open', 'browser_export_state']) {
        final result = await handler.execute(name: name, arguments: const {});
        expect(result.toolName, name);
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'Built-in browser tools are unavailable');
      }
    });

    test('preserves browser argument normalization and defaults', () async {
      final service = _FakeBrowserSessionService();
      final handler = BuiltInBrowserToolHandler(browserService: service);

      await handler.execute(
        name: 'browser_wait',
        arguments: const {'selector': '  #ready  ', 'timeout_ms': 250.9},
      );
      await handler.execute(
        name: 'browser_fill',
        arguments: const {'ref': '12', 'selector': '  ', 'value': 'query'},
      );
      await handler.execute(
        name: 'browser_click',
        arguments: const {'ref': 4.7, 'selector': '  button.submit  '},
      );
      await handler.execute(name: 'browser_save_data', arguments: const {});

      expect(service.calls.map((call) => call.name), [
        'browser_wait',
        'browser_fill',
        'browser_click',
        'browser_save_data',
      ]);
      expect(service.calls.map((call) => call.arguments), [
        <String, dynamic>{'selector': '#ready', 'timeout_ms': 250},
        <String, dynamic>{'ref': 12, 'selector': null, 'value': 'query'},
        <String, dynamic>{'ref': 4, 'selector': 'button.submit'},
        <String, dynamic>{
          'filename': 'browser_data',
          'data': '',
          'format': 'json',
          'destination': null,
        },
      ]);
    });

    test(
      'normalizes success, failure, fallback, and unknown results',
      () async {
        final service = _FakeBrowserSessionService(
          results: const {
            'browser_open': 'plain result',
            'browser_get_content': '{"ok":false,"error":"content failed"}',
            'browser_screenshot': '{"ok":false}',
          },
        );
        final handler = BuiltInBrowserToolHandler(browserService: service);

        final success = await handler.execute(
          name: 'browser_open',
          arguments: const {'url': 'https://example.com'},
        );
        final failed = await handler.execute(
          name: 'browser_get_content',
          arguments: const {},
        );
        final fallback = await handler.execute(
          name: 'browser_screenshot',
          arguments: const {},
        );
        final unknown = await handler.execute(
          name: 'browser_export_state',
          arguments: const {},
        );

        expect(success.isSuccess, isTrue);
        expect(success.result, 'plain result');
        expect(failed.isSuccess, isFalse);
        expect(failed.errorMessage, 'content failed');
        expect(fallback.isSuccess, isFalse);
        expect(fallback.errorMessage, 'Browser tool failed');
        expect(unknown.isSuccess, isFalse);
        expect(jsonDecode(unknown.result), {
          'ok': false,
          'code': 'tool_not_available',
          'error':
              'No matching browser tool is available: browser_export_state',
        });
      },
    );

    test('preserves browser service exceptions', () async {
      final handler = BuiltInBrowserToolHandler(
        browserService: _FakeBrowserSessionService(
          errors: {'browser_eval': StateError('evaluation failed')},
        ),
      );

      await expectLater(
        handler.execute(
          name: 'browser_eval',
          arguments: const {'script': 'return 1'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'evaluation failed',
          ),
        ),
      );
    });
  });
}

String _definitionName(Map<String, dynamic> tool) {
  return (tool['function']! as Map<String, dynamic>)['name']! as String;
}

List<dynamic> _required(Map<String, dynamic> tool) {
  final function = tool['function']! as Map<String, dynamic>;
  final parameters = function['parameters']! as Map<String, dynamic>;
  return parameters['required'] as List<dynamic>? ?? const <dynamic>[];
}

final class _FakeBrowserSessionService extends BrowserSessionService {
  _FakeBrowserSessionService({this.results = const {}, this.errors = const {}});

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
  Future<String> openUrl(String url) async {
    return _record('browser_open', {'url': url});
  }

  @override
  Future<String> snapshot({int? maxElements}) async {
    return _record('browser_snapshot', {'max_elements': maxElements});
  }

  @override
  Future<String> getContent({String format = 'text', int? maxChars}) async {
    return _record('browser_get_content', {
      'format': format,
      'max_chars': maxChars,
    });
  }

  @override
  Future<String> screenshot() async {
    return _record('browser_screenshot', {});
  }

  @override
  Future<String> waitFor({String? selector, int? timeoutMs}) async {
    return _record('browser_wait', {
      'selector': selector,
      'timeout_ms': timeoutMs,
    });
  }

  @override
  Future<String> navigateHistory(String direction) async {
    return _record('browser_navigate_history', {'direction': direction});
  }

  @override
  String closePanel() {
    return _record('browser_close', {});
  }

  @override
  Future<String> fillField({
    int? ref,
    String? selector,
    required String value,
  }) async {
    return _record('browser_fill', {
      'ref': ref,
      'selector': selector,
      'value': value,
    });
  }

  @override
  Future<String> clickElement({int? ref, String? selector}) async {
    return _record('browser_click', {'ref': ref, 'selector': selector});
  }

  @override
  Future<String> submitForm({String? selector}) async {
    return _record('browser_submit', {'selector': selector});
  }

  @override
  Future<String> evaluateJs(String script) async {
    return _record('browser_eval', {'script': script});
  }

  @override
  Future<String> saveData({
    required String filename,
    required String data,
    String format = 'json',
    String? destination,
  }) async {
    return _record('browser_save_data', {
      'filename': filename,
      'data': data,
      'format': format,
      'destination': destination,
    });
  }
}
