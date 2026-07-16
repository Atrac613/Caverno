import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'cli3_contention_soak_report.dart';

Future<Cli3ContentionSoakReport> runCli3ContentionSoak({
  required Directory dataRoot,
  Cli3ContentionSoakOptions options = const Cli3ContentionSoakOptions(),
  String? workerScriptPath,
}) async {
  _validateOptions(options);
  await dataRoot.create(recursive: true);
  final workspace = Directory.fromUri(dataRoot.uri.resolve('workspace/'));
  await workspace.create(recursive: true);
  final scriptPath = workerScriptPath ?? _resolveWorkerScriptPath();
  final workers = <_ContentionWorkerProcess>[];
  try {
    for (var index = 0; index < options.workers; index += 1) {
      workers.add(
        await _ContentionWorkerProcess.start(
          scriptPath: scriptPath,
          dataRoot: dataRoot,
          workspace: workspace,
          frontend: index.isEven ? 'flutterGui' : 'terminal',
          options: options,
        ),
      );
    }
    await Future.wait(
      workers.map((worker) => worker.ready),
    ).timeout(const Duration(seconds: 30));
    final stopwatch = Stopwatch()..start();
    for (final worker in workers) {
      worker.startWork();
    }
    final overallTimeout = Duration(
      milliseconds: max(
        30000,
        options.operationTimeout.inMilliseconds * options.iterations * 2,
      ),
    );
    final results = await Future.wait(
      workers.map((worker) => worker.result),
    ).timeout(overallTimeout);
    await Future.wait(workers.map((worker) => worker.expectCleanExit()));
    stopwatch.stop();
    return Cli3ContentionSoakReport(
      options: options,
      workers: results,
      elapsed: stopwatch.elapsed,
    );
  } finally {
    await Future.wait(workers.map((worker) => worker.dispose()));
  }
}

Future<void> main(List<String> arguments) async {
  late final _CliArguments parsed;
  try {
    parsed = _CliArguments.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  if (parsed.showHelp) {
    stdout.writeln(_usage);
    return;
  }

  Directory? temporaryRoot;
  try {
    final dataRoot = parsed.dataRoot == null
        ? temporaryRoot = await Directory.systemTemp.createTemp(
            'caverno_cli3_contention_',
          )
        : Directory(parsed.dataRoot!);
    final report = await runCli3ContentionSoak(
      dataRoot: dataRoot,
      options: parsed.options,
    );
    final jsonText = const JsonEncoder.withIndent(' ').convert(report.toJson());
    await _writeOutput(parsed.outJson, jsonText, fallbackToStdout: true);
    await _writeOutput(parsed.outMarkdown, report.toMarkdown());
    if (!report.passed) {
      exitCode = 1;
    }
  } finally {
    if (temporaryRoot != null && await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  }
}

final class _ContentionWorkerProcess {
  _ContentionWorkerProcess._(this.process) {
    process.stderr.transform(utf8.decoder).listen(_stderr.write);
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _completeError, onDone: _handleDone);
  }

  static Future<_ContentionWorkerProcess> start({
    required String scriptPath,
    required Directory dataRoot,
    required Directory workspace,
    required String frontend,
    required Cli3ContentionSoakOptions options,
  }) async {
    final process = await Process.start(_dartToolExecutable(), <String>[
      scriptPath,
      dataRoot.path,
      workspace.path,
      frontend,
      options.workers.toString(),
      options.iterations.toString(),
      options.hold.inMilliseconds.toString(),
      options.operationTimeout.inMilliseconds.toString(),
      options.retryInterval.inMilliseconds.toString(),
      options.maxP95Milliseconds.toString(),
    ], workingDirectory: Directory.current.path);
    return _ContentionWorkerProcess._(process);
  }

  final Process process;
  final StringBuffer _stderr = StringBuffer();
  final Completer<void> _ready = Completer<void>();
  final Completer<Cli3ContentionWorkerResult> _result =
      Completer<Cli3ContentionWorkerResult>();
  bool _disposed = false;

  Future<void> get ready => _ready.future;
  Future<Cli3ContentionWorkerResult> get result => _result.future;

  void startWork() {
    process.stdin.writeln('start');
  }

  void _handleLine(String line) {
    try {
      final event = jsonDecode(line) as Map<String, dynamic>;
      switch (event['event']) {
        case 'ready':
          if (!_ready.isCompleted) {
            _ready.complete();
          }
        case 'result':
          final result = event['result'];
          if (result is! Map<String, dynamic>) {
            throw const FormatException('Worker result must be an object.');
          }
          if (!_result.isCompleted) {
            _result.complete(Cli3ContentionWorkerResult.fromJson(result));
          }
        default:
          throw FormatException('Unknown worker event: ${event['event']}');
      }
    } on Object catch (error, stackTrace) {
      _completeError(error, stackTrace);
    }
  }

  void _handleDone() {
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError('Worker exited before ready. ${_stderr.toString()}'),
      );
    }
    if (!_result.isCompleted) {
      _result.completeError(
        StateError('Worker exited before reporting. ${_stderr.toString()}'),
      );
    }
  }

  void _completeError(Object error, [StackTrace? stackTrace]) {
    if (!_ready.isCompleted) {
      _ready.completeError(error, stackTrace);
    }
    if (!_result.isCompleted) {
      _result.completeError(error, stackTrace);
    }
  }

  Future<void> expectCleanExit() async {
    final code = await process.exitCode;
    if (code != 0) {
      throw StateError('Contention worker exited $code. ${_stderr.toString()}');
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(milliseconds: 250),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return process.exitCode;
      },
    );
  }
}

final class _CliArguments {
  const _CliArguments({
    required this.options,
    required this.showHelp,
    this.dataRoot,
    this.outJson,
    this.outMarkdown,
  });

  factory _CliArguments.parse(List<String> arguments) {
    var showHelp = false;
    String? dataRoot;
    String? outJson;
    String? outMarkdown;
    var workers = 2;
    var iterations = 100;
    var holdMs = 2;
    var timeoutMs = 5000;
    var retryMs = 1;
    var maxP95Ms = 250.0;

    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      String value() {
        index += 1;
        if (index >= arguments.length) {
          throw FormatException('$argument requires a value.');
        }
        return arguments[index];
      }

      switch (argument) {
        case '--help':
        case '-h':
          showHelp = true;
        case '--data-root':
          dataRoot = value();
        case '--workers':
          workers = _positiveInt(value(), argument, minimum: 2);
        case '--iterations':
          iterations = _positiveInt(value(), argument);
        case '--hold-ms':
          holdMs = _positiveInt(value(), argument);
        case '--timeout-ms':
          timeoutMs = _positiveInt(value(), argument);
        case '--retry-ms':
          retryMs = _positiveInt(value(), argument);
        case '--max-p95-ms':
          maxP95Ms = double.tryParse(value()) ?? -1;
          if (maxP95Ms <= 0) {
            throw FormatException('$argument must be greater than zero.');
          }
        case '--out-json':
          outJson = value();
        case '--out-md':
          outMarkdown = value();
        default:
          throw FormatException('Unknown argument: $argument');
      }
    }
    return _CliArguments(
      options: Cli3ContentionSoakOptions(
        workers: workers,
        iterations: iterations,
        hold: Duration(milliseconds: holdMs),
        operationTimeout: Duration(milliseconds: timeoutMs),
        retryInterval: Duration(milliseconds: retryMs),
        maxP95Milliseconds: maxP95Ms,
      ),
      showHelp: showHelp,
      dataRoot: dataRoot,
      outJson: outJson,
      outMarkdown: outMarkdown,
    );
  }

  final Cli3ContentionSoakOptions options;
  final bool showHelp;
  final String? dataRoot;
  final String? outJson;
  final String? outMarkdown;
}

void _validateOptions(Cli3ContentionSoakOptions options) {
  if (options.workers < 2 ||
      options.iterations <= 0 ||
      options.hold <= Duration.zero ||
      options.operationTimeout <= Duration.zero ||
      options.retryInterval <= Duration.zero ||
      options.maxP95Milliseconds <= 0) {
    throw ArgumentError('Invalid CLI3 contention soak options.');
  }
}

Future<void> _writeOutput(
  String? path,
  String content, {
  bool fallbackToStdout = false,
}) async {
  if (path == null) {
    if (fallbackToStdout) {
      stdout.writeln(content);
    }
    return;
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

String _resolveWorkerScriptPath() => File(
  '${Directory.current.path}${Platform.pathSeparator}tool'
  '${Platform.pathSeparator}cli3_contention_soak_worker.dart',
).path;

String _dartToolExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final flutterRoots = <String>[
    Directory.current.uri.resolve('.fvm/flutter_sdk/').toFilePath(),
    if ((Platform.environment['FLUTTER_ROOT'] ?? '').trim().isNotEmpty)
      Platform.environment['FLUTTER_ROOT']!.trim(),
  ];
  for (final flutterRoot in flutterRoots) {
    final candidate = File.fromUri(
      Directory(
        flutterRoot,
      ).uri.resolve('bin/cache/dart-sdk/bin/$executableName'),
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  return Platform.resolvedExecutable;
}

int _positiveInt(String value, String option, {int minimum = 1}) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < minimum) {
    throw FormatException('$option must be at least $minimum.');
  }
  return parsed;
}

const _usage = '''
Usage: dart run tool/cli3_contention_soak.dart [options]

Options:
  --workers <count>       Separate workers. Default: 2.
  --iterations <count>    Iterations per worker. Default: 100.
  --hold-ms <ms>          Lease hold time. Default: 2.
  --timeout-ms <ms>       Per-operation timeout. Default: 5000.
  --retry-ms <ms>         Conflict retry interval. Default: 1.
  --max-p95-ms <ms>       Direct-lock p95 threshold. Default: 250.
  --data-root <path>      Optional temporary lease root.
  --out-json <path>       Write the schema-versioned JSON report.
  --out-md <path>         Write the Markdown report.
  --help                  Print this help.
''';
