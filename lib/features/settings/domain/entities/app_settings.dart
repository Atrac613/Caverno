// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/goal_completion_policy.dart';

export '../../../../core/types/goal_completion_policy.dart';

part 'app_settings.freezed.dart';
part 'app_settings.g.dart';

const defaultFeedbackEndpointUrl =
    'https://hvu27dbkjku36mfqcgo6eenvti0gkdvv.lambda-url.ap-northeast-1.on.aws/';

/// Transport type for an MCP server.
enum McpServerType { http, stdio }

enum McpServerTrustState { pending, trusted, blocked }

enum LocalCommandPermissionAction { allow, deny, ask }

enum LocalCommandPermissionMatch { exact, prefix }

enum CodingVerificationTriggerPolicy { onCompletionClaim, onRequestOnly, off }

enum ReasoningEffortPreference { automatic, low, medium, high }

enum ProReasoningDepth { standard, deep, max }

enum ProReasoningCandidateRouting { mesh, selectedOnly }

enum LlmProvider { openAiCompatible, appleFoundationModels }

enum ModelToolCallStyle { unknown, nativeToolCalls, embeddedToolTags, none }

enum ModelStructuredOutputSupport { unknown, jsonSchema, jsonObject, none }

enum ModelGoalUpdateFidelity { unknown, reliable, unreliable }

enum ModelEditFormatPreference {
  unknown,
  wholeFile,
  searchReplace,
  unifiedDiff,
}

/// LL39 vision axis. Caverno attaches images on two production paths — a user
/// attachment and a computer-use screenshot observation — so "cannot read the
/// image" is a real capability gap, and the way it fails matters: an endpoint
/// that rejects image content parts needs a different response from a model
/// that accepts them and answers from the text alone.
enum ModelVisionSupport {
  unknown,

  /// The endpoint refused the request carrying image content.
  rejected,

  /// The request succeeded, but a no-image control arm scored the same, so the
  /// image did not inform the answer.
  ignored,

  /// Read a plain user attachment, but not the computer-use observation shape.
  basic,

  /// Read both production shapes.
  reliable,
}

extension ReasoningEffortPreferenceApi on ReasoningEffortPreference {
  String? get apiValue => switch (this) {
    ReasoningEffortPreference.automatic => null,
    ReasoningEffortPreference.low => 'low',
    ReasoningEffortPreference.medium => 'medium',
    ReasoningEffortPreference.high => 'high',
  };
}

@freezed
abstract class LocalCommandPermissionRule with _$LocalCommandPermissionRule {
  const LocalCommandPermissionRule._();

  const factory LocalCommandPermissionRule({
    required String id,
    @Default(true) bool enabled,
    @JsonKey(unknownEnumValue: LocalCommandPermissionAction.ask)
    @Default(LocalCommandPermissionAction.ask)
    LocalCommandPermissionAction action,
    @JsonKey(unknownEnumValue: LocalCommandPermissionMatch.exact)
    @Default(LocalCommandPermissionMatch.exact)
    LocalCommandPermissionMatch match,
    @Default('') String pattern,
    @Default('') String workingDirectory,
    DateTime? createdAt,
  }) = _LocalCommandPermissionRule;

  factory LocalCommandPermissionRule.fromJson(Map<String, dynamic> json) =>
      _$LocalCommandPermissionRuleFromJson(json);

  String get normalizedPattern => pattern.trim();

  String get normalizedWorkingDirectory => workingDirectory.trim();

  bool get isUsable => enabled && normalizedPattern.isNotEmpty;
}

@freezed
abstract class RoutineComputerUseActionAllowlistEntry
    with _$RoutineComputerUseActionAllowlistEntry {
  const RoutineComputerUseActionAllowlistEntry._();

  const factory RoutineComputerUseActionAllowlistEntry({
    required String id,
    @Default(true) bool enabled,
    @Default('') String label,
    @Default('') String toolName,
    @Default('') String targetLabelContains,
    @Default('') String targetRole,
    @Default('') String targetAction,
    @Default('') String targetRisk,
    @Default('') String appNameContains,
    @Default('') String appBundleId,
    @Default('') String windowTitleContains,
    @Default('') String urlHost,
    @Default('') String urlStartsWith,
    @Default('') String exactText,
  }) = _RoutineComputerUseActionAllowlistEntry;

  factory RoutineComputerUseActionAllowlistEntry.fromJson(
    Map<String, dynamic> json,
  ) => _$RoutineComputerUseActionAllowlistEntryFromJson(json);

  String get normalizedToolName => toolName.trim();

  String get normalizedLabel => label.trim();

  bool get hasBoundary {
    return targetLabelContains.trim().isNotEmpty ||
        targetRole.trim().isNotEmpty ||
        targetAction.trim().isNotEmpty ||
        targetRisk.trim().isNotEmpty ||
        appNameContains.trim().isNotEmpty ||
        appBundleId.trim().isNotEmpty ||
        windowTitleContains.trim().isNotEmpty ||
        urlHost.trim().isNotEmpty ||
        urlStartsWith.trim().isNotEmpty ||
        exactText.isNotEmpty;
  }
}

@freezed
abstract class McpServerConfig with _$McpServerConfig {
  const McpServerConfig._();

  const factory McpServerConfig({
    @Default('') String url,
    @Default(true) bool enabled,
    @JsonKey(unknownEnumValue: McpServerType.http)
    @Default(McpServerType.http)
    McpServerType type,
    @JsonKey(unknownEnumValue: McpServerTrustState.trusted)
    @Default(McpServerTrustState.trusted)
    McpServerTrustState trustState,
    @Default('') String command,
    @Default(<String>[]) List<String> args,
    @Default(<String, String>{}) Map<String, String> env,
    @Default('') String sourceId,
    DateTime? trustedAt,
  }) = _McpServerConfig;

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      _$McpServerConfigFromJson(json);

  String get normalizedUrl => url.trim();

  String get normalizedCommand => command.trim();

  Map<String, String> get normalizedEnv {
    final entries =
        env.entries
            .map((entry) => MapEntry(entry.key.trim(), entry.value.trim()))
            .where((entry) => entry.key.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.fromEntries(entries);
  }

  /// Whether this server configuration has enough data to attempt a connection.
  bool get isValid => switch (type) {
    McpServerType.http => normalizedUrl.isNotEmpty,
    McpServerType.stdio => normalizedCommand.isNotEmpty,
  };

  /// Human-readable label for display and logging.
  String get displayLabel => switch (type) {
    McpServerType.http => normalizedUrl,
    McpServerType.stdio =>
      args.isEmpty ? normalizedCommand : '$normalizedCommand ${args.join(' ')}',
  };

  String get trustSourceLabel => switch (type) {
    McpServerType.http => 'Remote MCP endpoint',
    McpServerType.stdio => 'Local stdio command',
  };

  String get trustIdentity => switch (type) {
    McpServerType.http => 'http:${normalizedUrl.toLowerCase()}',
    McpServerType.stdio =>
      'stdio:${normalizedCommand.toLowerCase()}::${args.join('\u{1f}')}::'
          '${normalizedEnv.entries.map((e) => '${e.key}=${e.value}').join('\u{1f}')}',
  };

  bool get isTrusted => trustState == McpServerTrustState.trusted;

  bool get isBlocked => trustState == McpServerTrustState.blocked;

  bool get needsTrustReview => trustState == McpServerTrustState.pending;

  bool get exposesToolsToModel => enabled && isValid && isTrusted;
}

@freezed
abstract class ExternalToolHook with _$ExternalToolHook {
  const ExternalToolHook._();

  const factory ExternalToolHook({
    required String id,
    @Default(true) bool enabled,
    @Default('') String event,
    @Default('') String command,
    @Default(<String>[]) List<String> args,
    @Default(<String, String>{}) Map<String, String> env,
    @Default('') String sourceId,
  }) = _ExternalToolHook;

  factory ExternalToolHook.fromJson(Map<String, dynamic> json) =>
      _$ExternalToolHookFromJson(json);

  String get normalizedEvent => event.trim();

  String get normalizedCommand => command.trim();

  Map<String, String> get normalizedEnv {
    final entries =
        env.entries
            .map((entry) => MapEntry(entry.key.trim(), entry.value.trim()))
            .where((entry) => entry.key.isNotEmpty)
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.fromEntries(entries);
  }

  bool get isUsable =>
      enabled && normalizedEvent.isNotEmpty && normalizedCommand.isNotEmpty;

  String get identity =>
      '${normalizedEvent.toLowerCase()}::$normalizedCommand::'
      '${args.join('\u{1f}')}::'
      '${normalizedEnv.entries.map((e) => '${e.key}=${e.value}').join('\u{1f}')}';

  ExternalToolHook normalizedForPersistence() => copyWith(
    id: id.trim(),
    event: normalizedEvent,
    command: normalizedCommand,
    env: normalizedEnv,
    sourceId: sourceId.trim(),
  );
}

@freezed
abstract class ModelCapabilityProfile with _$ModelCapabilityProfile {
  const ModelCapabilityProfile._();

  const factory ModelCapabilityProfile({
    required String id,
    @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)
    @Default(LlmProvider.openAiCompatible)
    LlmProvider provider,
    @Default('') String baseUrl,
    required String model,
    @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)
    @Default(ModelToolCallStyle.unknown)
    ModelToolCallStyle toolCallStyle,
    @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)
    @Default(ModelStructuredOutputSupport.unknown)
    ModelStructuredOutputSupport structuredOutputSupport,
    @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)
    @Default(ModelGoalUpdateFidelity.unknown)
    ModelGoalUpdateFidelity goalUpdateFidelity,
    @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)
    @Default(ModelEditFormatPreference.unknown)
    ModelEditFormatPreference editFormatPreference,
    @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)
    @Default(ModelVisionSupport.unknown)
    ModelVisionSupport visionSupport,
    @Default(0) int usableContextTokens,
    DateTime? probedAt,
    @Default('') String probeSummary,
    @Default(<String, String>{}) Map<String, String> probeMetadata,
  }) = _ModelCapabilityProfile;

  factory ModelCapabilityProfile.fromJson(Map<String, dynamic> json) =>
      _$ModelCapabilityProfileFromJson(json);

  static String buildId({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    final endpoint = provider == LlmProvider.appleFoundationModels
        ? 'apple-foundation-models://local'
        : baseUrl.trim().toLowerCase();
    return '${provider.name}|$endpoint|${model.trim()}';
  }

  String get normalizedBaseUrl => baseUrl.trim();

  String get normalizedModel => model.trim();

  String get computedId => buildId(
    provider: provider,
    baseUrl: normalizedBaseUrl,
    model: normalizedModel,
  );

  ModelCapabilityProfile normalizedForPersistence() {
    return copyWith(
      id: computedId,
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      usableContextTokens: usableContextTokens < 0 ? 0 : usableContextTokens,
      probeSummary: probeSummary.trim(),
      probeMetadata: Map<String, String>.from(probeMetadata),
    );
  }

  bool matches({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    final targetId = buildId(
      provider: provider,
      baseUrl: baseUrl,
      model: model,
    );
    return id == targetId || computedId == targetId;
  }
}

List<ModelCapabilityProfile> _modelCapabilityProfilesFromJson(
  List<dynamic>? json,
) {
  if (json == null) {
    return const <ModelCapabilityProfile>[];
  }
  return json
      .whereType<Map>()
      .map(
        (item) => ModelCapabilityProfile.fromJson(
          Map<String, dynamic>.from(item),
        ).normalizedForPersistence(),
      )
      .where((profile) => profile.normalizedModel.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _modelCapabilityProfilesToJson(
  List<ModelCapabilityProfile> profiles,
) {
  return profiles
      .map((profile) => profile.normalizedForPersistence().toJson())
      .toList(growable: false);
}

/// LL23: a declared, per-model harness configuration.
///
/// This is the closed allow-list of harness surfaces the LL17 self-improving
/// loop is permitted to mutate. The schema is intentionally small and
/// behaviour-preserving by default: every field has a safe default that means
/// "use the built-in harness behaviour", so a model with no stored config
/// behaves exactly as it does today. Unknown JSON keys are dropped on parse,
/// keeping the persisted surface closed.
@freezed
abstract class ModelHarnessConfig with _$ModelHarnessConfig {
  const ModelHarnessConfig._();

  /// Defensive ceiling on the configurable tool-loop cap so a stored or
  /// proposed value can never trigger a runaway loop.
  static const int maxToolLoopIterations = 100;

  const factory ModelHarnessConfig({
    required String id,
    @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)
    @Default(LlmProvider.openAiCompatible)
    LlmProvider provider,
    @Default('') String baseUrl,
    required String model,
    // Instruction surfaces. An empty string falls back to the built-in
    // SystemPromptBuilder guidance for that surface.
    @Default('') String bootstrapInstruction,
    @Default('') String executionInstruction,
    @Default('') String verificationInstruction,
    @Default('') String failureRecoveryInstruction,
    // Runtime control policy. Zero / false means "use the existing harness
    // default" so the config never silently weakens current behaviour.
    @Default(0) int toolLoopMaxIterations,
    @Default(false) bool recoveryMiddlewareEnabled,
    @Default(false) bool explorationToEditNudgeEnabled,
    @Default(false) bool summaryFirstToolResultsEnabled,
    @JsonKey(unknownEnumValue: GoalCompletionPolicy.toolOrAsk)
    @Default(GoalCompletionPolicy.toolOrAsk)
    GoalCompletionPolicy goalCompletionPolicy,
  }) = _ModelHarnessConfig;

  factory ModelHarnessConfig.fromJson(Map<String, dynamic> json) =>
      _$ModelHarnessConfigFromJson(json);

  /// Shares the LL3 profile keying scheme so a model resolves to one
  /// capability profile and one harness config under the same id.
  static String buildId({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    return ModelCapabilityProfile.buildId(
      provider: provider,
      baseUrl: baseUrl,
      model: model,
    );
  }

  String get normalizedBaseUrl => baseUrl.trim();

  String get normalizedModel => model.trim();

  String get computedId => buildId(
    provider: provider,
    baseUrl: normalizedBaseUrl,
    model: normalizedModel,
  );

  bool get hasInstructionOverrides =>
      bootstrapInstruction.trim().isNotEmpty ||
      executionInstruction.trim().isNotEmpty ||
      verificationInstruction.trim().isNotEmpty ||
      failureRecoveryInstruction.trim().isNotEmpty;

  bool get hasControlPolicyOverrides =>
      toolLoopMaxIterations > 0 ||
      recoveryMiddlewareEnabled ||
      explorationToEditNudgeEnabled ||
      summaryFirstToolResultsEnabled ||
      goalCompletionPolicy != GoalCompletionPolicy.toolOrAsk;

  /// True when the config carries no overrides, i.e. it is equivalent to having
  /// no stored config at all.
  bool get isEmpty => !hasInstructionOverrides && !hasControlPolicyOverrides;

  ModelHarnessConfig normalizedForPersistence() {
    return copyWith(
      id: computedId,
      baseUrl: normalizedBaseUrl,
      model: normalizedModel,
      bootstrapInstruction: bootstrapInstruction.trim(),
      executionInstruction: executionInstruction.trim(),
      verificationInstruction: verificationInstruction.trim(),
      failureRecoveryInstruction: failureRecoveryInstruction.trim(),
      toolLoopMaxIterations: toolLoopMaxIterations < 0
          ? 0
          : toolLoopMaxIterations,
    );
  }

  /// Resolves the tool-loop iteration cap for this model, falling back to
  /// [fallback] when no override is configured. Clamped to
  /// [maxToolLoopIterations] so a stored value can never exceed the ceiling.
  int resolveToolLoopMaxIterations(int fallback) {
    if (toolLoopMaxIterations <= 0) {
      return fallback;
    }
    return toolLoopMaxIterations > maxToolLoopIterations
        ? maxToolLoopIterations
        : toolLoopMaxIterations;
  }

  bool matches({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    final targetId = buildId(
      provider: provider,
      baseUrl: baseUrl,
      model: model,
    );
    return id == targetId || computedId == targetId;
  }
}

List<ModelHarnessConfig> _modelHarnessConfigsFromJson(List<dynamic>? json) {
  if (json == null) {
    return const <ModelHarnessConfig>[];
  }
  return json
      .whereType<Map>()
      .map(
        (item) => ModelHarnessConfig.fromJson(
          Map<String, dynamic>.from(item),
        ).normalizedForPersistence(),
      )
      .where((config) => config.normalizedModel.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _modelHarnessConfigsToJson(
  List<ModelHarnessConfig> configs,
) {
  return configs
      .map((config) => config.normalizedForPersistence().toJson())
      .toList(growable: false);
}

/// LL21: a lightweight snapshot of a [ModelCapabilityProfile] at a point in
/// time.
///
/// Appended to [AppSettings.modelCapabilityProfileRevisions] on every
/// [SettingsNotifier.upsertModelCapabilityProfile] call, capped at
/// [ModelCapabilityProfileRevision.maxPerProfile] entries per profile id. Used
/// to track capability drift across idle re-probes and detect GGUF/model-weight
/// swaps behind a stable model id.
@freezed
abstract class ModelCapabilityProfileRevision
    with _$ModelCapabilityProfileRevision {
  const ModelCapabilityProfileRevision._();

  const factory ModelCapabilityProfileRevision({
    required String profileId,
    required DateTime probedAt,
    @JsonKey(unknownEnumValue: ModelToolCallStyle.unknown)
    required ModelToolCallStyle toolCallStyle,
    @JsonKey(unknownEnumValue: ModelStructuredOutputSupport.unknown)
    required ModelStructuredOutputSupport structuredOutputSupport,
    @JsonKey(unknownEnumValue: ModelGoalUpdateFidelity.unknown)
    @Default(ModelGoalUpdateFidelity.unknown)
    ModelGoalUpdateFidelity goalUpdateFidelity,
    @JsonKey(unknownEnumValue: ModelEditFormatPreference.unknown)
    required ModelEditFormatPreference editFormatPreference,
    @JsonKey(unknownEnumValue: ModelVisionSupport.unknown)
    @Default(ModelVisionSupport.unknown)
    ModelVisionSupport visionSupport,
    required int usableContextTokens,
    @Default('') String probeSummary,

    /// LL39 bounded conformance score for this revision, and the suite that
    /// produced it. Null means the revision predates the benchmark or came from
    /// a path that does not score (a settings import, a bounded re-probe with
    /// no scored probes) — which is not the same as scoring zero, so a missing
    /// value must never read as a regression.
    ///
    /// Kept on the revision, not only on the profile: the profile is
    /// overwritten by every run, so without this the score has no history and
    /// nothing can be compared.
    int? benchmarkPoints,
    int? benchmarkAttemptedPoints,
    int? benchmarkMaxPoints,

    /// Suite identity, e.g. `cavernobench-v2`. Two suite versions are not
    /// comparable, so history is partitioned by this before any delta.
    @Default('') String benchmarkSuite,

    /// True when this revision's score dropped by more than the spread measured
    /// across earlier same-suite revisions. Separate from
    /// [capabilityChangeDetected] because the diagnosis differs: an enum flip
    /// says a capability appeared or vanished, while this says every capability
    /// still reports the same but the model got measurably worse.
    @Default(false) bool benchmarkRegressionDetected,

    /// How this revision was triggered. Known values: 'initial', 'idle_re_probe',
    /// 'calibrate', 'manual', 'probe'.
    @Default('probe') String source,

    /// True when any key capability field changed vs the immediately preceding
    /// revision for the same [profileId] — a heuristic for GGUF/weight swaps.
    @Default(false) bool capabilityChangeDetected,
  }) = _ModelCapabilityProfileRevision;

  factory ModelCapabilityProfileRevision.fromJson(Map<String, dynamic> json) =>
      _$ModelCapabilityProfileRevisionFromJson(json);

  factory ModelCapabilityProfileRevision.fromProfile(
    ModelCapabilityProfile profile, {
    String source = 'probe',
    bool capabilityChangeDetected = false,
    bool benchmarkRegressionDetected = false,
  }) => ModelCapabilityProfileRevision(
    profileId: profile.computedId,
    probedAt: profile.probedAt ?? DateTime.now(),
    toolCallStyle: profile.toolCallStyle,
    structuredOutputSupport: profile.structuredOutputSupport,
    goalUpdateFidelity: profile.goalUpdateFidelity,
    editFormatPreference: profile.editFormatPreference,
    visionSupport: profile.visionSupport,
    usableContextTokens: profile.usableContextTokens,
    probeSummary: profile.probeSummary,
    benchmarkPoints: _metadataInt(profile, 'benchmarkPoints'),
    benchmarkAttemptedPoints: _metadataInt(profile, 'benchmarkAttemptedPoints'),
    benchmarkMaxPoints: _metadataInt(profile, 'benchmarkMaxPoints'),
    benchmarkSuite: profile.probeMetadata['benchmarkSuite'] ?? '',
    source: source,
    capabilityChangeDetected: capabilityChangeDetected,
    benchmarkRegressionDetected: benchmarkRegressionDetected,
  );

  /// The builder writes the score into `probeMetadata`, which is the profile's
  /// existing output contract. Absent or unparseable stays null rather than
  /// becoming zero.
  static int? _metadataInt(ModelCapabilityProfile profile, String key) {
    final raw = profile.probeMetadata[key];
    if (raw == null) {
      return null;
    }
    return int.tryParse(raw.trim());
  }

  bool get hasBenchmarkScore => benchmarkPoints != null;

  /// Maximum revisions stored per profile id; oldest are dropped on overflow.
  static const maxPerProfile = 10;
}

List<ModelCapabilityProfileRevision> _profileRevisionsFromJson(
  List<dynamic>? json,
) {
  if (json == null) {
    return const <ModelCapabilityProfileRevision>[];
  }
  return json
      .whereType<Map>()
      .map(
        (item) => ModelCapabilityProfileRevision.fromJson(
          Map<String, dynamic>.from(item),
        ),
      )
      .where((r) => r.profileId.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _profileRevisionsToJson(
  List<ModelCapabilityProfileRevision> revisions,
) => revisions.map((r) => r.toJson()).toList(growable: false);

enum LlmEndpointSource { manual, discovered }

/// A saved OpenAI-compatible endpoint available for primary and role routing.
@freezed
abstract class LlmEndpoint with _$LlmEndpoint {
  const LlmEndpoint._();

  const factory LlmEndpoint({
    required String id,
    @Default('') String label,
    @Default('') String baseUrl,
    @Default('') String apiKey,
    @Default('') String model,
    @Default(true) bool enabled,
    @JsonKey(unknownEnumValue: LlmEndpointSource.manual)
    @Default(LlmEndpointSource.manual)
    LlmEndpointSource source,
    DateTime? createdAt,
  }) = _LlmEndpoint;

  factory LlmEndpoint.fromJson(Map<String, dynamic> json) =>
      _$LlmEndpointFromJson(json);

  static String normalizeBaseUrl(String baseUrl) =>
      baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  String get normalizedId => id.trim();

  String get normalizedBaseUrl => normalizeBaseUrl(baseUrl);

  String get normalizedLabel => label.trim();

  String get normalizedModel => model.trim();

  /// Human-readable name for lists, falling back to the base URL.
  String get displayLabel =>
      normalizedLabel.isEmpty ? normalizedBaseUrl : normalizedLabel;

  bool get isValid => normalizedBaseUrl.isNotEmpty;

  LlmEndpoint normalizedForPersistence() => copyWith(
    id: normalizedId,
    label: normalizedLabel,
    baseUrl: normalizedBaseUrl,
    apiKey: apiKey.trim(),
    model: normalizedModel,
  );
}

List<LlmEndpoint> _llmEndpointsFromJson(List<dynamic>? json) {
  if (json == null) {
    return const <LlmEndpoint>[];
  }
  return json
      .whereType<Map>()
      .map(
        (item) => LlmEndpoint.fromJson(
          Map<String, dynamic>.from(item),
        ).normalizedForPersistence(),
      )
      .where((profile) => profile.isValid)
      .toList(growable: false);
}

List<Map<String, dynamic>> _llmEndpointsToJson(List<LlmEndpoint> profiles) =>
    profiles
        .map((profile) => profile.normalizedForPersistence().toJson())
        .toList(growable: false);

List<ExternalToolHook> _externalToolHooksFromJson(List<dynamic>? json) {
  if (json == null) {
    return const <ExternalToolHook>[];
  }
  return json
      .whereType<Map>()
      .map(
        (item) => ExternalToolHook.fromJson(
          Map<String, dynamic>.from(item),
        ).normalizedForPersistence(),
      )
      .where((hook) => hook.id.trim().isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _externalToolHooksToJson(
  List<ExternalToolHook> hooks,
) => hooks
    .map((hook) => hook.normalizedForPersistence().toJson())
    .toList(growable: false);

@freezed
abstract class AppSettings with _$AppSettings {
  const AppSettings._();

  const factory AppSettings({
    @JsonKey(unknownEnumValue: LlmProvider.openAiCompatible)
    @Default(LlmProvider.openAiCompatible)
    LlmProvider llmProvider,
    required String baseUrl,
    required String model,
    required String apiKey,
    // Saved primary endpoints the user can switch between. The entry whose id
    // is [activeLlmEndpointId] mirrors [baseUrl] / [apiKey] / [model]; the rest
    // are inactive presets. Kept in sync by
    // [AppSettings.withNormalizedLlmEndpoints].
    @JsonKey(fromJson: _llmEndpointsFromJson, toJson: _llmEndpointsToJson)
    @Default(<LlmEndpoint>[])
    List<LlmEndpoint> llmEndpoints,
    @Default('') String activeLlmEndpointId,
    required double temperature,
    required int maxTokens,
    @JsonKey(unknownEnumValue: ReasoningEffortPreference.automatic)
    @Default(ReasoningEffortPreference.automatic)
    ReasoningEffortPreference reasoningEffort,
    @Default(false) bool proReasoningEnabled,
    @JsonKey(unknownEnumValue: ProReasoningDepth.deep)
    @Default(ProReasoningDepth.deep)
    ProReasoningDepth proReasoningDepth,
    @JsonKey(unknownEnumValue: ProReasoningCandidateRouting.mesh)
    @Default(ProReasoningCandidateRouting.mesh)
    ProReasoningCandidateRouting proReasoningCandidateRouting,
    // LL24 primary-turn routing. Empty strings preserve the active primary
    // model and endpoint. These are deliberately separate from LL1 secondary
    // roles such as plan drafting and memory extraction.
    @Default('') String generalPrimaryModel,
    @Default('') String codingPrimaryModel,
    @Default('') String planPrimaryModel,
    @Default('') String generalPrimaryEndpointId,
    @Default('') String codingPrimaryEndpointId,
    @Default('') String planPrimaryEndpointId,
    // Per-role model routing (LL1). Empty string means "use the main model".
    // Lets secondary LLM calls run on a smaller, faster local model.
    @Default('') String memoryExtractionModel,
    @Default('') String subagentModel,
    @Default('') String goalSuggestionModel,
    @Default('') String approvalAutoReviewModel,
    // Plan drafting (workflow + task proposals) in a planning session. Unlike
    // the other roles this usually wants a stronger model than the main one,
    // since the plan shapes the whole execution run.
    @Default('') String planningModel,
    // Pro Reasoning coordinates multiple deliberation stages, so it can use a
    // dedicated model independently from ordinary chat and plan drafting.
    @Default('') String proReasoningModel,
    // LL8 per-role endpoint routing. Empty string means "use the primary
    // endpoint". A non-empty value is a LlmEndpoint id; an unreachable mesh
    // endpoint falls back to the primary at call time (MeshEndpointRouter).
    @Default('') String memoryExtractionEndpointId,
    @Default('') String subagentEndpointId,
    @Default('') String goalSuggestionEndpointId,
    @Default('') String approvalAutoReviewEndpointId,
    @Default('') String planningEndpointId,
    @Default('') String proReasoningEndpointId,
    @Default('') String googleChatWebhookUrl,
    @Default('') String mcpUrl,
    @Default(<String>[]) List<String> mcpUrls,
    @Default(<McpServerConfig>[]) List<McpServerConfig> mcpServers,
    @Default(false) bool mcpEnabled,
    @Default(false) bool externalSettingsSyncEnabled,
    @Default('~/.caverno/config.json') String externalSettingsPath,
    @Default(false) bool externalToolHooksEnabled,
    @JsonKey(
      fromJson: _externalToolHooksFromJson,
      toJson: _externalToolHooksToJson,
    )
    @Default(<ExternalToolHook>[])
    List<ExternalToolHook> externalToolHooks,
    // Voice settings
    @Default(true) bool ttsEnabled,
    @Default(false) bool autoReadEnabled,
    @Default(0.5) double speechRate,
    // Voice mode (Whisper + VOICEVOX)
    @Default(true) bool voiceModeAutoStop,
    @Default('http://localhost:8080') String whisperUrl,
    @Default('http://localhost:50021') String voicevoxUrl,
    @Default(0) int voicevoxSpeakerId,
    @Default('system') String language,
    @JsonKey(unknownEnumValue: AssistantMode.general)
    @Default(AssistantMode.general)
    AssistantMode assistantMode,
    @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)
    @Default(ToolApprovalMode.defaultPermissions)
    ToolApprovalMode codingApprovalMode,
    // Approval policy for chat-mode built-in browser automation. Reuses the
    // shared [ToolApprovalMode] levels but is independent from coding writes.
    @JsonKey(unknownEnumValue: ToolApprovalMode.defaultPermissions)
    @Default(ToolApprovalMode.defaultPermissions)
    ToolApprovalMode chatApprovalMode,
    @Default(true) bool confirmFileMutations,
    @Default(true) bool confirmLocalCommands,
    @Default(true) bool confirmGitWrites,
    @Default(true) bool enableCodingVerificationFeedback,
    @JsonKey(
      unknownEnumValue: CodingVerificationTriggerPolicy.onCompletionClaim,
    )
    @Default(CodingVerificationTriggerPolicy.onCompletionClaim)
    CodingVerificationTriggerPolicy codingVerificationTriggerPolicy,
    @Default(90) int codingVerificationTimeoutSeconds,
    @Default(5) int codingVerificationMaxFailures,
    @Default(true) bool enableAgentsMd,
    @Default(false) bool enablePrefixStableToolLoop,
    // LL5: opt-in local semantic search. When enabled and an embeddings model
    // is configured, conversation history is embedded for semantic search;
    // otherwise search degrades to lexical FTS.
    @Default(false) bool enableSemanticSearch,
    @Default('') String embeddingsModel,
    @Default(false) bool showMemoryUpdates,
    @Default(true) bool enableLlmSessionLogs,
    @Default(true) bool feedbackUploadEnabled,
    @Default(defaultFeedbackEndpointUrl) String feedbackEndpointUrl,
    @Default('') String feedbackEndpointAuthToken,
    @Default(false) bool demoMode,
    @Default(false) bool onboardingCompleted,
    @Default(false) bool browserToolsEnabled,
    @Default(<String>[]) List<String> disabledBuiltInTools,
    @Default(<LocalCommandPermissionRule>[])
    List<LocalCommandPermissionRule> localCommandPermissionRules,
    @Default(<RoutineComputerUseActionAllowlistEntry>[])
    List<RoutineComputerUseActionAllowlistEntry>
    routineComputerUseActionAllowlist,
    @JsonKey(
      fromJson: _modelCapabilityProfilesFromJson,
      toJson: _modelCapabilityProfilesToJson,
    )
    @Default(<ModelCapabilityProfile>[])
    List<ModelCapabilityProfile> modelCapabilityProfiles,
    @JsonKey(
      fromJson: _modelHarnessConfigsFromJson,
      toJson: _modelHarnessConfigsToJson,
    )
    @Default(<ModelHarnessConfig>[])
    List<ModelHarnessConfig> modelHarnessConfigs,
    @JsonKey(
      fromJson: _profileRevisionsFromJson,
      toJson: _profileRevisionsToJson,
    )
    @Default(<ModelCapabilityProfileRevision>[])
    List<ModelCapabilityProfileRevision> modelCapabilityProfileRevisions,
    // LL18 idle/overnight maintenance gating (consumed via the maintenance
    // feature's IdleMaintenanceConfig; minutes are since local midnight).
    @Default(false) bool idleMaintenanceEnabled,
    @Default(120) int idleMaintenanceWindowStartMinutes,
    @Default(360) int idleMaintenanceWindowEndMinutes,
    @Default(10) int idleMaintenanceMinIdleMinutes,
    @Default(true) bool idleMaintenanceRequireAcPower,
  }) = _AppSettings;

  factory AppSettings.defaults() => const AppSettings(
    baseUrl: ApiConstants.defaultBaseUrl,
    model: ApiConstants.defaultModel,
    apiKey: ApiConstants.defaultApiKey,
    temperature: ApiConstants.defaultTemperature,
    maxTokens: ApiConstants.defaultMaxTokens,
    mcpUrl: 'http://localhost:8081',
    mcpUrls: ['http://localhost:8081'],
    mcpServers: [McpServerConfig(url: 'http://localhost:8081', enabled: true)],
    mcpEnabled: true,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(migrateLegacyJson(json));

  static const int minCodingVerificationTimeoutSeconds = 10;
  static const int maxCodingVerificationTimeoutSeconds = 300;
  static const int defaultCodingVerificationTimeoutSeconds = 90;
  static const int minCodingVerificationMaxFailures = 1;
  static const int maxCodingVerificationMaxFailures = 20;
  static const int defaultCodingVerificationMaxFailures = 5;
  static const String defaultExternalSettingsPath = '~/.caverno/config.json';
  static const String appleFoundationModelsModelId =
      ApiConstants.appleFoundationModelsModelId;

  String get effectiveModel => llmProvider == LlmProvider.appleFoundationModels
      ? appleFoundationModelsModelId
      : model;

  /// Id given to the endpoint profile seeded from a pre-multi-endpoint install.
  static const String seededLlmEndpointId = 'primary';

  /// Saved endpoint profiles that are usable, in registration order.
  List<LlmEndpoint> get usableLlmEndpoints => llmEndpoints
      .map((profile) => profile.normalizedForPersistence())
      .where((profile) => profile.isValid)
      .toList(growable: false);

  /// The profile currently driving [baseUrl] / [apiKey] / [model], or null when
  /// no profile is registered.
  LlmEndpoint? get activeLlmEndpoint {
    final profiles = usableLlmEndpoints;
    if (profiles.isEmpty) return null;
    final targetId = activeLlmEndpointId.trim();
    for (final profile in profiles) {
      if (profile.id == targetId) return profile;
    }
    return profiles.first;
  }

  /// Reconciles the saved endpoint list with the primary connection fields.
  ///
  /// - Seeds a single profile from [baseUrl] / [apiKey] / [model] when the list
  ///   is empty, so installs that predate multi-endpoint support keep their
  ///   configured endpoint as the first entry.
  /// - Repoints [activeLlmEndpointId] at a real entry when it dangles.
  /// - Mirrors the primary fields into the active entry, so direct writes to
  ///   [baseUrl] / [apiKey] / [model] (settings edits, QR import, external
  ///   config sync) never leave the list showing stale values.
  AppSettings withNormalizedLlmEndpoints() {
    final trimmedBaseUrl = LlmEndpoint.normalizeBaseUrl(baseUrl);
    final profiles = usableLlmEndpoints;

    if (profiles.isEmpty) {
      if (trimmedBaseUrl.isEmpty) return this;
      return copyWith(
        llmEndpoints: [
          LlmEndpoint(
            id: seededLlmEndpointId,
            baseUrl: trimmedBaseUrl,
            apiKey: apiKey.trim(),
            model: model.trim(),
          ),
        ],
        activeLlmEndpointId: seededLlmEndpointId,
      );
    }

    final activeId = profiles.any((p) => p.id == activeLlmEndpointId.trim())
        ? activeLlmEndpointId.trim()
        : profiles.first.id;
    final synced = [
      for (final profile in profiles)
        if (profile.id == activeId)
          profile.copyWith(
            baseUrl: trimmedBaseUrl.isEmpty ? profile.baseUrl : trimmedBaseUrl,
            apiKey: apiKey.trim(),
            model: model.trim(),
          )
        else
          profile,
    ];
    return copyWith(llmEndpoints: synced, activeLlmEndpointId: activeId);
  }

  String get effectiveMemoryExtractionModel =>
      _resolveRoleModel(memoryExtractionModel, memoryExtractionEndpointId);

  String get effectiveSubagentModel =>
      _resolveRoleModel(subagentModel, subagentEndpointId);

  String get effectiveGoalSuggestionModel =>
      _resolveRoleModel(goalSuggestionModel, goalSuggestionEndpointId);

  String get effectiveApprovalAutoReviewModel =>
      _resolveRoleModel(approvalAutoReviewModel, approvalAutoReviewEndpointId);

  String get effectivePlanningModel =>
      _resolveRoleModel(planningModel, planningEndpointId);

  String get effectiveProReasoningModel =>
      _resolveRoleModel(proReasoningModel, proReasoningEndpointId);

  String primaryModelOverrideFor(AssistantMode mode) => switch (mode) {
    AssistantMode.general => generalPrimaryModel,
    AssistantMode.coding => codingPrimaryModel,
    AssistantMode.plan => planPrimaryModel,
  };

  String primaryEndpointIdFor(AssistantMode mode) => switch (mode) {
    AssistantMode.general => generalPrimaryEndpointId,
    AssistantMode.coding => codingPrimaryEndpointId,
    AssistantMode.plan => planPrimaryEndpointId,
  };

  String effectivePrimaryModelFor(AssistantMode mode) => _resolveRoleModel(
    primaryModelOverrideFor(mode),
    primaryEndpointIdFor(mode),
  );

  String get normalizedFeedbackEndpointUrl => feedbackEndpointUrl.trim();

  String get normalizedFeedbackEndpointAuthToken =>
      feedbackEndpointAuthToken.trim();

  bool get isFeedbackUploadConfigured =>
      feedbackUploadEnabled && normalizedFeedbackEndpointUrl.isNotEmpty;

  ModelCapabilityProfile? get effectiveModelCapabilityProfile {
    return modelCapabilityProfileFor(
      provider: llmProvider,
      baseUrl: baseUrl,
      model: effectiveModel,
    );
  }

  ModelCapabilityProfile? modelCapabilityProfileFor({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    for (final profile in modelCapabilityProfiles.reversed) {
      if (profile.matches(provider: provider, baseUrl: baseUrl, model: model)) {
        return profile.normalizedForPersistence();
      }
    }
    return null;
  }

  /// LL23: the harness config for the active model, or null when none is
  /// stored. A null result means "use the built-in harness behaviour".
  ModelHarnessConfig? get effectiveModelHarnessConfig {
    return modelHarnessConfigFor(
      provider: llmProvider,
      baseUrl: baseUrl,
      model: effectiveModel,
    );
  }

  GoalCompletionPolicy get effectiveGoalCompletionPolicy =>
      effectiveModelHarnessConfig?.goalCompletionPolicy ??
      GoalCompletionPolicy.toolOrAsk;

  ModelHarnessConfig? modelHarnessConfigFor({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    for (final config in modelHarnessConfigs.reversed) {
      if (config.matches(provider: provider, baseUrl: baseUrl, model: model)) {
        return config.normalizedForPersistence();
      }
    }
    return null;
  }

  /// LL21: stored profile revisions for the active model, newest first.
  List<ModelCapabilityProfileRevision> get effectiveModelProfileRevisions =>
      capabilityProfileRevisionsFor(
        provider: llmProvider,
        baseUrl: baseUrl,
        model: effectiveModel,
      );

  /// Returns stored profile revisions for the given model/endpoint, newest
  /// first (most recent re-probe at index 0).
  List<ModelCapabilityProfileRevision> capabilityProfileRevisionsFor({
    required LlmProvider provider,
    required String baseUrl,
    required String model,
  }) {
    final targetId = ModelCapabilityProfile.buildId(
      provider: provider,
      baseUrl: baseUrl,
      model: model,
    );
    final result = <ModelCapabilityProfileRevision>[];
    for (var i = modelCapabilityProfileRevisions.length - 1; i >= 0; i--) {
      if (modelCapabilityProfileRevisions[i].profileId == targetId) {
        result.add(modelCapabilityProfileRevisions[i]);
      }
    }
    return result;
  }

  /// Registered endpoints that are enabled and usable, in registration order.
  List<LlmEndpoint> get enabledLlmEndpoints => llmEndpoints
      .map((endpoint) => endpoint.normalizedForPersistence())
      .where((endpoint) => endpoint.enabled && endpoint.isValid)
      .toList(growable: false);

  /// Enabled endpoints other than the active primary endpoint.
  List<LlmEndpoint> get enabledAdditionalLlmEndpoints {
    final activeId = activeLlmEndpointId.trim();
    return enabledLlmEndpoints
        .where((endpoint) => endpoint.id != activeId)
        .toList(growable: false);
  }

  /// Looks up a registered endpoint by normalized base URL, or null.
  LlmEndpoint? llmEndpointForBaseUrl(String baseUrl) {
    final targetBaseUrl = LlmEndpoint.normalizeBaseUrl(baseUrl).toLowerCase();
    for (final endpoint in llmEndpoints.reversed) {
      if (endpoint.normalizedBaseUrl.toLowerCase() == targetBaseUrl) {
        return endpoint.normalizedForPersistence();
      }
    }
    return null;
  }

  /// Role models only apply to OpenAI-compatible endpoints; the Apple
  /// Foundation Models provider has a single on-device model.
  String _resolveRoleModel(String roleModel, String roleEndpointId) {
    if (llmProvider == LlmProvider.appleFoundationModels) {
      return effectiveModel;
    }
    final trimmed = roleModel.trim();
    if (trimmed.isNotEmpty) return trimmed;

    final endpointId = roleEndpointId.trim();
    if (endpointId.isNotEmpty) {
      for (final endpoint in enabledLlmEndpoints) {
        if (endpoint.id == endpointId && endpoint.normalizedModel.isNotEmpty) {
          return endpoint.normalizedModel;
        }
      }
    }
    return effectiveModel;
  }

  static Map<String, dynamic> migrateLegacyJson(Map<String, dynamic> json) {
    var migrated = _migrateApprovalMode(json);
    migrated = _migrateUnifiedEndpoints(migrated);
    migrated = _migrateProReasoningCandidateRouting(migrated);
    return migrated;
  }

  static Map<String, dynamic> _migrateProReasoningCandidateRouting(
    Map<String, dynamic> json,
  ) {
    if (json.containsKey('proReasoningCandidateRouting')) return json;
    final endpointId = json['proReasoningEndpointId']?.toString().trim() ?? '';
    if (endpointId.isEmpty) return json;
    return <String, dynamic>{
      ...json,
      'proReasoningCandidateRouting':
          ProReasoningCandidateRouting.selectedOnly.name,
    };
  }

  static Map<String, dynamic> _migrateApprovalMode(Map<String, dynamic> json) {
    if (json.containsKey('codingApprovalMode')) return json;
    final migrated = Map<String, dynamic>.from(json);
    final confirmFileMutations =
        migrated['confirmFileMutations'] as bool? ?? true;
    final confirmLocalCommands =
        migrated['confirmLocalCommands'] as bool? ?? true;
    final confirmGitWrites = migrated['confirmGitWrites'] as bool? ?? true;
    migrated['codingApprovalMode'] =
        !confirmFileMutations && !confirmLocalCommands && !confirmGitWrites
        ? 'fullAccess'
        : 'defaultPermissions';
    return migrated;
  }

  static Map<String, dynamic> _migrateUnifiedEndpoints(
    Map<String, dynamic> json,
  ) {
    if (json.containsKey('llmEndpoints')) return json;

    final hasLegacyEndpoints =
        json.containsKey('llmEndpointProfiles') ||
        json.containsKey('namedEndpoints');
    if (!hasLegacyEndpoints) return json;

    final migrated = Map<String, dynamic>.from(json);
    final endpoints = <Map<String, dynamic>>[];
    final normalizedBaseUrlToIndex = <String, int>{};
    final namedIdMapping = <String, String>{};

    final legacyProfiles = json['llmEndpointProfiles'];
    if (legacyProfiles is List) {
      for (final item in legacyProfiles.whereType<Map>()) {
        final profile = Map<String, dynamic>.from(item);
        final endpoint = <String, dynamic>{
          ...profile,
          'enabled': true,
          'source': 'manual',
        };
        endpoints.add(endpoint);
        final normalizedBaseUrl = LlmEndpoint.normalizeBaseUrl(
          profile['baseUrl']?.toString() ?? '',
        ).toLowerCase();
        if (normalizedBaseUrl.isNotEmpty) {
          normalizedBaseUrlToIndex[normalizedBaseUrl] = endpoints.length - 1;
        }
      }
    }

    final legacyNamedEndpoints = json['namedEndpoints'];
    if (legacyNamedEndpoints is List) {
      for (final item in legacyNamedEndpoints.whereType<Map>()) {
        final named = Map<String, dynamic>.from(item);
        final namedId = named['id']?.toString() ?? '';
        final normalizedBaseUrl = LlmEndpoint.normalizeBaseUrl(
          named['baseUrl']?.toString() ?? '',
        ).toLowerCase();
        final existingIndex = normalizedBaseUrlToIndex[normalizedBaseUrl];
        if (normalizedBaseUrl.isNotEmpty && existingIndex != null) {
          final existing = endpoints[existingIndex];
          final existingLabel = existing['label']?.toString().trim() ?? '';
          final existingApiKey = existing['apiKey']?.toString().trim() ?? '';
          endpoints[existingIndex] = <String, dynamic>{
            ...existing,
            if (existingLabel.isEmpty) 'label': named['label'] ?? '',
            if (existingApiKey.isEmpty) 'apiKey': named['apiKey'] ?? '',
            // A legacy profile was selectable, so a merged entry stays enabled.
            'enabled': true,
          };
          if (namedId.isNotEmpty) {
            namedIdMapping[namedId] =
                endpoints[existingIndex]['id']?.toString() ?? namedId;
          }
          continue;
        }

        endpoints.add(<String, dynamic>{
          'id': namedId,
          'label': named['label'] ?? '',
          'baseUrl': named['baseUrl'] ?? '',
          'apiKey': named['apiKey'] ?? '',
          'model': '',
          'enabled': named['enabled'] ?? true,
          'source': 'discovered',
          if (named.containsKey('createdAt')) 'createdAt': named['createdAt'],
        });
        if (normalizedBaseUrl.isNotEmpty) {
          normalizedBaseUrlToIndex[normalizedBaseUrl] = endpoints.length - 1;
        }
      }
    }

    migrated['llmEndpoints'] = endpoints;
    for (final field in const <String>[
      'generalPrimaryEndpointId',
      'codingPrimaryEndpointId',
      'planPrimaryEndpointId',
      'memoryExtractionEndpointId',
      'subagentEndpointId',
      'goalSuggestionEndpointId',
      'approvalAutoReviewEndpointId',
      'planningEndpointId',
      'proReasoningEndpointId',
    ]) {
      final currentId = migrated[field]?.toString();
      if (currentId != null && namedIdMapping.containsKey(currentId)) {
        migrated[field] = namedIdMapping[currentId];
      }
    }
    migrated.remove('llmEndpointProfiles');
    migrated.remove('namedEndpoints');
    return migrated;
  }

  String get normalizedGoogleChatWebhookUrl => googleChatWebhookUrl.trim();

  bool get hasGoogleChatWebhook => normalizedGoogleChatWebhookUrl.isNotEmpty;

  int get effectiveCodingVerificationTimeoutSeconds =>
      codingVerificationTimeoutSeconds
          .clamp(
            minCodingVerificationTimeoutSeconds,
            maxCodingVerificationTimeoutSeconds,
          )
          .toInt();

  int get effectiveCodingVerificationMaxFailures =>
      codingVerificationMaxFailures
          .clamp(
            minCodingVerificationMaxFailures,
            maxCodingVerificationMaxFailures,
          )
          .toInt();

  bool get runsCodingVerificationOnCompletionClaim {
    return enableCodingVerificationFeedback &&
        codingVerificationTriggerPolicy ==
            CodingVerificationTriggerPolicy.onCompletionClaim;
  }

  Set<String> get disabledBuiltInToolsSet =>
      Set<String>.from(disabledBuiltInTools);

  /// Whether any chat-mode high-risk tool governed by the shared approval gate
  /// is currently exposed. Drives whether the chat permission-mode selector is
  /// shown. Browser tools have their own enable flag; SSH / BLE / serial are on
  /// unless explicitly disabled.
  bool get exposesGatedChatTools {
    if (browserToolsEnabled) return true;
    const connectionTools = {'ssh_connect', 'ble_connect', 'serial_open'};
    final disabled = disabledBuiltInToolsSet;
    return connectionTools.any((tool) => !disabled.contains(tool));
  }

  List<LocalCommandPermissionRule> get enabledLocalCommandPermissionRules =>
      localCommandPermissionRules
          .where((rule) => rule.enabled && rule.normalizedPattern.isNotEmpty)
          .toList(growable: false);

  List<RoutineComputerUseActionAllowlistEntry>
  get enabledRoutineComputerUseActionAllowlist =>
      routineComputerUseActionAllowlist
          .where(
            (entry) =>
                entry.enabled &&
                entry.normalizedToolName.isNotEmpty &&
                entry.hasBoundary,
          )
          .toList(growable: false);

  String get normalizedExternalSettingsPath => externalSettingsPath.trim();

  bool get hasExternalSettingsPath => normalizedExternalSettingsPath.isNotEmpty;

  List<ExternalToolHook> enabledExternalToolHooksFor(String event) {
    if (!externalToolHooksEnabled) {
      return const <ExternalToolHook>[];
    }
    final normalizedEvent = event.trim().toLowerCase();
    return externalToolHooks
        .map((hook) => hook.normalizedForPersistence())
        .where(
          (hook) =>
              hook.isUsable &&
              hook.normalizedEvent.toLowerCase() == normalizedEvent,
        )
        .toList(growable: false);
  }

  List<McpServerConfig> get configuredMcpServers {
    if (mcpServers.isNotEmpty) {
      return List<McpServerConfig>.from(mcpServers);
    }

    return buildMcpServersFromUrls(mcpUrls.isNotEmpty ? mcpUrls : [mcpUrl]);
  }

  List<McpServerConfig> get effectiveMcpServers {
    return configuredMcpServers
        .map((server) => server.copyWith(url: server.normalizedUrl))
        .toList(growable: false);
  }

  List<McpServerConfig> get enabledMcpServers {
    final enabledServers = <McpServerConfig>[];
    final seenIds = <String>{};

    for (final server in effectiveMcpServers) {
      if (!server.enabled || !server.isValid || !server.isTrusted) continue;
      final id = server.trustIdentity;
      if (!seenIds.add(id)) continue;

      enabledServers.add(
        server.type == McpServerType.http
            ? server.copyWith(url: server.normalizedUrl)
            : server,
      );
    }

    return enabledServers;
  }

  List<McpServerConfig> get connectableMcpServers {
    final connectableServers = <McpServerConfig>[];
    final seenIds = <String>{};

    for (final server in effectiveMcpServers) {
      if (!server.enabled || !server.isValid || server.isBlocked) continue;
      final id = server.trustIdentity;
      if (!seenIds.add(id)) continue;
      connectableServers.add(
        server.type == McpServerType.http
            ? server.copyWith(url: server.normalizedUrl)
            : server,
      );
    }

    return connectableServers;
  }

  List<String> get effectiveMcpUrls {
    return enabledMcpServers
        .map((server) => server.normalizedUrl)
        .toList(growable: false);
  }

  String get primaryMcpUrl =>
      effectiveMcpUrls.isEmpty ? '' : effectiveMcpUrls.first;

  static List<String> normalizeMcpUrls(Iterable<String> values) {
    return activeMcpUrlsFromServers(buildMcpServersFromUrls(values));
  }

  static List<McpServerConfig> buildMcpServersFromUrls(
    Iterable<String> values,
  ) {
    return values
        .map((value) => McpServerConfig(url: value, enabled: true))
        .toList(growable: false);
  }

  static List<String> activeMcpUrlsFromServers(
    Iterable<McpServerConfig> values,
  ) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final value in values) {
      final trimmed = value.normalizedUrl;
      if (!value.enabled || trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      if (!value.isTrusted) {
        continue;
      }
      normalized.add(trimmed);
    }

    return normalized;
  }
}
