import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/llama_cpp_slot_discovery.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_candidate_endpoint_resolver.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_candidate_explorer.dart';
import 'package:caverno/features/chat/domain/services/pro_reasoning_models.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  test(
    'default preflight probes thinking before running the warm candidate',
    () async {
      final host = await _CandidateServer.start('host-a');
      addTearDown(host.close);
      final explorer = ProReasoningCandidateExplorer(
        endpoints: [_target('a', 'Host A', host.baseUrl)],
      );

      final result = await explorer.explore(
        ProReasoningExploreRequest(
          question: 'Choose a deployment strategy.',
          frame: const ProReasoningFrame(
            subQuestions: ['Correctness'],
            investigationSteps: [],
            successCriteria: ['Ground claims'],
            requiresInvestigation: false,
          ),
          evidence: 'Measured evidence.',
          candidateCount: 1,
          deadline: DateTime.now().add(const Duration(seconds: 5)),
          isCancelled: () => false,
          onProgress:
              ({
                required completed,
                required requested,
                required endpointLabels,
              }) {},
        ),
      );

      expect(host.getPaths, contains('/slots'));
      expect(host.requests, hasLength(2));
      expect(result.candidates.single.thinkingRequested, isTrue);
      expect(result.candidates.single.thinkingObserved, isTrue);
    },
  );

  test('default preflight does not cold-load an LM Studio model', () async {
    final host = await _CandidateServer.start(
      'host-a',
      slotsSupported: false,
      modelState: 'not-loaded',
    );
    addTearDown(host.close);
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [_target('a', 'Host A', host.baseUrl)],
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 1,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(host.getPaths, containsAll(['/slots', '/api/v0/models']));
    expect(host.requests, isEmpty);
    expect(result.candidates, isEmpty);
  });

  test(
    'round-robins live hosts, keeps each host sequential, and drops a dead host',
    () async {
      final hostA = await _CandidateServer.start('host-a');
      final hostB = await _CandidateServer.start('host-b');
      addTearDown(hostA.close);
      addTearDown(hostB.close);
      final endpoints = [
        _target('a', 'Host A', hostA.baseUrl),
        _target('dead', 'Dead host', 'http://127.0.0.1:9/v1'),
        _target('b', 'Host B', hostB.baseUrl),
      ];
      final probed = <String>[];
      final callsByHost = <String, List<int>>{};
      final progress =
          <({int completed, int requested, List<String> labels})>[];
      final explorer = ProReasoningCandidateExplorer(
        endpoints: endpoints,
        probeEndpoint: (target) async {
          probed.add(target.endpointId);
          if (target.endpointId == 'dead') return null;
          return ProReasoningEndpointProbe(
            target: target,
            inventory: const SlotInventory(
              supported: true,
              slots: [
                ServerSlot(id: 0, isProcessing: false),
                ServerSlot(id: 1, isProcessing: false),
              ],
            ),
            thinkingOverrideSupported: true,
          );
        },
        onCandidateCall:
            ({
              required target,
              required candidateIndex,
              required attemptCount,
              required maxTokens,
              required result,
              required error,
              required startedAt,
              required finishedAt,
            }) {
              callsByHost
                  .putIfAbsent(target.endpointId, () => [])
                  .add(candidateIndex);
            },
      );

      final result = await explorer.explore(
        ProReasoningExploreRequest(
          question: 'Choose a deployment strategy.',
          frame: const ProReasoningFrame(
            subQuestions: ['Correctness', 'Operational risk'],
            investigationSteps: [],
            successCriteria: ['Ground claims'],
            requiresInvestigation: false,
          ),
          evidence: 'Measured evidence.',
          candidateCount: 4,
          deadline: DateTime.now().add(const Duration(seconds: 5)),
          isCancelled: () => false,
          onProgress:
              ({
                required completed,
                required requested,
                required endpointLabels,
              }) {
                progress.add((
                  completed: completed,
                  requested: requested,
                  labels: List<String>.of(endpointLabels),
                ));
              },
        ),
      );

      expect(probed, ['a', 'dead', 'b']);
      expect(result.endpointLabels, ['Host A', 'Host B']);
      expect(result.requestedCandidateCount, 4);
      expect(result.attemptedCandidateCount, 4);
      expect(
        result.candidates.map(
          (candidate) => '${candidate.endpointId}:${candidate.index}',
        ),
        ['a:0', 'b:1', 'a:2', 'b:3'],
      );
      expect(callsByHost, {
        'a': [0, 2],
        'b': [1, 3],
      });
      expect(hostA.requests, hasLength(2));
      expect(hostB.requests, hasLength(2));
      expect(hostA.maxInFlight, 1);
      expect(hostB.maxInFlight, 1);
      expect(
        [
          ...hostA.requests,
          ...hostB.requests,
        ].map((body) => body['id_slot']).toSet(),
        {0},
      );
      expect(
        result.candidates.every(
          (candidate) =>
              candidate.thinkingRequested && candidate.thinkingObserved,
        ),
        isTrue,
      );
      expect(progress.first.completed, 0);
      expect(progress.first.labels, ['Host A', 'Host B']);
      expect(progress.last.completed, 4);
    },
  );

  test(
    'selected-only resolution sends candidates only to the selected endpoint',
    () async {
      final primary = await _CandidateServer.start('primary-host');
      final selected = await _CandidateServer.start('selected-host');
      addTearDown(primary.close);
      addTearDown(selected.close);
      final settings = AppSettings.defaults().copyWith(
        baseUrl: primary.baseUrl,
        apiKey: 'primary-key',
        model: 'primary-model',
        llmEndpoints: [
          LlmEndpoint(
            id: 'primary',
            label: 'Primary host',
            baseUrl: primary.baseUrl,
            apiKey: 'primary-key',
            model: 'primary-model',
          ),
          LlmEndpoint(
            id: 'selected',
            label: 'Selected host',
            baseUrl: selected.baseUrl,
            apiKey: 'selected-key',
            model: 'selected-endpoint-model',
          ),
        ],
        activeLlmEndpointId: 'primary',
        proReasoningEndpointId: 'selected',
        proReasoningModel: 'selected-role-model',
        proReasoningCandidateRouting: ProReasoningCandidateRouting.selectedOnly,
      );
      final endpoints = const ProReasoningCandidateEndpointResolver().resolve(
        settings: settings,
        selectedEndpointOnly:
            settings.proReasoningCandidateRouting ==
            ProReasoningCandidateRouting.selectedOnly,
      );
      final explorer = ProReasoningCandidateExplorer(endpoints: endpoints);

      final result = await explorer.explore(
        ProReasoningExploreRequest(
          question: 'Choose a deployment strategy.',
          frame: const ProReasoningFrame(
            subQuestions: ['Correctness'],
            investigationSteps: [],
            successCriteria: ['Ground claims'],
            requiresInvestigation: false,
          ),
          evidence: 'Measured evidence.',
          candidateCount: 2,
          deadline: DateTime.now().add(const Duration(seconds: 5)),
          isCancelled: () => false,
          onProgress:
              ({
                required completed,
                required requested,
                required endpointLabels,
              }) {},
        ),
      );

      expect(endpoints.map((endpoint) => endpoint.endpointId), ['selected']);
      expect(primary.getPaths, isEmpty);
      expect(primary.requests, isEmpty);
      expect(selected.requests, hasLength(3));
      expect(selected.requests.map((request) => request['model']).toSet(), {
        'selected-role-model',
      });
      expect(result.endpointLabels, ['Selected host']);
      expect(result.candidates, hasLength(2));
      expect(
        result.candidates.map((candidate) => candidate.endpointId).toSet(),
        {'selected'},
      );
      expect(result.candidates.map((candidate) => candidate.model).toSet(), {
        'selected-role-model',
      });
    },
  );

  test(
    'cancel closes an in-flight host request and preserves warm result',
    () async {
      final host = await _CandidateServer.start('host-a', holdSecond: true);
      addTearDown(host.close);
      var cancelled = false;
      final cancelSignal = Completer<void>();
      final explorer = ProReasoningCandidateExplorer(
        endpoints: [_target('a', 'Host A', host.baseUrl)],
        probeEndpoint: (target) async => ProReasoningEndpointProbe(
          target: target,
          inventory: const SlotInventory(
            supported: true,
            slots: [ServerSlot(id: 0, isProcessing: false)],
          ),
          thinkingOverrideSupported: true,
        ),
      );

      final resultFuture = explorer.explore(
        ProReasoningExploreRequest(
          question: 'Choose a deployment strategy.',
          frame: const ProReasoningFrame(
            subQuestions: ['Correctness'],
            investigationSteps: [],
            successCriteria: ['Ground claims'],
            requiresInvestigation: false,
          ),
          evidence: 'Measured evidence.',
          candidateCount: 2,
          deadline: DateTime.now().add(const Duration(minutes: 1)),
          isCancelled: () => cancelled,
          cancelSignal: cancelSignal.future,
          onProgress:
              ({
                required completed,
                required requested,
                required endpointLabels,
              }) {},
        ),
      );
      while (host.requests.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      cancelled = true;
      cancelSignal.complete();

      final result = await resultFuture.timeout(const Duration(seconds: 2));
      expect(result.candidates.map((candidate) => candidate.index), [0]);
      expect(result.attemptedCandidateCount, 2);
    },
  );

  test('retries a thinking-only length result with a larger budget', () async {
    final host = await _CandidateServer.start(
      'host-a',
      exhaustedCandidateAttempts: 1,
    );
    addTearDown(host.close);
    final observedAttempts = <({int count, int maxTokens})>[];
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [_target('a', 'Host A', host.baseUrl)],
      onCandidateCall:
          ({
            required target,
            required candidateIndex,
            required attemptCount,
            required maxTokens,
            required result,
            required error,
            required startedAt,
            required finishedAt,
          }) {
            observedAttempts.add((count: attemptCount, maxTokens: maxTokens));
          },
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 1,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(host.requests.map((request) => request['max_tokens']), [
      32,
      3000,
      6000,
    ]);
    final initialRequest = host.requests[1];
    final recoveryRequest = host.requests[2];
    expect(recoveryRequest['messages'], initialRequest['messages']);
    expect(recoveryRequest['seed'], initialRequest['seed']);
    expect(recoveryRequest['id_slot'], initialRequest['id_slot']);
    expect(recoveryRequest['cache_prompt'], isTrue);
    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.answer, contains('host-a answer'));
    expect(result.attemptedCandidateCount, 1);
    expect(observedAttempts, [(count: 2, maxTokens: 6000)]);
  });

  test('retries partial visible content after a length result', () async {
    final host = await _CandidateServer.start(
      'host-a',
      exhaustedCandidateAttempts: 1,
      partialExhaustedCandidateContent: true,
    );
    addTearDown(host.close);
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [_target('a', 'Host A', host.baseUrl)],
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 1,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(host.requests.map((request) => request['max_tokens']), [
      32,
      3000,
      6000,
    ]);
    expect(result.candidates, hasLength(1));
    expect(result.candidates.single.answer, contains('host-a answer'));
  });

  test('reuses a recovered warm budget for later candidates', () async {
    final host = await _CandidateServer.start(
      'host-a',
      exhaustedCandidateAttempts: 1,
      partialExhaustedCandidateContent: true,
    );
    addTearDown(host.close);
    final observedAttempts = <({int count, int maxTokens})>[];
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [_target('a', 'Host A', host.baseUrl)],
      onCandidateCall:
          ({
            required target,
            required candidateIndex,
            required attemptCount,
            required maxTokens,
            required result,
            required error,
            required startedAt,
            required finishedAt,
          }) {
            observedAttempts.add((count: attemptCount, maxTokens: maxTokens));
          },
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 2,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(host.requests.map((request) => request['max_tokens']), [
      32,
      3000,
      6000,
      6000,
    ]);
    expect(observedAttempts, [
      (count: 2, maxTokens: 6000),
      (count: 1, maxTokens: 6000),
    ]);
    expect(result.candidates, hasLength(2));
  });

  test('keeps a recovered warm budget isolated to its endpoint', () async {
    final hostA = await _CandidateServer.start(
      'host-a',
      exhaustedCandidateAttempts: 1,
      partialExhaustedCandidateContent: true,
    );
    final hostB = await _CandidateServer.start('host-b');
    addTearDown(hostA.close);
    addTearDown(hostB.close);
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [
        _target('a', 'Host A', hostA.baseUrl),
        _target('b', 'Host B', hostB.baseUrl),
      ],
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 3,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(hostA.requests.map((request) => request['max_tokens']), [
      32,
      3000,
      6000,
      6000,
    ]);
    expect(hostB.requests.map((request) => request['max_tokens']), [32, 3000]);
    expect(result.candidates, hasLength(3));
  });

  test('drops a candidate after one exhausted-budget retry', () async {
    final host = await _CandidateServer.start(
      'host-a',
      exhaustedCandidateAttempts: 2,
    );
    addTearDown(host.close);
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [_target('a', 'Host A', host.baseUrl)],
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 1,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(host.requests.map((request) => request['max_tokens']), [
      32,
      3000,
      6000,
    ]);
    expect(result.candidates, isEmpty);
    expect(result.attemptedCandidateCount, 1);
  });

  test('drops partial visible content after a second length result', () async {
    final host = await _CandidateServer.start(
      'host-a',
      exhaustedCandidateAttempts: 2,
      partialExhaustedCandidateContent: true,
    );
    addTearDown(host.close);
    final explorer = ProReasoningCandidateExplorer(
      endpoints: [_target('a', 'Host A', host.baseUrl)],
    );

    final result = await explorer.explore(
      ProReasoningExploreRequest(
        question: 'Choose a deployment strategy.',
        frame: const ProReasoningFrame(
          subQuestions: ['Correctness'],
          investigationSteps: [],
          successCriteria: ['Ground claims'],
          requiresInvestigation: false,
        ),
        evidence: 'Measured evidence.',
        candidateCount: 1,
        deadline: DateTime.now().add(const Duration(seconds: 5)),
        isCancelled: () => false,
        onProgress:
            ({
              required completed,
              required requested,
              required endpointLabels,
            }) {},
      ),
    );

    expect(host.requests.map((request) => request['max_tokens']), [
      32,
      3000,
      6000,
    ]);
    expect(result.candidates, isEmpty);
  });
}

ProReasoningEndpointTarget _target(String id, String label, String baseUrl) =>
    ProReasoningEndpointTarget(
      endpointId: id,
      label: label,
      baseUrl: baseUrl,
      apiKey: 'no-key',
      model: 'reasoning-model',
    );

final class _CandidateServer {
  _CandidateServer._(
    this.server,
    this.label,
    this.holdSecond,
    this.slotsSupported,
    this.modelState,
    this._remainingExhaustedCandidateAttempts,
    this.partialExhaustedCandidateContent,
  );

  final HttpServer server;
  final String label;
  final bool holdSecond;
  final bool slotsSupported;
  final String modelState;
  int _remainingExhaustedCandidateAttempts;
  final bool partialExhaustedCandidateContent;
  final List<Map<String, dynamic>> requests = [];
  final List<String> getPaths = [];
  final Completer<void> _releaseHeldRequest = Completer<void>();
  late final StreamSubscription<HttpRequest> _subscription;
  int _inFlight = 0;
  int maxInFlight = 0;

  String get baseUrl => 'http://${server.address.address}:${server.port}/v1';

  static Future<_CandidateServer> start(
    String label, {
    bool holdSecond = false,
    bool slotsSupported = true,
    String modelState = 'loaded',
    int exhaustedCandidateAttempts = 0,
    bool partialExhaustedCandidateContent = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _CandidateServer._(
      server,
      label,
      holdSecond,
      slotsSupported,
      modelState,
      exhaustedCandidateAttempts,
      partialExhaustedCandidateContent,
    );
    fixture._subscription = server.listen(
      (request) => unawaited(fixture._handle(request)),
    );
    return fixture;
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'GET') {
      getPaths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/slots') {
        request.response.write(
          jsonEncode(
            slotsSupported
                ? [
                    {'id': 0, 'state': 0},
                  ]
                : {'error': 'slots unsupported'},
          ),
        );
      } else if (request.uri.path == '/api/v0/models') {
        request.response.write(
          jsonEncode({
            'data': [
              {'id': 'reasoning-model', 'state': modelState},
            ],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
      return;
    }
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      final body = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      requests.add(body);
      if (holdSecond && requests.length == 2) {
        await _releaseHeldRequest.future;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      request.response.headers.contentType = ContentType.json;
      final exhaustCandidate =
          body['max_tokens'] != 32 && _remainingExhaustedCandidateAttempts > 0;
      if (exhaustCandidate) _remainingExhaustedCandidateAttempts--;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': exhaustCandidate
                    ? partialExhaustedCandidateContent
                          ? '$label partial answer |'
                          : ''
                    : '$label answer ${body['seed']}',
                'reasoning_content': '$label reasoning',
              },
              'finish_reason': exhaustCandidate ? 'length' : 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 20,
            'completion_tokens': exhaustCandidate ? body['max_tokens'] : 5,
          },
          'id_slot': body['id_slot'],
          'timings': {'predicted_ms': 12.5},
        }),
      );
      await request.response.close();
    } catch (_) {
      // Closing the client is the behavior under test for cancellation.
    } finally {
      _inFlight--;
    }
  }

  Future<void> close() async {
    if (!_releaseHeldRequest.isCompleted) _releaseHeldRequest.complete();
    await _subscription.cancel();
    await server.close(force: true);
  }
}
