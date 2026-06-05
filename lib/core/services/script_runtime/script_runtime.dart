import 'dart:async';

/// A single input file staged for a script run (typically a chat attachment
/// such as an image the user asked the model to analyze).
class ScriptInput {
  const ScriptInput({required this.name, required this.path, this.mime});

  final String name;
  final String path;
  final String? mime;

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    if (mime != null) 'mime': mime,
  };
}

/// A request to execute a snippet in a [ScriptRuntime].
class ScriptRunRequest {
  const ScriptRunRequest({
    required this.code,
    this.inputs = const [],
    this.workingDirectory,
    this.timeout = const Duration(seconds: 60),
  });

  final String code;
  final List<ScriptInput> inputs;

  /// Absolute directory the script runs in. Staged [inputs] live here.
  final String? workingDirectory;
  final Duration timeout;
}

/// The captured outcome of a [ScriptRunRequest].
class ScriptRunResult {
  const ScriptRunResult({
    this.stdout = '',
    this.stderr = '',
    this.result,
    this.error,
    this.traceback,
    this.timedOut = false,
  });

  final String stdout;
  final String stderr;

  /// Structured value the script handed back via the host helper
  /// (e.g. Python `caverno.set_output(...)`). JSON-serializable or null.
  final Object? result;

  /// `"ExcType: message"` when the script raised, otherwise null.
  final String? error;
  final String? traceback;
  final bool timedOut;

  bool get isError => error != null || timedOut;
}

/// A pluggable on-device script execution backend.
///
/// The MVP ships only [language] == "python", but the abstraction lets other
/// on-device languages (JS, Ruby, ...) be added behind the same chat tool
/// without touching the chat loop. Implementations own a long-lived runtime and
/// serialize jobs.
abstract class ScriptRuntime {
  /// Stable language id surfaced to the tool layer (e.g. "python").
  String get language;

  /// Human-readable label (e.g. "Python 3.12").
  String get displayName;

  /// Whether this runtime can run on the current platform.
  bool get isSupported;

  /// Start the runtime if it is not already running. Safe to call repeatedly;
  /// concurrent callers await the same startup.
  Future<void> ensureStarted();

  /// Execute [request] and return its captured result. Throws only on
  /// unexpected internal errors; script-level failures are reported via
  /// [ScriptRunResult.error] / [ScriptRunResult.timedOut].
  Future<ScriptRunResult> run(ScriptRunRequest request);

  /// Tear down the runtime and release resources.
  Future<void> dispose();
}

/// Resolves a [ScriptRuntime] by language. The MVP registers only Python.
class ScriptRuntimeRegistry {
  ScriptRuntimeRegistry(Iterable<ScriptRuntime> runtimes)
    : _runtimes = {for (final runtime in runtimes) runtime.language: runtime};

  static const String defaultLanguage = 'python';

  final Map<String, ScriptRuntime> _runtimes;

  ScriptRuntime? forLanguage(String language) => _runtimes[language];

  ScriptRuntime? get defaultRuntime => _runtimes[defaultLanguage];

  Iterable<ScriptRuntime> get all => _runtimes.values;

  Future<void> dispose() async {
    for (final runtime in _runtimes.values) {
      await runtime.dispose();
    }
  }
}
