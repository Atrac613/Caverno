import 'dart:convert';

import 'package:caverno/core/services/script_runtime/script_runtime.dart';
import 'package:caverno/features/chat/data/datasources/python_script_tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [ScriptRuntime] so the tool layer can be tested without the native
/// embedded interpreter.
class _FakeRuntime implements ScriptRuntime {
  _FakeRuntime(this._result);

  final ScriptRunResult _result;
  ScriptRunRequest? lastRequest;

  @override
  String get language => 'python';

  @override
  String get displayName => 'Python';

  @override
  bool get isSupported => true;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<ScriptRunResult> run(ScriptRunRequest request) async {
    lastRequest = request;
    return _result;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('tool schema exposes run_python_script with required code', () {
    final definition = PythonScriptTools.toolDefinition;
    expect(definition['type'], 'function');
    final function = definition['function'] as Map<String, dynamic>;
    expect(function['name'], 'run_python_script');
    final params = function['parameters'] as Map<String, dynamic>;
    expect(params['required'] as List, contains('code'));
  });

  test('execute maps output and forwards code/inputs/timeout', () async {
    final runtime = _FakeRuntime(
      const ScriptRunResult(stdout: 'hi\n', result: {'a': 1}),
    );

    final json = await PythonScriptTools.execute(
      runtime: runtime,
      arguments: {
        'code': 'print("hi")',
        'working_directory': '/tmp/run',
        'inputs': [
          {'name': 'a.jpg', 'path': '/tmp/run/a.jpg', 'mime': 'image/jpeg'},
        ],
        'timeout_seconds': 5,
      },
    );

    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['language'], 'python');
    expect(decoded['stdout'], 'hi\n');
    expect(decoded['result'], {'a': 1});

    final request = runtime.lastRequest!;
    expect(request.code, 'print("hi")');
    expect(request.workingDirectory, '/tmp/run');
    expect(request.inputs.single.name, 'a.jpg');
    expect(request.inputs.single.path, '/tmp/run/a.jpg');
    expect(request.timeout, const Duration(seconds: 5));
  });

  test('execute rejects empty code without touching the runtime', () async {
    final runtime = _FakeRuntime(const ScriptRunResult());
    final json = await PythonScriptTools.execute(
      runtime: runtime,
      arguments: {'code': '   '},
    );
    expect((jsonDecode(json) as Map)['error'], 'code is required');
    expect(runtime.lastRequest, isNull);
  });

  test('execute surfaces error and timed_out flags', () async {
    final runtime = _FakeRuntime(
      const ScriptRunResult(error: 'ValueError: boom', timedOut: true),
    );
    final json = await PythonScriptTools.execute(
      runtime: runtime,
      arguments: {'code': 'raise ValueError("boom")'},
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['error'], 'ValueError: boom');
    expect(decoded['timed_out'], true);
  });

  test('execute clamps an oversized timeout to the maximum', () async {
    final runtime = _FakeRuntime(const ScriptRunResult());
    await PythonScriptTools.execute(
      runtime: runtime,
      arguments: {'code': 'pass', 'timeout_seconds': 100000},
    );
    expect(runtime.lastRequest!.timeout, const Duration(seconds: 120));
  });
}
