import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_discovery.dart';
import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_transport.dart';
import 'package:caverno/features/chat/data/datasources/parallel_slot_executor.dart';

/// LL20 parallel slot execution proof.
///
/// Exercises the real substrate (LlamaCppSlotDiscovery + LlamaCppSlotTransport +
/// ParallelSlotExecutor) against a live OpenAI-compatible endpoint: discovers
/// slots, runs N distinct candidates concurrently (each pinned to its own slot)
/// and then sequentially, and reports the served slots, per-candidate timings,
/// and the concurrent-vs-sequential wall-clock speedup. On a single-slot or
/// non-slot endpoint it records the graceful sequential fallback.
Future<void> main(List<String> args) async {
  final options = Ll20MeasurementOptions.parse(
    args,
    environment: Platform.environment,
  );
  if (options == null) {
    stderr.writeln(Ll20MeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final discovery = LlamaCppSlotDiscovery(
    baseUrl: options.baseUrl,
    apiKey: options.apiKey,
  );
  final transport = LlamaCppSlotTransport(
    baseUrl: options.baseUrl,
    apiKey: options.apiKey,
    timeout: options.timeout,
  );
  try {
    final summary = await runLl20ParallelSlotMeasurement(
      options: options,
      discovery: discovery,
      transport: transport,
      executor: const ParallelSlotExecutor(),
    );

    if (options.outputPath != null) {
      final output = File(options.outputPath!);
      await output.parent.create(recursive: true);
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(summary.toJson())}\n',
      );
    }

    switch (options.format) {
      case Ll20MeasurementOutputFormat.json:
        stdout.writeln(
          const JsonEncoder.withIndent('  ').convert(summary.toJson()),
        );
      case Ll20MeasurementOutputFormat.markdown:
        stdout.write(summary.toMarkdown());
    }
  } finally {
    discovery.close();
    transport.close();
  }
}

enum Ll20MeasurementOutputFormat { markdown, json }

class Ll20MeasurementOptions {
  const Ll20MeasurementOptions({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.candidateCount,
    required this.maxTokens,
    required this.timeout,
    required this.outputPath,
    required this.format,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final int candidateCount;
  final int maxTokens;
  final Duration timeout;
  final String? outputPath;
  final Ll20MeasurementOutputFormat format;

  static const usage =
      'Usage: dart run tool/ll20_parallel_slot_measurement.dart '
      '[--base-url URL] [--model MODEL] [--api-key KEY] '
      '[--candidate-count N] [--max-tokens N] [--timeout-seconds N] '
      '[--output PATH] [--format markdown|json]\n\n'
      'Defaults: CAVERNO_LLM_BASE_URL or http://localhost:1234/v1, '
      'CAVERNO_LLM_MODEL or local-model, CAVERNO_LLM_API_KEY or no-key.';

  static Ll20MeasurementOptions? parse(
    List<String> args, {
    Map<String, String> environment = const {},
  }) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') return null;
      if (!arg.startsWith('--')) return null;
      final equalsIndex = arg.indexOf('=');
      if (equalsIndex > 0) {
        values[arg.substring(2, equalsIndex)] = arg.substring(equalsIndex + 1);
        continue;
      }
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        return null;
      }
      values[arg.substring(2)] = args[index + 1];
      index += 1;
    }

    final format = switch (values['format']?.trim().toLowerCase()) {
      null || '' || 'markdown' => Ll20MeasurementOutputFormat.markdown,
      'json' => Ll20MeasurementOutputFormat.json,
      _ => null,
    };
    if (format == null) return null;

    final candidateCount = _parsePositiveInt(
      values['candidate-count'],
      fallback: 3,
    );
    final maxTokens = _parsePositiveInt(values['max-tokens'], fallback: 24);
    final timeoutSeconds = _parsePositiveInt(
      values['timeout-seconds'],
      fallback: 180,
    );
    if (candidateCount == null || maxTokens == null || timeoutSeconds == null) {
      return null;
    }

    return Ll20MeasurementOptions(
      baseUrl:
          values['base-url'] ??
          environment['CAVERNO_LLM_BASE_URL'] ??
          'http://localhost:1234/v1',
      model:
          values['model'] ?? environment['CAVERNO_LLM_MODEL'] ?? 'local-model',
      apiKey:
          values['api-key'] ?? environment['CAVERNO_LLM_API_KEY'] ?? 'no-key',
      candidateCount: candidateCount,
      maxTokens: maxTokens,
      timeout: Duration(seconds: timeoutSeconds),
      outputPath: values['output'],
      format: format,
    );
  }

  static int? _parsePositiveInt(String? value, {required int fallback}) {
    if (value == null || value.trim().isEmpty) return fallback;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}

class Ll20CandidateRecord {
  const Ll20CandidateRecord({
    required this.index,
    required this.ok,
    this.assignedSlot,
    this.servedSlot,
    this.promptMs,
    this.error,
  });

  final int index;
  final bool ok;
  final int? assignedSlot;
  final int? servedSlot;
  final double? promptMs;
  final String? error;

  factory Ll20CandidateRecord.fromOutcome(
    int index,
    SlotCandidateOutcome outcome,
  ) {
    return Ll20CandidateRecord(
      index: index,
      ok: outcome.isSuccess,
      assignedSlot: outcome.assignedSlot,
      servedSlot: outcome.result?.idSlot,
      promptMs: outcome.result?.timings?.promptMs,
      error: outcome.error?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'ok': ok,
      'assignedSlot': ?assignedSlot,
      'servedSlot': ?servedSlot,
      'promptMs': ?promptMs,
      'error': ?error,
    };
  }
}

class Ll20MeasurementSummary {
  const Ll20MeasurementSummary({
    required this.generatedAt,
    required this.baseUrl,
    required this.model,
    required this.candidateCount,
    required this.inventorySupported,
    required this.slotIds,
    required this.concurrentWallClockMs,
    required this.sequentialWallClockMs,
    required this.records,
  });

  final DateTime generatedAt;
  final String baseUrl;
  final String model;
  final int candidateCount;
  final bool inventorySupported;
  final List<int> slotIds;
  final int concurrentWallClockMs;
  final int sequentialWallClockMs;
  final List<Ll20CandidateRecord> records;

  int get slotCount => slotIds.length;

  Set<int> get distinctServedSlots => {
    for (final record in records)
      if (record.ok && record.servedSlot != null) record.servedSlot!,
  };

  int get successCount => records.where((r) => r.ok).length;

  double? get speedup {
    if (concurrentWallClockMs <= 0) return null;
    return sequentialWallClockMs / concurrentWallClockMs;
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_ll20_parallel_slot_measurement',
      'schemaVersion': 1,
      'generatedAt': generatedAt.toIso8601String(),
      'baseUrl': baseUrl,
      'model': model,
      'candidateCount': candidateCount,
      'inventorySupported': inventorySupported,
      'slotCount': slotCount,
      'slotIds': slotIds,
      'concurrentWallClockMs': concurrentWallClockMs,
      'sequentialWallClockMs': sequentialWallClockMs,
      'successCount': successCount,
      'distinctServedSlots': distinctServedSlots.toList()..sort(),
      'speedup': ?speedup,
      'candidates': [for (final record in records) record.toJson()],
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL20 Parallel Slot Measurement')
      ..writeln()
      ..writeln('- Generated: `${generatedAt.toIso8601String()}`')
      ..writeln('- Base URL: `$baseUrl`')
      ..writeln('- Model: `$model`')
      ..writeln('- Candidates: `$candidateCount`')
      ..writeln('- Slots supported: `$inventorySupported`')
      ..writeln('- Slot count: `$slotCount` (`${slotIds.join(', ')}`)')
      ..writeln()
      ..writeln(
        '| Candidate | ok | assigned slot | served id_slot | prompt_ms |',
      )
      ..writeln('| ---: | :--: | ---: | ---: | ---: |');
    for (final record in records) {
      buffer.writeln(
        '| ${record.index} | ${record.ok ? 'yes' : 'no'} | '
        '${record.assignedSlot ?? '-'} | ${record.servedSlot ?? '-'} | '
        '${_formatDouble(record.promptMs)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Timing')
      ..writeln()
      ..writeln('- Concurrent wall-clock: `${concurrentWallClockMs}ms`')
      ..writeln('- Sequential wall-clock: `${sequentialWallClockMs}ms`')
      ..writeln('- Speedup: `${_formatSpeedup(speedup)}`')
      ..writeln('- Distinct served slots: `${distinctServedSlots.length}`')
      ..writeln('- Successful candidates: `$successCount/$candidateCount`');
    return buffer.toString();
  }
}

Future<Ll20MeasurementSummary> runLl20ParallelSlotMeasurement({
  required Ll20MeasurementOptions options,
  required LlamaCppSlotDiscovery discovery,
  required LlamaCppSlotTransport transport,
  required ParallelSlotExecutor executor,
  DateTime? generatedAt,
}) async {
  final inventory = await discovery.discover();

  List<SlotCandidateRunner> buildRunners() {
    return [
      for (var index = 0; index < options.candidateCount; index += 1)
        (idSlot) => transport.createChatCompletion(
          model: options.model,
          messages: [
            {
              'role': 'system',
              'content':
                  'You are the Caverno LL20 slot measurement assistant. '
                  'Answer in one short sentence.',
            },
            {
              'role': 'user',
              'content':
                  'Candidate $index: name a distinct primary color (#$index).',
            },
          ],
          temperature: 0.7,
          maxTokens: options.maxTokens,
          idSlot: idSlot,
        ),
    ];
  }

  final concurrentWatch = Stopwatch()..start();
  final concurrentOutcomes = await executor.run(
    candidates: buildRunners(),
    inventory: inventory,
  );
  concurrentWatch.stop();

  final sequentialWatch = Stopwatch()..start();
  await executor.run(
    candidates: buildRunners(),
    inventory: inventory,
    maxConcurrency: 1,
  );
  sequentialWatch.stop();

  return Ll20MeasurementSummary(
    generatedAt: generatedAt ?? DateTime.now(),
    baseUrl: options.baseUrl,
    model: options.model,
    candidateCount: options.candidateCount,
    inventorySupported: inventory.supported,
    slotIds: inventory.slotIds,
    concurrentWallClockMs: concurrentWatch.elapsedMilliseconds,
    sequentialWallClockMs: sequentialWatch.elapsedMilliseconds,
    records: [
      for (var index = 0; index < concurrentOutcomes.length; index += 1)
        Ll20CandidateRecord.fromOutcome(index, concurrentOutcomes[index]),
    ],
  );
}

String _formatDouble(double? value) {
  if (value == null) return '-';
  return value.toStringAsFixed(1);
}

String _formatSpeedup(double? value) {
  if (value == null) return '-';
  return '${value.toStringAsFixed(2)}x';
}
