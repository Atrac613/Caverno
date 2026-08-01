import 'dart:async';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_recorder.dart';
import 'package:caverno/features/chat/domain/services/model_edit_apply_telemetry_service.dart';
import 'package:caverno/features/chat/presentation/providers/model_edit_apply_telemetry_runtime_adapter.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_preset_profile.dart';
import 'package:caverno/features/settings/domain/services/llm_sampler_runtime_feedback_service.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the fallback baseline and persists a successful edit', () async {
    final settings = _RecordingSettingsNotifier();
    final container = ProviderContainer(
      overrides: [settingsNotifierProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);
    final currentSettings = container.read(settingsNotifierProvider);
    final runtime = ModelEditApplyTelemetryRuntimeAdapter(
      container.read(settingsNotifierProvider.notifier),
    );
    final owner = _owner(1);
    runtime.activateOwner(owner);

    final baseline = runtime.baselineFor(currentSettings);
    final result = await runtime.record(
      owner: owner,
      toolResult: _result(
        '{"path":"/workspace/main.dart","replacements":1,"ok":true}',
      ),
      baselineProfile: baseline,
    );

    expect(baseline.model, currentSettings.effectiveModel);
    expect(result.status, ModelEditApplyTelemetryRecordStatus.persisted);
    expect(settings.writes, hasLength(1));
    expect(
      settings.writes.single.probeMetadata[ModelEditApplyTelemetryService
          .attemptsKey],
      '1',
    );
    expect(runtime.isCurrent(owner), isTrue);
  });

  test('persists edit failure before owner-aware sampler feedback', () async {
    final settings = _RecordingSettingsNotifier();
    final container = ProviderContainer(
      overrides: [settingsNotifierProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);
    final runtime = ModelEditApplyTelemetryRuntimeAdapter(
      container.read(settingsNotifierProvider.notifier),
    );
    final owner = _owner(2);
    runtime.activateOwner(owner);

    final result = await runtime.record(
      owner: owner,
      toolResult: _result(
        '{"error":"old_text was not found in the target file"}',
      ),
      baselineProfile: runtime.baselineFor(
        container.read(settingsNotifierProvider),
      ),
    );

    expect(
      result.status,
      ModelEditApplyTelemetryRecordStatus.persistedWithFeedback,
    );
    expect(settings.writes, hasLength(2));
    expect(
      settings.writes.first.probeMetadata[ModelEditApplyTelemetryService
          .attemptsKey],
      '1',
    );
    expect(
      settings
          .writes
          .last
          .probeMetadata[LlmSamplerRuntimeFeedbackService.editApplyFailureCountKey(
        LlmSamplerRequestClass.toolLoop,
      )],
      '1',
    );
  });

  test('rejects delayed feedback after the owner is replaced', () async {
    final gate = Completer<void>();
    final settings = _RecordingSettingsNotifier(gate: gate);
    final container = ProviderContainer(
      overrides: [settingsNotifierProvider.overrideWith(() => settings)],
    );
    addTearDown(container.dispose);
    final runtime = ModelEditApplyTelemetryRuntimeAdapter(
      container.read(settingsNotifierProvider.notifier),
    );
    final retiredOwner = _owner(3);
    final currentOwner = _owner(4);
    runtime.activateOwner(retiredOwner);

    final future = runtime.record(
      owner: retiredOwner,
      toolResult: _result(
        '{"error":"old_text was not found in the target file"}',
      ),
      baselineProfile: runtime.baselineFor(
        container.read(settingsNotifierProvider),
      ),
    );
    await settings.writeStarted.future;
    runtime.activateOwner(currentOwner);
    gate.complete();

    final result = await future;

    expect(
      result.status,
      ModelEditApplyTelemetryRecordStatus.persistenceFailed,
    );
    expect(settings.writes, hasLength(1));
    expect(runtime.isCurrent(retiredOwner), isFalse);
    expect(runtime.isCurrent(currentOwner), isTrue);
  });
}

final class _RecordingSettingsNotifier extends SettingsNotifier {
  _RecordingSettingsNotifier({this.gate});

  final Completer<void>? gate;
  final writeStarted = Completer<void>();
  final List<ModelCapabilityProfile> writes = [];

  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    baseUrl: 'http://localhost:1234/v1',
    model: 'test-model',
  );

  @override
  Future<void> upsertModelCapabilityProfile(
    ModelCapabilityProfile profile, {
    String source = 'probe',
  }) async {
    writes.add(profile);
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
    }
    await gate?.future;
    state = state.copyWith(modelCapabilityProfiles: [profile]);
  }
}

ChatTurnOwner _owner(int generation) => ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: generation,
);

ToolResultInfo _result(String result) => ToolResultInfo(
  id: 'edit-result',
  name: 'edit_file',
  arguments: const {'path': '/workspace/main.dart'},
  result: result,
);
