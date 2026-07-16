import 'dart:math';

const cli3ContentionSoakSchema = 'caverno_cli3_contention_soak_report';
const cli3ContentionSoakSchemaVersion = 1;

final class Cli3ContentionSoakOptions {
  const Cli3ContentionSoakOptions({
    this.workers = 2,
    this.iterations = 100,
    this.hold = const Duration(milliseconds: 2),
    this.operationTimeout = const Duration(seconds: 5),
    this.retryInterval = const Duration(milliseconds: 1),
    this.maxP95Milliseconds = 250,
  });

  final int workers;
  final int iterations;
  final Duration hold;
  final Duration operationTimeout;
  final Duration retryInterval;
  final double maxP95Milliseconds;

  int get expectedOperationsPerResource => workers * iterations;

  Map<String, Object> toJson() => <String, Object>{
    'workers': workers,
    'iterationsPerWorker': iterations,
    'holdMs': hold.inMilliseconds,
    'operationTimeoutMs': operationTimeout.inMilliseconds,
    'retryIntervalMs': retryInterval.inMilliseconds,
    'maxP95Ms': maxP95Milliseconds,
  };
}

final class Cli3ContentionWorkerResult {
  const Cli3ContentionWorkerResult({
    required this.frontend,
    required this.processId,
    required this.runtimeSuccesses,
    required this.runtimeConflicts,
    required this.runtimeTimeouts,
    required this.runtimeWaitMicros,
    required this.memorySuccesses,
    required this.memoryTimeouts,
    required this.memoryOperationMicros,
    required this.genericOwnerDiagnostics,
    required this.invalidOwnerDiagnostics,
  });

  factory Cli3ContentionWorkerResult.fromJson(Map<String, dynamic> json) {
    return Cli3ContentionWorkerResult(
      frontend: json['frontend'] as String,
      processId: json['processId'] as int,
      runtimeSuccesses: json['runtimeSuccesses'] as int,
      runtimeConflicts: json['runtimeConflicts'] as int,
      runtimeTimeouts: json['runtimeTimeouts'] as int,
      runtimeWaitMicros: _intList(json['runtimeWaitMicros']),
      memorySuccesses: json['memorySuccesses'] as int,
      memoryTimeouts: json['memoryTimeouts'] as int,
      memoryOperationMicros: _intList(json['memoryOperationMicros']),
      genericOwnerDiagnostics: json['genericOwnerDiagnostics'] as int,
      invalidOwnerDiagnostics: json['invalidOwnerDiagnostics'] as int,
    );
  }

  final String frontend;
  final int processId;
  final int runtimeSuccesses;
  final int runtimeConflicts;
  final int runtimeTimeouts;
  final List<int> runtimeWaitMicros;
  final int memorySuccesses;
  final int memoryTimeouts;
  final List<int> memoryOperationMicros;
  final int genericOwnerDiagnostics;
  final int invalidOwnerDiagnostics;

  Map<String, Object> toJson() => <String, Object>{
    'frontend': frontend,
    'processId': processId,
    'runtimeSuccesses': runtimeSuccesses,
    'runtimeConflicts': runtimeConflicts,
    'runtimeTimeouts': runtimeTimeouts,
    'runtimeWaitMicros': runtimeWaitMicros,
    'memorySuccesses': memorySuccesses,
    'memoryTimeouts': memoryTimeouts,
    'memoryOperationMicros': memoryOperationMicros,
    'genericOwnerDiagnostics': genericOwnerDiagnostics,
    'invalidOwnerDiagnostics': invalidOwnerDiagnostics,
  };
}

final class Cli3ContentionLatencySummary {
  const Cli3ContentionLatencySummary({
    required this.sampleCount,
    required this.p50Milliseconds,
    required this.p95Milliseconds,
    required this.maxMilliseconds,
  });

  factory Cli3ContentionLatencySummary.fromMicros(Iterable<int> values) {
    final sorted = values.toList(growable: false)..sort();
    if (sorted.isEmpty) {
      return const Cli3ContentionLatencySummary(
        sampleCount: 0,
        p50Milliseconds: 0,
        p95Milliseconds: 0,
        maxMilliseconds: 0,
      );
    }
    double percentile(double fraction) {
      final index = (sorted.length * fraction).ceil().clamp(1, sorted.length);
      return sorted[index - 1] / 1000;
    }

    return Cli3ContentionLatencySummary(
      sampleCount: sorted.length,
      p50Milliseconds: percentile(0.50),
      p95Milliseconds: percentile(0.95),
      maxMilliseconds: sorted.last / 1000,
    );
  }

  final int sampleCount;
  final double p50Milliseconds;
  final double p95Milliseconds;
  final double maxMilliseconds;

  Map<String, Object> toJson() => <String, Object>{
    'samples': sampleCount,
    'p50Ms': _rounded(p50Milliseconds),
    'p95Ms': _rounded(p95Milliseconds),
    'maxMs': _rounded(maxMilliseconds),
  };
}

final class Cli3ContentionSoakReport {
  Cli3ContentionSoakReport({
    required this.options,
    required this.workers,
    required this.elapsed,
  }) : runtimeSuccesses = workers.fold(
         0,
         (sum, worker) => sum + worker.runtimeSuccesses,
       ),
       runtimeConflicts = workers.fold(
         0,
         (sum, worker) => sum + worker.runtimeConflicts,
       ),
       runtimeTimeouts = workers.fold(
         0,
         (sum, worker) => sum + worker.runtimeTimeouts,
       ),
       memorySuccesses = workers.fold(
         0,
         (sum, worker) => sum + worker.memorySuccesses,
       ),
       memoryTimeouts = workers.fold(
         0,
         (sum, worker) => sum + worker.memoryTimeouts,
       ),
       genericOwnerDiagnostics = workers.fold(
         0,
         (sum, worker) => sum + worker.genericOwnerDiagnostics,
       ),
       invalidOwnerDiagnostics = workers.fold(
         0,
         (sum, worker) => sum + worker.invalidOwnerDiagnostics,
       ),
       runtimeLatency = Cli3ContentionLatencySummary.fromMicros(
         workers.expand((worker) => worker.runtimeWaitMicros),
       ),
       memoryLatency = Cli3ContentionLatencySummary.fromMicros(
         workers.expand((worker) => worker.memoryOperationMicros),
       );

  final Cli3ContentionSoakOptions options;
  final List<Cli3ContentionWorkerResult> workers;
  final Duration elapsed;
  final int runtimeSuccesses;
  final int runtimeConflicts;
  final int runtimeTimeouts;
  final int memorySuccesses;
  final int memoryTimeouts;
  final int genericOwnerDiagnostics;
  final int invalidOwnerDiagnostics;
  final Cli3ContentionLatencySummary runtimeLatency;
  final Cli3ContentionLatencySummary memoryLatency;

  int get totalSuccesses => runtimeSuccesses + memorySuccesses;

  double get throughputOperationsPerSecond {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    return seconds <= 0 ? 0 : totalSuccesses / seconds;
  }

  List<String> get blockingReasons {
    final reasons = <String>[];
    final expected = options.expectedOperationsPerResource;
    if (workers.length != options.workers) {
      reasons.add(
        'Expected ${options.workers} workers, received ${workers.length}.',
      );
    }
    final processIds = workers.map((worker) => worker.processId).toSet();
    if (processIds.length != workers.length ||
        processIds.any((processId) => processId <= 0)) {
      reasons.add('Workers did not report distinct valid process identifiers.');
    }
    final frontends = workers.map((worker) => worker.frontend).toSet();
    if (!frontends.contains('flutterGui') || !frontends.contains('terminal')) {
      reasons.add('Both GUI-like and terminal-like workers must participate.');
    }
    if (runtimeSuccesses != expected) {
      reasons.add(
        'Runtime operations completed $runtimeSuccesses of $expected.',
      );
    }
    if (memorySuccesses != expected) {
      reasons.add('Memory operations completed $memorySuccesses of $expected.');
    }
    if (runtimeTimeouts > 0 || memoryTimeouts > 0) {
      reasons.add(
        'Ownership timed out: runtime=$runtimeTimeouts, memory=$memoryTimeouts.',
      );
    }
    if (invalidOwnerDiagnostics > 0) {
      reasons.add(
        'Invalid parsed owner diagnostics: $invalidOwnerDiagnostics.',
      );
    }
    final measuredP95 = max(
      runtimeLatency.p95Milliseconds,
      memoryLatency.p95Milliseconds,
    );
    if (measuredP95 > options.maxP95Milliseconds) {
      reasons.add(
        'Mixed-resource p95 ${_format(measuredP95)} ms exceeds '
        '${_format(options.maxP95Milliseconds)} ms.',
      );
    }
    return reasons;
  }

  bool get passed => blockingReasons.isEmpty;

  String get decision =>
      passed ? 'direct_file_locking_sufficient' : 'investigate_local_daemon';

  List<String> get decisionReasons => passed
      ? <String>[
          'All expected mixed-resource operations completed without timeout.',
          'No parsed owner diagnostic was invalid.',
          'The measured mixed-resource p95 stayed within the configured threshold.',
        ]
      : blockingReasons;

  Map<String, Object> toJson() => <String, Object>{
    'schema': cli3ContentionSoakSchema,
    'schemaVersion': cli3ContentionSoakSchemaVersion,
    'status': passed ? 'passed' : 'failed',
    'decision': decision,
    'decisionReasons': decisionReasons,
    'configuration': options.toJson(),
    'metrics': <String, Object>{
      'elapsedMs': _rounded(elapsed.inMicroseconds / 1000),
      'throughputOperationsPerSecond': _rounded(throughputOperationsPerSecond),
      'runtime': <String, Object>{
        'successes': runtimeSuccesses,
        'conflicts': runtimeConflicts,
        'timeouts': runtimeTimeouts,
        'latency': runtimeLatency.toJson(),
      },
      'chatMemory': <String, Object>{
        'successes': memorySuccesses,
        'timeouts': memoryTimeouts,
        'latency': memoryLatency.toJson(),
      },
      'ownerDiagnostics': <String, Object>{
        'generic': genericOwnerDiagnostics,
        'invalid': invalidOwnerDiagnostics,
      },
    },
    'workers': workers
        .map(
          (worker) => <String, Object>{
            'frontend': worker.frontend,
            'processId': worker.processId,
            'runtimeSuccesses': worker.runtimeSuccesses,
            'runtimeConflicts': worker.runtimeConflicts,
            'runtimeTimeouts': worker.runtimeTimeouts,
            'memorySuccesses': worker.memorySuccesses,
            'memoryTimeouts': worker.memoryTimeouts,
          },
        )
        .toList(growable: false),
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# CLI3 Contention Soak')
      ..writeln()
      ..writeln('- Status: `${passed ? 'passed' : 'failed'}`')
      ..writeln('- Decision: `$decision`')
      ..writeln('- Workers: ${options.workers}')
      ..writeln('- Iterations per worker: ${options.iterations}')
      ..writeln(
        '- Throughput: ${_format(throughputOperationsPerSecond)} operations/s',
      )
      ..writeln()
      ..writeln('## Metrics')
      ..writeln()
      ..writeln(
        '| Resource | Successes | Conflicts | Timeouts | p50 ms | p95 ms | max ms |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |')
      ..writeln(
        '| Conversation + workspace | $runtimeSuccesses | $runtimeConflicts | '
        '$runtimeTimeouts | ${_format(runtimeLatency.p50Milliseconds)} | '
        '${_format(runtimeLatency.p95Milliseconds)} | '
        '${_format(runtimeLatency.maxMilliseconds)} |',
      )
      ..writeln(
        '| Chat memory | $memorySuccesses | - | $memoryTimeouts | '
        '${_format(memoryLatency.p50Milliseconds)} | '
        '${_format(memoryLatency.p95Milliseconds)} | '
        '${_format(memoryLatency.maxMilliseconds)} |',
      )
      ..writeln()
      ..writeln('## Decision Reasons')
      ..writeln();
    for (final reason in decisionReasons) {
      buffer.writeln('- $reason');
    }
    return buffer.toString();
  }
}

List<int> _intList(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected an integer list.');
  }
  return value.cast<int>();
}

num _rounded(double value) => double.parse(value.toStringAsFixed(3));
String _format(double value) => value.toStringAsFixed(3);
