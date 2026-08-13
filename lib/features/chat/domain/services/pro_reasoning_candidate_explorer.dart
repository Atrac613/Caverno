import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/datasources/llama_cpp_slot_discovery.dart';
import '../../data/datasources/llama_cpp_slot_transport.dart';
import '../../data/datasources/parallel_slot_executor.dart';
import 'pro_reasoning_models.dart';
import 'pro_reasoning_prompt_builder.dart';

final class ProReasoningEndpointTarget {
  const ProReasoningEndpointTarget({
    required this.endpointId,
    required this.label,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String endpointId;
  final String label;
  final String baseUrl;
  final String apiKey;
  final String model;
}

final class ProReasoningEndpointProbe {
  const ProReasoningEndpointProbe({
    required this.target,
    required this.inventory,
    this.thinkingOverrideSupported = false,
  });

  final ProReasoningEndpointTarget target;
  final SlotInventory inventory;
  final bool thinkingOverrideSupported;
}

typedef ProReasoningEndpointProber =
    Future<ProReasoningEndpointProbe?> Function(
      ProReasoningEndpointTarget target,
    );
typedef ProReasoningCandidateCallObserver =
    FutureOr<void> Function({
      required ProReasoningEndpointTarget target,
      required int candidateIndex,
      required int attemptCount,
      required int maxTokens,
      required SlotChatResult? result,
      required Object? error,
      required DateTime startedAt,
      required DateTime finishedAt,
    });

/// Fans candidate answers across responding hosts and serializes each host's
/// queue. This intentionally never treats multiple slots on one host as
/// independent GPUs; separate hosts are the only parallelism boundary.
final class ProReasoningCandidateExplorer {
  ProReasoningCandidateExplorer({
    required List<ProReasoningEndpointTarget> endpoints,
    this.promptBuilder = const ProReasoningPromptBuilder(),
    this.executor = const ParallelSlotExecutor(),
    ProReasoningEndpointProber? probeEndpoint,
    this.onCandidateCall,
    DateTime Function()? clock,
  }) : endpoints = List<ProReasoningEndpointTarget>.unmodifiable(endpoints),
       _probeEndpoint = probeEndpoint ?? _defaultProbeEndpoint,
       _clock = clock ?? DateTime.now;

  final List<ProReasoningEndpointTarget> endpoints;
  final ProReasoningPromptBuilder promptBuilder;
  final ParallelSlotExecutor executor;
  final ProReasoningEndpointProber _probeEndpoint;
  final ProReasoningCandidateCallObserver? onCandidateCall;
  final DateTime Function() _clock;
  final Set<LlamaCppSlotTransport> _activeTransports = {};

  static const _candidateMaxTokens = 3000;
  static const _reasoningBudgetRecoveryMaxTokens = 6000;

  Future<ProReasoningExploreResult> explore(
    ProReasoningExploreRequest request,
  ) async {
    if (request.candidateCount <= 0 ||
        request.isCancelled() ||
        !_clock().isBefore(request.deadline)) {
      return ProReasoningExploreResult(
        requestedCandidateCount: request.candidateCount,
      );
    }

    final probeFuture = Future.wait(endpoints.map(_probeEndpoint));
    final cancelSignal = request.cancelSignal;
    final probeResults = cancelSignal == null
        ? await probeFuture
        : await Future.any<List<ProReasoningEndpointProbe?>>([
            probeFuture,
            cancelSignal.then((_) => const <ProReasoningEndpointProbe?>[]),
          ]);
    final probes = probeResults.whereType<ProReasoningEndpointProbe>().toList(
      growable: false,
    );
    final labels = probes.map((probe) => probe.target.label).toList();
    request.onProgress(
      completed: 0,
      requested: request.candidateCount,
      endpointLabels: labels,
    );
    if (probes.isEmpty ||
        request.isCancelled() ||
        !_clock().isBefore(request.deadline)) {
      return ProReasoningExploreResult(
        endpointLabels: labels,
        requestedCandidateCount: request.candidateCount,
      );
    }

    var effectiveCandidateCount = request.candidateCount;
    if (cancelSignal != null) {
      unawaited(cancelSignal.then((_) => _closeActiveTransports()));
    }
    final firstCandidate = await _runWarmCandidate(
      probe: probes.first,
      request: request,
      assignment: _assignmentFor(request.frame, 0),
      sharedPrefix: promptBuilder.buildCandidateSharedPrefix(
        question: request.question,
        frame: request.frame,
        evidence: request.evidence,
      ),
    );
    final warmResult = firstCandidate.$1;
    final warmDuration = firstCandidate.$2;
    if (warmDuration > Duration.zero) {
      final remaining = request.deadline.difference(_clock());
      final additionalCapacity =
          (remaining.inMilliseconds / warmDuration.inMilliseconds).floor() *
          probes.length;
      effectiveCandidateCount = (1 + additionalCapacity).clamp(
        1,
        request.candidateCount,
      );
    }

    final sharedPrefix = promptBuilder.buildCandidateSharedPrefix(
      question: request.question,
      frame: request.frame,
      evidence: request.evidence,
    );
    final assignments = <List<_CandidateAssignment>>[
      for (var i = 0; i < probes.length; i++) <_CandidateAssignment>[],
    ];
    for (var index = 1; index < effectiveCandidateCount; index++) {
      assignments[index % assignments.length].add(
        _CandidateAssignment(
          index: index,
          angle: _angleFor(request.frame, index),
          temperature: _temperatureFor(index),
          seed: 104729 + (index * 7919),
        ),
      );
    }

    var completed = 0;
    var attempted = 1;
    final candidates = <ProReasoningCandidate>[?warmResult];
    completed = 1;
    request.onProgress(
      completed: completed,
      requested: effectiveCandidateCount,
      endpointLabels: labels,
    );
    Future<void> runHost(
      ProReasoningEndpointProbe probe,
      List<_CandidateAssignment> hostAssignments,
    ) async {
      final transport = LlamaCppSlotTransport(
        baseUrl: probe.target.baseUrl,
        apiKey: probe.target.apiKey,
        timeout: _remainingTimeout(request.deadline),
      );
      _activeTransports.add(transport);
      try {
        final runners = hostAssignments
            .map((assignment) {
              return (int? slotId) async {
                if (request.isCancelled() ||
                    !_clock().isBefore(request.deadline)) {
                  throw const ProReasoningCandidateSkippedException();
                }
                attempted++;
                final startedAt = _clock();
                SlotChatResult? result;
                Object? error;
                var attemptCount = 0;
                var maxTokens = _candidateMaxTokens;
                try {
                  result = await _runCandidateWithRecovery(
                    transport: transport,
                    probe: probe,
                    assignment: assignment,
                    sharedPrefix: sharedPrefix,
                    slotId: slotId,
                    deadline: request.deadline,
                    isCancelled: request.isCancelled,
                    onAttempt: (attempt, budget) {
                      attemptCount = attempt;
                      maxTokens = budget;
                    },
                  );
                  return result;
                } catch (caught) {
                  error = caught;
                  rethrow;
                } finally {
                  await onCandidateCall?.call(
                    target: probe.target,
                    candidateIndex: assignment.index,
                    attemptCount: attemptCount,
                    maxTokens: maxTokens,
                    result: result,
                    error: error,
                    startedAt: startedAt,
                    finishedAt: _clock(),
                  );
                }
              };
            })
            .toList(growable: false);
        for (var index = 0; index < runners.length; index++) {
          final outcome = await executor.run(
            candidates: <SlotCandidateRunner>[runners[index]],
            inventory: probe.inventory,
            maxConcurrency: 1,
          );
          final candidateOutcome = outcome.single;
          final result = candidateOutcome.result;
          if (result != null && result.hasUsableContent) {
            candidates.add(_toCandidate(probe, hostAssignments[index], result));
          }
          if (candidateOutcome.error is ProReasoningCandidateSkippedException) {
            break;
          }
          completed++;
          request.onProgress(
            completed: completed,
            requested: effectiveCandidateCount,
            endpointLabels: labels,
          );
        }
      } finally {
        _activeTransports.remove(transport);
        transport.close();
      }
    }

    final hosts = Future.wait([
      for (var index = 0; index < probes.length; index++)
        runHost(probes[index], assignments[index]),
    ]);
    await hosts;
    // `candidates` is mutated only after an await boundary completes for a
    // host. Sort restores deterministic candidate order across host futures.
    candidates.sort((left, right) => left.index.compareTo(right.index));
    return ProReasoningExploreResult(
      candidates: List<ProReasoningCandidate>.unmodifiable(candidates),
      endpointLabels: labels,
      requestedCandidateCount: effectiveCandidateCount,
      attemptedCandidateCount: attempted,
    );
  }

  void _closeActiveTransports() {
    for (final transport in _activeTransports.toList(growable: false)) {
      transport.close();
    }
  }

  Future<(ProReasoningCandidate?, Duration)> _runWarmCandidate({
    required ProReasoningEndpointProbe probe,
    required ProReasoningExploreRequest request,
    required _CandidateAssignment assignment,
    required String sharedPrefix,
  }) async {
    final transport = LlamaCppSlotTransport(
      baseUrl: probe.target.baseUrl,
      apiKey: probe.target.apiKey,
      timeout: _remainingTimeout(request.deadline),
    );
    _activeTransports.add(transport);
    final startedAt = _clock();
    try {
      final idleSlots = probe.inventory.idleSlotIds;
      final allSlots = probe.inventory.slotIds;
      final slotId = idleSlots.isNotEmpty
          ? idleSlots.first
          : allSlots.isNotEmpty
          ? allSlots.first
          : null;
      SlotChatResult? result;
      Object? error;
      var attemptCount = 0;
      var maxTokens = _candidateMaxTokens;
      try {
        result = await _runCandidateWithRecovery(
          transport: transport,
          probe: probe,
          assignment: assignment,
          sharedPrefix: sharedPrefix,
          slotId: slotId,
          deadline: request.deadline,
          isCancelled: request.isCancelled,
          onAttempt: (attempt, budget) {
            attemptCount = attempt;
            maxTokens = budget;
          },
        );
        if (!result.hasUsableContent) {
          return (null, _clock().difference(startedAt));
        }
        return (
          _toCandidate(probe, assignment, result),
          _clock().difference(startedAt),
        );
      } catch (caught) {
        error = caught;
        return (null, _clock().difference(startedAt));
      } finally {
        await onCandidateCall?.call(
          target: probe.target,
          candidateIndex: assignment.index,
          attemptCount: attemptCount,
          maxTokens: maxTokens,
          result: result,
          error: error,
          startedAt: startedAt,
          finishedAt: _clock(),
        );
      }
    } finally {
      _activeTransports.remove(transport);
      transport.close();
    }
  }

  _CandidateAssignment _assignmentFor(ProReasoningFrame frame, int index) =>
      _CandidateAssignment(
        index: index,
        angle: _angleFor(frame, index),
        temperature: _temperatureFor(index),
        seed: 104729 + (index * 7919),
      );

  Future<SlotChatResult> _runCandidate({
    required LlamaCppSlotTransport transport,
    required ProReasoningEndpointProbe probe,
    required _CandidateAssignment assignment,
    required String sharedPrefix,
    required int? slotId,
    required int maxTokens,
  }) => transport.createChatCompletion(
    model: probe.target.model,
    messages: <Map<String, dynamic>>[
      <String, dynamic>{
        'role': 'user',
        'content': promptBuilder.buildCandidatePrompt(
          sharedPrefix: sharedPrefix,
          angle: assignment.angle,
        ),
      },
    ],
    temperature: assignment.temperature,
    maxTokens: maxTokens,
    idSlot: slotId,
    cachePrompt: true,
    chatTemplateKwargs: probe.thinkingOverrideSupported
        ? const <String, dynamic>{'enable_thinking': true}
        : null,
    reasoningEffort: probe.thinkingOverrideSupported ? 'high' : null,
    seed: assignment.seed,
  );

  Future<SlotChatResult> _runCandidateWithRecovery({
    required LlamaCppSlotTransport transport,
    required ProReasoningEndpointProbe probe,
    required _CandidateAssignment assignment,
    required String sharedPrefix,
    required int? slotId,
    required DateTime deadline,
    required bool Function() isCancelled,
    required void Function(int attempt, int maxTokens) onAttempt,
  }) async {
    onAttempt(1, _candidateMaxTokens);
    final initial = await _runCandidate(
      transport: transport,
      probe: probe,
      assignment: assignment,
      sharedPrefix: sharedPrefix,
      slotId: slotId,
      maxTokens: _candidateMaxTokens,
    );
    if (!initial.exhaustedBudgetInReasoning ||
        isCancelled() ||
        !_clock().isBefore(deadline)) {
      return initial;
    }

    onAttempt(2, _reasoningBudgetRecoveryMaxTokens);
    return _runCandidate(
      transport: transport,
      probe: probe,
      assignment: assignment,
      sharedPrefix: sharedPrefix,
      slotId: slotId,
      maxTokens: _reasoningBudgetRecoveryMaxTokens,
    );
  }

  ProReasoningCandidate _toCandidate(
    ProReasoningEndpointProbe probe,
    _CandidateAssignment assignment,
    SlotChatResult result,
  ) => ProReasoningCandidate(
    index: assignment.index,
    answer: result.content.trim(),
    reasoning: result.reasoning.trim(),
    angle: assignment.angle,
    model: probe.target.model,
    endpointId: probe.target.endpointId,
    endpointLabel: probe.target.label,
    thinkingRequested: probe.thinkingOverrideSupported,
    thinkingObserved: result.reasoning.trim().isNotEmpty,
    duration: _durationFrom(result),
    slotId: result.idSlot,
    promptTokens: result.promptTokens,
    completionTokens: result.completionTokens,
  );

  static Future<ProReasoningEndpointProbe?> _defaultProbeEndpoint(
    ProReasoningEndpointTarget target,
  ) async {
    final discovery = LlamaCppSlotDiscovery(
      baseUrl: target.baseUrl,
      apiKey: target.apiKey,
      model: target.model,
    );
    try {
      final inventory = await discovery.discover();
      if (!inventory.supported &&
          await _configuredModelIsColdInLmStudio(target) == true) {
        return null;
      }
      final transport = LlamaCppSlotTransport(
        baseUrl: target.baseUrl,
        apiKey: target.apiKey,
        timeout: const Duration(seconds: 15),
      );
      try {
        final thinkingProbe = await _probeThinkingOverride(target, transport);
        if (!thinkingProbe.reachable) {
          await transport.createChatCompletion(
            model: target.model,
            messages: const <Map<String, dynamic>>[
              <String, dynamic>{'role': 'user', 'content': 'Reply OK.'},
            ],
            maxTokens: 1,
            temperature: 0,
            cachePrompt: false,
          );
        }
        return ProReasoningEndpointProbe(
          target: target,
          inventory: inventory,
          thinkingOverrideSupported: thinkingProbe.supported,
        );
      } finally {
        transport.close();
      }
    } catch (_) {
      return null;
    } finally {
      discovery.close();
    }
  }

  static Future<({bool reachable, bool supported})> _probeThinkingOverride(
    ProReasoningEndpointTarget target,
    LlamaCppSlotTransport transport,
  ) async {
    try {
      final result = await transport.createChatCompletion(
        model: target.model,
        messages: const <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content': 'Think briefly, then answer OK.',
          },
        ],
        maxTokens: 32,
        temperature: 0,
        cachePrompt: false,
        chatTemplateKwargs: const <String, dynamic>{'enable_thinking': true},
      );
      return (reachable: true, supported: result.reasoning.trim().isNotEmpty);
    } catch (_) {
      return (reachable: false, supported: false);
    }
  }

  static Future<bool?> _configuredModelIsColdInLmStudio(
    ProReasoningEndpointTarget target,
  ) async {
    final baseUri = Uri.tryParse(target.baseUrl);
    if (baseUri == null) return null;
    final segments = baseUri.pathSegments.toList();
    if (segments.isNotEmpty && segments.last == 'v1') segments.removeLast();
    final uri = baseUri.replace(
      pathSegments: [...segments, 'api', 'v0', 'models'],
    );
    final client = http.Client();
    try {
      final response = await client
          .get(uri, headers: {'Authorization': 'Bearer ${target.apiKey}'})
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      if (data is! List) return null;
      for (final entry in data.whereType<Map>()) {
        if (entry['id']?.toString() != target.model) continue;
        return entry['state']?.toString().toLowerCase() != 'loaded';
      }
      return true;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Duration _remainingTimeout(DateTime deadline) {
    final remaining = deadline.difference(_clock());
    if (remaining <= Duration.zero) return const Duration(milliseconds: 1);
    return remaining;
  }

  String _angleFor(ProReasoningFrame frame, int index) {
    if (frame.subQuestions.isEmpty) {
      return 'Develop the strongest direct answer and challenge its assumptions.';
    }
    final focus = frame.subQuestions[index % frame.subQuestions.length];
    return 'Focus on this sub-question, then integrate the whole answer: $focus';
  }

  double _temperatureFor(int index) => switch (index % 4) {
    0 => 0.35,
    1 => 0.55,
    2 => 0.7,
    _ => 0.45,
  };

  Duration _durationFrom(SlotChatResult result) {
    final milliseconds = result.timings?.predictedMs;
    if (milliseconds == null || milliseconds < 0) return Duration.zero;
    return Duration(microseconds: (milliseconds * 1000).round());
  }
}

final class _CandidateAssignment {
  const _CandidateAssignment({
    required this.index,
    required this.angle,
    required this.temperature,
    required this.seed,
  });

  final int index;
  final String angle;
  final double temperature;
  final int seed;
}

final class ProReasoningCandidateSkippedException implements Exception {
  const ProReasoningCandidateSkippedException();
}
