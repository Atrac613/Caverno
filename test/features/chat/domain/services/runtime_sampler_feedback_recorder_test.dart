import 'dart:async';

import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/services/runtime_sampler_feedback_recorder.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_runtime_feedback_service.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeSamplerFeedbackRecorder malformed calls', () {
    test('records every authoritative malformed-call pattern', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final matchingMessages = [
        'No matching tool is available.',
        'Unknown tool requested.',
        'Malformed tool call payload.',
        'Invalid tool arguments.',
        'Required argument is missing.',
        'Required parameter is missing.',
        'Required field is missing.',
        'Required path is missing.',
        'Required pattern is missing.',
      ];

      for (var index = 0; index < matchingMessages.length; index++) {
        await recorder.recordEvent(
          RuntimeSamplerMalformedToolCallEvent(
            owner: _owner('conversation-$index'),
            baselineProfile: _profile('model-$index'),
            message: matchingMessages[index],
          ),
        );
      }

      expect(store.writes, hasLength(matchingMessages.length));
      for (final write in store.writes) {
        expect(
          write
              .profile
              .probeMetadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
            LlmSamplerRequestClass.toolLoop,
          )],
          '1',
        );
      }
    });

    test('ignores messages that do not match malformed-call policy', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

      for (final message in [
        'Tool execution failed.',
        'The required operation was denied.',
        'The argument was accepted.',
        'No tool result was returned.',
      ]) {
        await recorder.recordEvent(
          RuntimeSamplerMalformedToolCallEvent(
            owner: _owner('conversation-a'),
            baselineProfile: _profile('model-a'),
            message: message,
          ),
        );
      }

      expect(store.writes, isEmpty);
    });
  });

  group('RuntimeSamplerFeedbackRecorder classified events', () {
    test('event binding delegates the immutable event to its sink', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final event = RuntimeSamplerToolLoopRepetitionEvent(
        owner: _owner('conversation-a'),
        baselineProfile: _profile('model-a'),
      );
      final binding = RuntimeSamplerFeedbackEventBinding(
        sink: recorder,
        event: event,
      );

      await binding.record();

      expect(store.writes.single.owner, event.owner);
    });

    test('records repetition as one tool-loop signal', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

      await recorder.recordEvent(
        RuntimeSamplerToolLoopRepetitionEvent(
          owner: _owner('conversation-a'),
          baselineProfile: _profile('model-a'),
        ),
      );

      final metadata = store.writes.single.profile.probeMetadata;
      expect(
        metadata[LlmSamplerRuntimeFeedbackService.repetitionCountKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        '1',
      );
      expect(
        metadata[LlmSamplerPresetProfile.sourceKey(
          LlmSamplerRequestClass.toolLoop,
        )],
        LlmSamplerRuntimeFeedbackService.runtimeSource,
      );
    });

    test('maps every assistant mode for planning JSON repair', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final requestClassByMode = {
        AssistantMode.coding: LlmSamplerRequestClass.coding,
        AssistantMode.plan: LlmSamplerRequestClass.plan,
        AssistantMode.general: LlmSamplerRequestClass.toolLoop,
      };

      for (final entry in requestClassByMode.entries) {
        await recorder.recordEvent(
          RuntimeSamplerPlanningJsonRepairEvent(
            owner: _owner('conversation-${entry.key.name}'),
            baselineProfile: _profile('model-${entry.key.name}'),
            settingsLoaded: true,
            assistantMode: entry.key,
          ),
        );
      }

      expect(store.writes, hasLength(requestClassByMode.length));
      for (final write in store.writes) {
        final mode = AssistantMode.values.byName(
          write.owner.conversationId.substring('conversation-'.length),
        );
        final requestClass = requestClassByMode[mode]!;
        expect(
          write
              .profile
              .probeMetadata[LlmSamplerRuntimeFeedbackService.jsonRepairCountKey(
            requestClass,
          )],
          '1',
        );
      }
    });

    test('ignores planning repairs until settings are loaded', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

      await recorder.recordEvent(
        RuntimeSamplerPlanningJsonRepairEvent(
          owner: _owner('conversation-a'),
          baselineProfile: _profile('model-a'),
          settingsLoaded: false,
          assistantMode: AssistantMode.plan,
        ),
      );

      expect(store.writes, isEmpty);
    });

    test('preserves every explicit JSON repair request class', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

      for (final requestClass in LlmSamplerRequestClass.values) {
        await recorder.recordEvent(
          RuntimeSamplerJsonRepairEvent(
            owner: _owner('conversation-${requestClass.name}'),
            baselineProfile: _profile('model-${requestClass.name}'),
            requestClass: requestClass,
          ),
        );
      }

      expect(store.writes, hasLength(LlmSamplerRequestClass.values.length));
      for (var index = 0; index < store.writes.length; index++) {
        final requestClass = LlmSamplerRequestClass.values[index];
        expect(
          store
              .writes[index]
              .profile
              .probeMetadata[LlmSamplerRuntimeFeedbackService.jsonRepairCountKey(
            requestClass,
          )],
          '1',
        );
      }
    });

    test('passes every generic signal field to the sampler policy', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final RuntimeSamplerFeedbackPort feedbackPort = recorder;
      const requestClass = LlmSamplerRequestClass.routine;

      await feedbackPort.record(
        owner: _owner('conversation-a'),
        baselineProfile: _profile('model-a'),
        signal: const LlmSamplerRuntimeFeedbackSignal(
          requestClass: requestClass,
          jsonRepairEventCount: 2,
          malformedToolCallCount: 3,
          editApplyFailureCount: 4,
          repetitionDetected: true,
        ),
      );

      final metadata = store.writes.single.profile.probeMetadata;
      expect(
        metadata[LlmSamplerRuntimeFeedbackService.jsonRepairCountKey(
          requestClass,
        )],
        '2',
      );
      expect(
        metadata[LlmSamplerRuntimeFeedbackService.malformedToolCallCountKey(
          requestClass,
        )],
        '3',
      );
      expect(
        metadata[LlmSamplerRuntimeFeedbackService.editApplyFailureCountKey(
          requestClass,
        )],
        '4',
      );
      expect(
        metadata[LlmSamplerRuntimeFeedbackService.repetitionCountKey(
          requestClass,
        )],
        '1',
      );
    });

    test('does not persist a null policy update', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

      await recorder.record(
        owner: _owner('conversation-a'),
        baselineProfile: _profile('model-a'),
        signal: const LlmSamplerRuntimeFeedbackSignal(
          requestClass: LlmSamplerRequestClass.agentic,
        ),
      );

      expect(store.writes, isEmpty);
    });

    test('required port completes after successful persistence', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final port = RuntimeSamplerFeedbackRequiredPort(recorder);

      await port.record(
        owner: _owner('conversation-a'),
        baselineProfile: _profile('model-a'),
        signal: const LlmSamplerRuntimeFeedbackSignal(
          requestClass: LlmSamplerRequestClass.toolLoop,
          malformedToolCallCount: 1,
        ),
      );

      expect(store.writes, hasLength(1));
    });

    test('required port reports a failed best-effort receipt', () async {
      final recorder = RuntimeSamplerFeedbackRecorder(
        profileStore: _ThrowingProfileStore(),
      );
      final port = RuntimeSamplerFeedbackRequiredPort(recorder);

      await expectLater(
        port.record(
          owner: _owner('conversation-a'),
          baselineProfile: _profile('model-a'),
          signal: const LlmSamplerRuntimeFeedbackSignal(
            requestClass: LlmSamplerRequestClass.toolLoop,
            malformedToolCallCount: 1,
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('RuntimeSamplerFeedbackRecorder persistence boundary', () {
    test('classifies feedback before invoking profile persistence', () async {
      final order = <String>[];
      final recorder = RuntimeSamplerFeedbackRecorder(
        profileStore: _OrderingProfileStore(order),
        feedbackService: _OrderingFeedbackService(order),
      );

      await recorder.recordEvent(
        RuntimeSamplerJsonRepairEvent(
          owner: _owner('conversation-a'),
          baselineProfile: _profile('model-a'),
          requestClass: LlmSamplerRequestClass.plan,
        ),
      );

      expect(order, ['feedback', 'persist']);
    });

    test('persists the updated profile with the originating owner', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final owner = _owner('conversation-a', generation: 7);

      await recorder.recordEvent(
        RuntimeSamplerJsonRepairEvent(
          owner: owner,
          baselineProfile: _profile('  model-a  '),
          requestClass: LlmSamplerRequestClass.plan,
        ),
      );

      final write = store.writes.single;
      expect(write.owner, owner);
      expect(write.profile.normalizedModel, 'model-a');
      expect(write.profile.id, write.profile.computedId);
      expect(
        write
            .profile
            .probeMetadata[LlmSamplerRuntimeFeedbackService.jsonRepairCountKey(
          LlmSamplerRequestClass.plan,
        )],
        '1',
      );
    });

    test('snapshots baseline metadata before an unawaited write', () async {
      final store = _DelayedProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
      final metadata = <String, String>{'owner': 'conversation-a'};
      final event = RuntimeSamplerJsonRepairEvent(
        owner: _owner('conversation-a'),
        baselineProfile: _profile('model-a', metadata: metadata),
        requestClass: LlmSamplerRequestClass.plan,
      );
      metadata['owner'] = 'poisoned';

      final recording = recorder.recordEvent(event);
      expect(
        store.writes.single.profile.probeMetadata['owner'],
        'conversation-a',
      );
      expect(
        () => event.baselineProfile.probeMetadata['owner'] = 'poisoned-again',
        throwsUnsupportedError,
      );
      expect(store.isPending(event.owner), isTrue);

      store.complete(event.owner);
      await recording;
    });

    test(
      'keeps owner identity when delayed writes finish out of order',
      () async {
        final store = _DelayedProfileStore();
        final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);
        final ownerA = _owner('shared-conversation', generation: 2);
        final ownerB = _owner('shared-conversation', generation: 9);

        final recordingA = recorder.recordEvent(
          RuntimeSamplerJsonRepairEvent(
            owner: ownerA,
            baselineProfile: _profile('model-a'),
            requestClass: LlmSamplerRequestClass.coding,
          ),
        );
        final recordingB = recorder.recordEvent(
          RuntimeSamplerJsonRepairEvent(
            owner: ownerB,
            baselineProfile: _profile('model-b'),
            requestClass: LlmSamplerRequestClass.plan,
          ),
        );

        expect(store.writes.map((write) => write.owner), [ownerA, ownerB]);
        expect(store.writes.map((write) => write.profile.normalizedModel), [
          'model-a',
          'model-b',
        ]);
        store.complete(ownerB);
        await recordingB;
        store.complete(ownerA);
        await recordingA;
        expect(store.completionOrder, [ownerB, ownerA]);
      },
    );

    test('swallows synchronous and asynchronous persistence errors', () async {
      for (final store in [
        _ThrowingProfileStore(),
        _AsyncThrowingProfileStore(),
      ]) {
        final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

        await expectLater(
          recorder.recordEvent(
            RuntimeSamplerJsonRepairEvent(
              owner: _owner('conversation-a'),
              baselineProfile: _profile('model-a'),
              requestClass: LlmSamplerRequestClass.plan,
            ),
          ),
          completes,
        );
      }
    });

    test('swallows sampler policy errors before persistence', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(
        profileStore: store,
        feedbackService: const _ThrowingFeedbackService(),
      );

      await expectLater(
        recorder.recordEvent(
          RuntimeSamplerJsonRepairEvent(
            owner: _owner('conversation-a'),
            baselineProfile: _profile('model-a'),
            requestClass: LlmSamplerRequestClass.plan,
          ),
        ),
        completes,
      );
      expect(store.writes, isEmpty);
    });

    test('swallows generic event snapshot errors', () async {
      final store = _ProfileStore();
      final recorder = RuntimeSamplerFeedbackRecorder(profileStore: store);

      await expectLater(
        recorder.record(
          owner: _owner('conversation-a'),
          baselineProfile: _profile('model-a'),
          signal: const _ThrowingSignal(),
        ),
        completes,
      );
      expect(store.writes, isEmpty);
    });

    test('every event remains best effort when persistence fails', () async {
      final recorder = RuntimeSamplerFeedbackRecorder(
        profileStore: _ThrowingProfileStore(),
      );
      final owner = _owner('conversation-a');
      final profile = _profile('model-a');
      final events = <RuntimeSamplerFeedbackEvent>[
        RuntimeSamplerMalformedToolCallEvent(
          owner: owner,
          baselineProfile: profile,
          message: 'Malformed tool call.',
        ),
        RuntimeSamplerToolLoopRepetitionEvent(
          owner: owner,
          baselineProfile: profile,
        ),
        RuntimeSamplerPlanningJsonRepairEvent(
          owner: owner,
          baselineProfile: profile,
          settingsLoaded: true,
          assistantMode: AssistantMode.plan,
        ),
        RuntimeSamplerJsonRepairEvent(
          owner: owner,
          baselineProfile: profile,
          requestClass: LlmSamplerRequestClass.coding,
        ),
        RuntimeSamplerGenericSignalEvent(
          owner: owner,
          baselineProfile: profile,
          signal: const LlmSamplerRuntimeFeedbackSignal(
            requestClass: LlmSamplerRequestClass.toolLoop,
            malformedToolCallCount: 1,
          ),
        ),
      ];

      for (final event in events) {
        await expectLater(recorder.recordEvent(event), completes);
      }
    });
  });
}

typedef _ProfileWrite = ({ChatTurnOwner owner, ModelCapabilityProfile profile});

class _ProfileStore implements ModelCapabilityProfileStorePort {
  final List<_ProfileWrite> writes = [];

  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) async {
    writes.add((owner: owner, profile: profile));
  }
}

class _DelayedProfileStore implements ModelCapabilityProfileStorePort {
  final List<_ProfileWrite> writes = [];
  final List<ChatTurnOwner> completionOrder = [];
  final Map<ChatTurnOwner, Completer<void>> _pending = {};

  bool isPending(ChatTurnOwner owner) => _pending.containsKey(owner);

  void complete(ChatTurnOwner owner) {
    completionOrder.add(owner);
    _pending.remove(owner)!.complete();
  }

  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) {
    writes.add((owner: owner, profile: profile));
    final completer = Completer<void>();
    _pending[owner] = completer;
    return completer.future;
  }
}

class _ThrowingProfileStore implements ModelCapabilityProfileStorePort {
  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) {
    throw StateError('synchronous persistence failure');
  }
}

class _AsyncThrowingProfileStore implements ModelCapabilityProfileStorePort {
  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) async {
    throw StateError('asynchronous persistence failure');
  }
}

class _OrderingProfileStore implements ModelCapabilityProfileStorePort {
  _OrderingProfileStore(this.order);

  final List<String> order;

  @override
  Future<void> persist({
    required ChatTurnOwner owner,
    required ModelCapabilityProfile profile,
  }) async {
    order.add('persist');
  }
}

class _OrderingFeedbackService extends LlmSamplerRuntimeFeedbackService {
  _OrderingFeedbackService(this.order);

  final List<String> order;

  @override
  LlmSamplerRuntimeFeedbackResult? recordSignal({
    required ModelCapabilityProfile profile,
    required LlmSamplerRuntimeFeedbackSignal signal,
    DateTime? observedAt,
  }) {
    order.add('feedback');
    return super.recordSignal(
      profile: profile,
      signal: signal,
      observedAt: observedAt,
    );
  }
}

class _ThrowingFeedbackService extends LlmSamplerRuntimeFeedbackService {
  const _ThrowingFeedbackService();

  @override
  LlmSamplerRuntimeFeedbackResult? recordSignal({
    required ModelCapabilityProfile profile,
    required LlmSamplerRuntimeFeedbackSignal signal,
    DateTime? observedAt,
  }) {
    throw StateError('sampler policy failure');
  }
}

class _ThrowingSignal extends LlmSamplerRuntimeFeedbackSignal {
  const _ThrowingSignal() : super(requestClass: LlmSamplerRequestClass.agentic);

  @override
  LlmSamplerRequestClass get requestClass {
    throw StateError('signal snapshot failure');
  }
}

ChatTurnOwner _owner(String conversationId, {int generation = 1}) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

ModelCapabilityProfile _profile(
  String model, {
  Map<String, String> metadata = const {},
}) {
  return ModelCapabilityProfile(
    id: 'stale-id',
    provider: LlmProvider.openAiCompatible,
    baseUrl: ' http://localhost:1234/v1 ',
    model: model,
    probeMetadata: metadata,
  );
}
