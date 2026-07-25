import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/planning_executor_profile.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

AppSettings _settings({
  String planningModel = '',
  List<ModelCapabilityProfile> capabilityProfiles = const [],
  List<ModelHarnessConfig> harnessConfigs = const [],
}) {
  return AppSettings.defaults().copyWith(
    baseUrl: 'http://localhost:1234/v1',
    model: 'executor-model',
    planningModel: planningModel,
    modelCapabilityProfiles: capabilityProfiles,
    modelHarnessConfigs: harnessConfigs,
  );
}

ModelCapabilityProfile _capabilityProfile({
  int usableContextTokens = 0,
  ModelToolCallStyle toolCallStyle = ModelToolCallStyle.unknown,
  ModelEditFormatPreference editFormatPreference =
      ModelEditFormatPreference.unknown,
}) {
  return ModelCapabilityProfile(
    id: ModelCapabilityProfile.buildId(
      provider: LlmProvider.openAiCompatible,
      baseUrl: 'http://localhost:1234/v1',
      model: 'executor-model',
    ),
    baseUrl: 'http://localhost:1234/v1',
    model: 'executor-model',
    usableContextTokens: usableContextTokens,
    toolCallStyle: toolCallStyle,
    editFormatPreference: editFormatPreference,
  );
}

void main() {
  test('no executor profile when plan drafting runs on the executor model', () {
    expect(PlanningExecutorProfile.fromSettings(_settings()), isNull);
    expect(
      PlanningExecutorProfile.fromSettings(
        _settings(planningModel: 'executor-model'),
      ),
      isNull,
      reason:
          'an explicit assignment to the main model is still planner == executor',
    );
  });

  test('carries the measured executor budget when planning is routed', () {
    final profile = PlanningExecutorProfile.fromSettings(
      _settings(
        planningModel: 'planner-model',
        capabilityProfiles: [
          _capabilityProfile(
            usableContextTokens: 32768,
            toolCallStyle: ModelToolCallStyle.nativeToolCalls,
          ),
        ],
      ),
    );

    expect(profile, isNotNull);
    expect(profile!.model, 'executor-model');
    expect(profile.usableContextTokens, 32768);
    expect(
      profile.toolLoopMaxIterations,
      PlanningExecutorProfile.defaultToolLoopMaxIterations,
      reason: 'no harness override is stored, so the loop default is reported',
    );

    final block = profile.toPromptBlock();
    expect(block, contains('- model: executor-model'));
    expect(block, contains('- usableContextTokens: 32768'));
    expect(block, contains('Prefer more, smaller tasks over few large ones.'));
  });

  test('discloses only facts a prompt rule acts on', () {
    final block = PlanningExecutorProfile.fromSettings(
      _settings(
        planningModel: 'planner-model',
        capabilityProfiles: [
          _capabilityProfile(
            usableContextTokens: 32768,
            toolCallStyle: ModelToolCallStyle.nativeToolCalls,
            editFormatPreference: ModelEditFormatPreference.wholeFile,
          ),
        ],
      ),
    )?.toPromptBlock();

    expect(block, contains('- usableContextTokens: 32768'));
    expect(
      block,
      isNot(contains('toolCallStyle')),
      reason:
          'a bare capability with no rule attached only spends instruction budget',
    );
    expect(block, isNot(contains('editFormat')));
    expect(block, isNot(contains('structuredOutput')));
  });

  test('reports the stored tool-loop override', () {
    final profile = PlanningExecutorProfile.fromSettings(
      _settings(
        planningModel: 'planner-model',
        harnessConfigs: [
          const ModelHarnessConfig(
            id: 'harness-1',
            baseUrl: 'http://localhost:1234/v1',
            model: 'executor-model',
            toolLoopMaxIterations: 40,
          ),
        ],
      ),
    );

    expect(profile?.toolLoopMaxIterations, 40);
    expect(profile?.toPromptBlock(), contains('- toolLoopMaxIterations: 40'));
  });

  test('omits capabilities that were never probed', () {
    final profile = PlanningExecutorProfile.fromSettings(
      _settings(planningModel: 'planner-model'),
    );
    final block = profile?.toPromptBlock();

    expect(block, isNotNull);
    expect(block, contains('- model: executor-model'));
    expect(
      block,
      isNot(contains('usableContextTokens')),
      reason: 'an unprobed context window must not be guessed',
    );
  });

  test('compact block stays a single line', () {
    final profile = PlanningExecutorProfile.fromSettings(
      _settings(
        planningModel: 'planner-model',
        capabilityProfiles: [_capabilityProfile(usableContextTokens: 8192)],
      ),
    );

    final block = profile!.toPromptBlock(compact: true)!;
    expect(block.split('\n'), hasLength(1));
    expect(block, contains('context: 8192 tokens'));
  });
}
