import 'dart:async';
import 'dart:collection';

import 'package:test/test.dart';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_recorder.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_service.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_runtime_feedback_service.dart';

void main() {
  group('ModelEditApplyTelemetryBaseline', () {
    test('keeps an explicit effective profile unchanged', () {
      final effective = _profile(model: 'effective-model');

      final resolved = ModelEditApplyTelemetryBaseline.resolve(
        effectiveProfile: effective,
        provider: LlmProvider.appleFoundationModels,
        baseUrl: 'ignored',
        model: 'ignored',
      );

      expect(resolved, same(effective));
    });

    test('constructs the current normalized fallback profile', () {
      final resolved = ModelEditApplyTelemetryBaseline.resolve(
        effectiveProfile: null,
        provider: LlmProvider.openAiCompatible,
        baseUrl: '  HTTP://LOCALHOST:1234/v1  ',
        model: '  fallback-model  ',
      );

      expect(resolved.provider, LlmProvider.openAiCompatible);
      expect(resolved.baseUrl, 'HTTP://LOCALHOST:1234/v1');
      expect(resolved.model, 'fallback-model');
      expect(
        resolved.id,
        ModelCapabilityProfile.buildId(
          provider: LlmProvider.openAiCompatible,
          baseUrl: 'HTTP://LOCALHOST:1234/v1',
          model: 'fallback-model',
        ),
      );
      expect(resolved.probeMetadata, isEmpty);
    });
  });

  group('ModelEditApplyTelemetryRecorder', () {
    test(
      'returns no update for non-edit and externally denied results',
      () async {
        final fixture = _Fixture();
        final owner = _owner('owner-a', 1);
        final results = <ModelEditApplyTelemetryRecordResult>[
          await fixture.recorder.record(
            owner: owner,
            toolResult: _toolResult(
              name: 'read_file',
              result: '{"path":"/workspace/a.dart"}',
            ),
            baselineProfile: _profile(),
          ),
          await fixture.recorder.record(
            owner: owner,
            toolResult: _toolResult(
              result:
                  '{"error":"User denied file edit","code":"approval_denied"}',
            ),
            baselineProfile: _profile(),
          ),
        ];

        expect(
          results.map((result) => result.status),
          everyElement(ModelEditApplyTelemetryRecordStatus.noUpdate),
        );
        expect(
          results.map((result) => result.observation),
          everyElement(isNull),
        );
        expect(
          results.map((result) => result.persistedProfile),
          everyElement(isNull),
        );
        expect(
          results.map((result) => result.didPersist),
          everyElement(isFalse),
        );
        expect(fixture.store.calls, isEmpty);
        expect(fixture.feedback.calls, isEmpty);
      },
    );

    test('persists a successful edit without runtime feedback', () async {
      final fixture = _Fixture();
      final owner = _owner('owner-a', 2);
      final baseline = _profile(
        metadata: const {ModelEditApplyTelemetryService.attemptsKey: '2'},
      );

      final result = await fixture.recorder.record(
        owner: owner,
        toolResult: _toolResult(
          path: '/workspace/success.dart',
          result:
              '{"path":"/workspace/success.dart","replacements":1,"ok":true}',
        ),
        baselineProfile: baseline,
      );

      expect(result.status, ModelEditApplyTelemetryRecordStatus.persisted);
      expect(result.observation!.outcome, ModelEditApplyOutcome.success);
      expect(result.observation!.path, '/workspace/success.dart');
      expect(result.didPersist, isTrue);
      expect(fixture.store.calls, hasLength(1));
      expect(fixture.store.calls.single.owner, same(owner));
      expect(fixture.store.calls.single.profile, same(result.persistedProfile));
      expect(
        result.persistedProfile!.probeMetadata[ModelEditApplyTelemetryService
            .attemptsKey],
        '3',
      );
      expect(
        result.persistedProfile!.probeMetadata[ModelEditApplyTelemetryService
            .successesKey],
        '1',
      );
      expect(
        baseline.probeMetadata[ModelEditApplyTelemetryService.attemptsKey],
        '2',
      );
      expect(
        () => result.persistedProfile!.probeMetadata['poison'] = 'mutation',
        throwsUnsupportedError,
      );
      expect(fixture.feedback.calls, isEmpty);
      expect(fixture.events, <String>[
        'persist:start:owner-a',
        'persist:end:owner-a',
      ]);
    });

    final failures =
        <({String label, String result, ModelEditApplyOutcome outcome})>[
          (
            label: 'edit mismatch',
            result: '{"error":"old_text was not found in the target file"}',
            outcome: ModelEditApplyOutcome.editMismatch,
          ),
          (
            label: 'multiple matches',
            result: '{"error":"old_text matched multiple locations"}',
            outcome: ModelEditApplyOutcome.multipleMatches,
          ),
          (
            label: 'malformed request',
            result: '{"error":"path is required"}',
            outcome: ModelEditApplyOutcome.malformedRequest,
          ),
          (
            label: 'missing file',
            result: '{"error":"file does not exist"}',
            outcome: ModelEditApplyOutcome.missingFile,
          ),
          (
            label: 'other failure',
            result: '{"error":"disk write failed"}',
            outcome: ModelEditApplyOutcome.otherFailure,
          ),
        ];

    for (final failure in failures) {
      test(
        'preserves ${failure.label} classification and failure feedback',
        () async {
          final fixture = _Fixture();
          final owner = _owner('failure-owner', 3);

          final result = await fixture.recorder.record(
            owner: owner,
            toolResult: _toolResult(
              path: '/workspace/failure.dart',
              result: failure.result,
            ),
            baselineProfile: _profile(),
          );

          expect(
            result.status,
            ModelEditApplyTelemetryRecordStatus.persistedWithFeedback,
          );
          expect(result.observation!.outcome, failure.outcome);
          expect(result.observation!.isFailure, isTrue);
          expect(result.didPersist, isTrue);
          expect(fixture.store.calls.single.owner, same(owner));
          expect(fixture.feedback.calls, hasLength(1));
          final feedback = fixture.feedback.calls.single;
          expect(feedback.owner, same(owner));
          expect(feedback.baselineProfile, same(result.persistedProfile));
          expect(feedback.signal.requestClass, LlmSamplerRequestClass.toolLoop);
          expect(feedback.signal.editApplyFailureCount, 1);
          expect(feedback.signal.jsonRepairEventCount, 0);
          expect(feedback.signal.malformedToolCallCount, 0);
          expect(feedback.signal.repetitionDetected, isFalse);
          expect(fixture.events, <String>[
            'persist:start:failure-owner',
            'persist:end:failure-owner',
            'feedback:failure-owner',
          ]);
        },
      );
    }

    test('swallows persistence failure and skips failure feedback', () async {
      final fixture = _Fixture(
        storeErrors: <String, Object>{
          'owner-a': StateError('profile store failed'),
        },
      );
      final owner = _owner('owner-a', 4);

      final result = await fixture.recorder.record(
        owner: owner,
        toolResult: _failureResult('/workspace/a.dart'),
        baselineProfile: _profile(),
      );

      expect(
        result.status,
        ModelEditApplyTelemetryRecordStatus.persistenceFailed,
      );
      expect(result.observation!.outcome, ModelEditApplyOutcome.editMismatch);
      expect(result.persistedProfile, isNull);
      expect(result.didPersist, isFalse);
      expect(fixture.store.calls.single.owner, same(owner));
      expect(fixture.feedback.calls, isEmpty);
      expect(fixture.events, <String>['persist:start:owner-a']);
    });

    test(
      'swallows feedback failure and returns the persisted profile',
      () async {
        final fixture = _Fixture(
          feedbackErrors: <String, Object>{
            'owner-a': StateError('feedback failed'),
          },
        );
        final owner = _owner('owner-a', 5);

        final result = await fixture.recorder.record(
          owner: owner,
          toolResult: _failureResult('/workspace/a.dart'),
          baselineProfile: _profile(),
        );

        expect(
          result.status,
          ModelEditApplyTelemetryRecordStatus.feedbackFailed,
        );
        expect(result.observation!.outcome, ModelEditApplyOutcome.editMismatch);
        expect(result.didPersist, isTrue);
        expect(
          result.persistedProfile,
          same(fixture.store.calls.single.profile),
        );
        expect(fixture.feedback.calls.single.owner, same(owner));
        expect(fixture.events, <String>[
          'persist:start:owner-a',
          'persist:end:owner-a',
          'feedback:owner-a',
        ]);
      },
    );

    test('swallows unexpected classification and update errors', () async {
      final fixture = _Fixture();
      final owner = _owner('owner-a', 6);

      final result = await fixture.recorder.record(
        owner: owner,
        toolResult: ToolResultInfo(
          id: 'tool-throwing',
          name: 'edit_file',
          arguments: _ThrowingMap(),
          result: '{"replacements":1}',
        ),
        baselineProfile: _profile(),
      );

      expect(result.status, ModelEditApplyTelemetryRecordStatus.updateFailed);
      expect(result.observation, isNull);
      expect(result.persistedProfile, isNull);
      expect(result.didPersist, isFalse);
      expect(fixture.store.calls, isEmpty);
      expect(fixture.feedback.calls, isEmpty);
    });

    test(
      'keeps owners and baselines paired across delayed persistence',
      () async {
        final ownerA = _owner('shared-owner', 7);
        final ownerB = _owner('shared-owner', 8);
        final ownerAGate = Completer<void>();
        final fixture = _Fixture(
          storeGates: <String, Completer<void>>{'shared-owner#7': ownerAGate},
        );

        final ownerAFuture = fixture.recorder.record(
          owner: ownerA,
          toolResult: _failureResult('/workspace/generation-7.dart'),
          baselineProfile: _profile(
            model: 'model-generation-7',
            metadata: const {'capturedOwner': 'generation-7'},
          ),
        );
        final ownerBResult = await fixture.recorder.record(
          owner: ownerB,
          toolResult: _failureResult('/workspace/generation-8.dart'),
          baselineProfile: _profile(
            model: 'model-generation-8',
            metadata: const {'capturedOwner': 'generation-8'},
          ),
        );

        expect(
          ownerBResult.status,
          ModelEditApplyTelemetryRecordStatus.persistedWithFeedback,
        );
        expect(fixture.store.calls.map((call) => call.owner), <ChatTurnOwner>[
          ownerA,
          ownerB,
        ]);
        expect(fixture.store.calls.map((call) => call.profile.model), <String>[
          'model-generation-7',
          'model-generation-8',
        ]);
        expect(fixture.feedback.calls, hasLength(1));
        expect(fixture.feedback.calls.single.owner, same(ownerB));
        expect(
          fixture.feedback.calls.single.baselineProfile.model,
          'model-generation-8',
        );
        expect(
          fixture
              .feedback
              .calls
              .single
              .baselineProfile
              .probeMetadata[ModelEditApplyTelemetryService.lastPathKey],
          '/workspace/generation-8.dart',
        );
        expect(
          fixture
              .feedback
              .calls
              .single
              .baselineProfile
              .probeMetadata['capturedOwner'],
          'generation-8',
        );

        ownerAGate.complete();
        final ownerAResult = await ownerAFuture;

        expect(
          ownerAResult.status,
          ModelEditApplyTelemetryRecordStatus.persistedWithFeedback,
        );
        expect(fixture.feedback.calls, hasLength(2));
        expect(fixture.feedback.calls[1].owner, same(ownerA));
        expect(
          fixture.feedback.calls[1].baselineProfile.model,
          'model-generation-7',
        );
        expect(
          fixture
              .feedback
              .calls[1]
              .baselineProfile
              .probeMetadata[ModelEditApplyTelemetryService.lastPathKey],
          '/workspace/generation-7.dart',
        );
        expect(
          fixture
              .feedback
              .calls[1]
              .baselineProfile
              .probeMetadata['capturedOwner'],
          'generation-7',
        );
        expect(fixture.events, <String>[
          'persist:start:shared-owner',
          'persist:start:shared-owner',
          'persist:end:shared-owner',
          'feedback:shared-owner',
          'persist:end:shared-owner',
          'feedback:shared-owner',
        ]);
      },
    );
  });
}

final class _Fixture {
  _Fixture({
    Map<String, Object> storeErrors = const <String, Object>{},
    Map<String, Object> feedbackErrors = const <String, Object>{},
    Map<String, Completer<void>> storeGates = const <String, Completer<void>>{},
  }) : store = _ProfileStore(
         events: <String>[],
         errors: storeErrors,
         gates: storeGates,
       ),
       feedback = _RuntimeFeedback(events: <String>[], errors: feedbackErrors) {
    store.events = events;
    feedback.events = events;
    recorder = ModelEditApplyTelemetryRecorder(
      profileStore: store,
      runtimeFeedback: feedback,
    );
  }

  final List<String> events = <String>[];
  final _ProfileStore store;
  final _RuntimeFeedback feedback;
  late final ModelEditApplyTelemetryRecorder recorder;
}

typedef _StoreCall = ({ChatTurnOwner owner, ModelCapabilityProfile profile});

final class _ProfileStore implements ModelCapabilityProfileStorePort {
  _ProfileStore({
    required this.events,
    required this.errors,
    required this.gates,
  });

  List<String> events;
  final Map<String, Object> errors;
  final Map<String, Completer<void>> gates;
  final List<_StoreCall> calls = <_StoreCall>[];

  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) async {
    calls.add((owner: owner, profile: profile));
    events.add('persist:start:${owner.conversationId}');
    final gate =
        gates['${owner.conversationId}#${owner.interactionGeneration}'] ??
        gates[owner.conversationId];
    if (gate != null) {
      await gate.future;
    }
    final error = errors[owner.conversationId];
    if (error != null) {
      throw error;
    }
    events.add('persist:end:${owner.conversationId}');
  }
}

typedef _FeedbackCall = ({
  ChatTurnOwner owner,
  ModelCapabilityProfile baselineProfile,
  LlmSamplerRuntimeFeedbackSignal signal,
});

final class _RuntimeFeedback implements RuntimeSamplerFeedbackPort {
  _RuntimeFeedback({required this.events, required this.errors});

  List<String> events;
  final Map<String, Object> errors;
  final List<_FeedbackCall> calls = <_FeedbackCall>[];

  @override
  Future<void> record({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile baselineProfile,
    required LlmSamplerRuntimeFeedbackSignal signal,
  }) async {
    calls.add((owner: owner, baselineProfile: baselineProfile, signal: signal));
    events.add('feedback:${owner.conversationId}');
    final error = errors[owner.conversationId];
    if (error != null) {
      throw error;
    }
  }
}

final class _ThrowingMap extends MapBase<String, dynamic> {
  @override
  dynamic operator [](Object? key) {
    throw StateError('argument lookup failed');
  }

  @override
  void operator []=(String key, dynamic value) {
    throw UnsupportedError('read only');
  }

  @override
  void clear() {
    throw UnsupportedError('read only');
  }

  @override
  Iterable<String> get keys => const <String>[];

  @override
  dynamic remove(Object? key) {
    throw UnsupportedError('read only');
  }
}

ChatTurnOwner _owner(String conversationId, int generation) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

ModelCapabilityProfile _profile({
  String model = 'baseline-model',
  Map<String, String> metadata = const <String, String>{},
}) {
  return ModelCapabilityProfile(
    id: '',
    baseUrl: 'http://localhost:1234/v1',
    model: model,
    probeMetadata: metadata,
  ).normalizedForPersistence();
}

ToolResultInfo _failureResult(String path) {
  return _toolResult(
    path: path,
    result: '{"error":"old_text was not found in the target file"}',
  );
}

ToolResultInfo _toolResult({
  String name = 'edit_file',
  String path = '/workspace/a.dart',
  required String result,
}) {
  return ToolResultInfo(
    id: 'tool-1',
    name: name,
    arguments: <String, dynamic>{'path': path},
    result: result,
  );
}
