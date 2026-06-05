import 'dart:convert';

import '../../../../core/services/script_runtime/script_runtime.dart';

/// Built-in `run_python_script` tool.
///
/// Lets the model write and run Python on-device (via the embedded interpreter
/// behind [ScriptRuntime]) to compute answers it cannot derive directly —
/// parsing files, analyzing attached media, data crunching, math, etc. The
/// schema only exposes `code` (plus an optional timeout/reason); the chat
/// handler injects the staged `working_directory` and attachment `inputs`.
class PythonScriptTools {
  PythonScriptTools._();

  static const int _maxOutputChars = 12000;
  static const int _defaultTimeoutSeconds = 60;
  static const int _maxTimeoutSeconds = 120;

  static Map<String, dynamic> get toolDefinition => {
    'type': 'function',
    'function': {
      'name': 'run_python_script',
      'description':
          'Execute a Python 3 script on the device and capture its stdout, '
          'stderr and any structured result. Use this to compute answers you '
          'cannot derive directly: parsing or analyzing files, inspecting an '
          'attached image (e.g. metadata/EXIF), data processing, math, etc. '
          'Write a complete script that prints its findings. Files the user '
          'attached to the current message are exposed through an injected '
          '`caverno` helper: `caverno.inputs` is a list whose items have '
          '`.name`, `.path`, `.read_bytes()` and `.read_text()`. Return a '
          'structured value with `caverno.set_output(value)`. Only the Python '
          'standard library is guaranteed available; any extra package must be '
          'pure-Python and bundled. The script may read files and use the '
          'network.',
      'parameters': {
        'type': 'object',
        'properties': {
          'code': {
            'type': 'string',
            'description':
                'Complete Python 3 source to execute. Print results to stdout '
                'and/or call caverno.set_output(value).',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description':
                'Optional wall-clock limit in seconds (default '
                '$_defaultTimeoutSeconds, max $_maxTimeoutSeconds).',
          },
          'reason': {
            'type': 'string',
            'description':
                'Short human-readable reason for running this script, shown to '
                'the user in the approval prompt.',
          },
        },
        'required': ['code'],
      },
    },
  };

  /// Runs [arguments] against [runtime] and returns a JSON string mirroring the
  /// local shell tool's shape (stdout/stderr/result/error/timed_out).
  static Future<String> execute({
    required ScriptRuntime runtime,
    required Map<String, dynamic> arguments,
  }) async {
    final code = (arguments['code'] as String?)?.trim() ?? '';
    if (code.isEmpty) {
      return jsonEncode({'error': 'code is required'});
    }

    final requestedTimeout =
        (arguments['timeout_seconds'] as num?)?.toInt() ??
        _defaultTimeoutSeconds;
    final timeoutSeconds = requestedTimeout.clamp(1, _maxTimeoutSeconds).toInt();

    final workingDirectory = (arguments['working_directory'] as String?)?.trim();
    final inputs = _parseInputs(arguments['inputs']);

    final result = await runtime.run(
      ScriptRunRequest(
        code: code,
        inputs: inputs,
        workingDirectory:
            (workingDirectory != null && workingDirectory.isNotEmpty)
            ? workingDirectory
            : null,
        timeout: Duration(seconds: timeoutSeconds),
      ),
    );

    final stdout = _truncate(result.stdout);
    final stderr = _truncate(result.stderr);
    return jsonEncode({
      'language': runtime.language,
      'stdout': stdout,
      'stderr': stderr,
      if (result.result != null) 'result': result.result,
      if (result.error != null) 'error': result.error,
      if (result.traceback != null) 'traceback': _truncate(result.traceback!),
      if (result.timedOut) 'timed_out': true,
      if (stdout.length < result.stdout.length) 'stdout_truncated': true,
      if (stderr.length < result.stderr.length) 'stderr_truncated': true,
    });
  }

  /// Parses the host-injected `inputs` argument (staged attachment files).
  static List<ScriptInput> _parseInputs(Object? raw) {
    if (raw is! List) return const [];
    final inputs = <ScriptInput>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final path = (item['path'] as String?)?.trim() ?? '';
      if (path.isEmpty) continue;
      inputs.add(
        ScriptInput(
          name: (item['name'] as String?)?.trim() ?? path.split('/').last,
          path: path,
          mime: item['mime'] as String?,
        ),
      );
    }
    return inputs;
  }

  static String _truncate(String text) => text.length > _maxOutputChars
      ? text.substring(0, _maxOutputChars)
      : text;
}
