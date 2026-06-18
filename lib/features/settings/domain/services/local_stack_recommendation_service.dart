import '../entities/app_settings.dart';
import '../entities/local_host_resources.dart';
import '../entities/local_model_lifecycle.dart';

enum LocalModelResourceFit { fits, close, tooLarge, unknown }

enum LocalModelResourceReason {
  fitsSafeBudget,
  nearSafeBudget,
  exceedsSafeBudget,
  missingHostMemory,
  missingModelHints,
}

enum LocalModelQuantizationHint { q4, q5, q6, q8, f16, unknown }

enum LocalStackRoleKind {
  memoryExtraction,
  subagent,
  goalSuggestion,
  approvalAutoReview,
}

enum LocalStackRoleSuggestionStatus {
  suggestSmallerModel,
  assignedMissing,
  noFitCandidate,
}

class LocalStackRoleModelSuggestion {
  const LocalStackRoleModelSuggestion({
    required this.role,
    required this.status,
    required this.assignedModelId,
    required this.usesMainModel,
    this.suggestedModelId,
  });

  final LocalStackRoleKind role;
  final LocalStackRoleSuggestionStatus status;
  final String assignedModelId;
  final bool usesMainModel;
  final String? suggestedModelId;

  bool get hasSuggestedModel =>
      suggestedModelId != null && suggestedModelId!.isNotEmpty;
}

class LocalStackRoleGuidance {
  const LocalStackRoleGuidance({required this.suggestions});

  const LocalStackRoleGuidance.empty() : suggestions = const [];

  final List<LocalStackRoleModelSuggestion> suggestions;

  bool get hasSuggestions => suggestions.isNotEmpty;

  LocalStackRoleModelSuggestion? suggestionFor(LocalStackRoleKind role) {
    for (final suggestion in suggestions) {
      if (suggestion.role == role) return suggestion;
    }
    return null;
  }
}

enum LocalStackSpeedupKind { ngramSpeculation, draftModelSpeculation }

enum LocalStackSpeedupStatus {
  recommended,
  alreadyConfigured,
  needsDraftModel,
  targetMissing,
}

class LocalStackSpeedupRecommendation {
  const LocalStackSpeedupRecommendation({
    required this.kind,
    required this.status,
    this.targetModelId,
    this.draftModelId,
  });

  final LocalStackSpeedupKind kind;
  final LocalStackSpeedupStatus status;
  final String? targetModelId;
  final String? draftModelId;

  bool get hasDraftModel => draftModelId != null && draftModelId!.isNotEmpty;
}

class LocalStackSpeedupGuidance {
  const LocalStackSpeedupGuidance({required this.recommendations});

  final List<LocalStackSpeedupRecommendation> recommendations;

  bool get hasRecommendations => recommendations.isNotEmpty;

  LocalStackSpeedupRecommendation? recommendationFor(
    LocalStackSpeedupKind kind,
  ) {
    for (final recommendation in recommendations) {
      if (recommendation.kind == kind) return recommendation;
    }
    return null;
  }
}

class LocalModelResourceRecommendation {
  const LocalModelResourceRecommendation({
    required this.modelId,
    required this.fit,
    required this.reason,
    required this.quantization,
    required this.safeBudgetBytes,
    this.parameterBillion,
    this.contextWindowTokens,
    this.estimatedMemoryBytes,
  });

  final String modelId;
  final LocalModelResourceFit fit;
  final LocalModelResourceReason reason;
  final LocalModelQuantizationHint quantization;
  final int safeBudgetBytes;
  final double? parameterBillion;
  final int? contextWindowTokens;
  final int? estimatedMemoryBytes;

  double? get estimatedMemoryGiB => estimatedMemoryBytes == null
      ? null
      : estimatedMemoryBytes! / localHostBytesPerGiB;

  bool get hasMemoryEstimate => estimatedMemoryBytes != null;
}

class LocalStackResourceGuidance {
  const LocalStackResourceGuidance({
    required this.hostProfile,
    required this.safeBudgetBytes,
    required this.closeBudgetBytes,
    required this.recommendations,
  });

  final LocalHostResourceProfile hostProfile;
  final int safeBudgetBytes;
  final int closeBudgetBytes;
  final List<LocalModelResourceRecommendation> recommendations;

  bool get hasDetectedMemory => hostProfile.hasDetectedMemory;

  int get fitCount => _count(LocalModelResourceFit.fits);

  int get closeCount => _count(LocalModelResourceFit.close);

  int get tooLargeCount => _count(LocalModelResourceFit.tooLarge);

  int get unknownCount => _count(LocalModelResourceFit.unknown);

  LocalModelResourceRecommendation? recommendationFor(String modelId) {
    for (final recommendation in recommendations) {
      if (recommendation.modelId == modelId) return recommendation;
    }
    return null;
  }

  int _count(LocalModelResourceFit fit) {
    return recommendations
        .where((recommendation) => recommendation.fit == fit)
        .length;
  }
}

class LocalStackRecommendationService {
  const LocalStackRecommendationService();

  static const double safeBudgetRatio = 0.70;
  static const double closeBudgetRatio = 0.85;
  static const double _metadataOverheadRatio = 1.15;
  static const int _defaultContextWindowTokens = 4096;

  LocalStackResourceGuidance buildGuidance({
    required LocalHostResourceProfile hostProfile,
    required LocalModelLifecycleCatalog catalog,
  }) {
    final totalMemoryBytes = hostProfile.totalMemoryBytes ?? 0;
    final safeBudgetBytes = (totalMemoryBytes * safeBudgetRatio).floor();
    final closeBudgetBytes = (totalMemoryBytes * closeBudgetRatio).floor();

    return LocalStackResourceGuidance(
      hostProfile: hostProfile,
      safeBudgetBytes: safeBudgetBytes,
      closeBudgetBytes: closeBudgetBytes,
      recommendations: [
        for (final model in catalog.models)
          _recommendModel(
            model: model,
            hostProfile: hostProfile,
            safeBudgetBytes: safeBudgetBytes,
            closeBudgetBytes: closeBudgetBytes,
          ),
      ],
    );
  }

  LocalStackSpeedupGuidance buildSpeedupGuidance({
    required AppSettings settings,
    required LocalModelLifecycleCatalog catalog,
    required String endpointId,
  }) {
    if (!catalog.supported || catalog.models.isEmpty) {
      return const LocalStackSpeedupGuidance(recommendations: []);
    }

    final recommendations = <LocalStackSpeedupRecommendation>[
      LocalStackSpeedupRecommendation(
        kind: LocalStackSpeedupKind.ngramSpeculation,
        status: _hasNgramSpeculation(catalog)
            ? LocalStackSpeedupStatus.alreadyConfigured
            : LocalStackSpeedupStatus.recommended,
      ),
    ];

    final draftRecommendation = _buildDraftModelRecommendation(
      settings: settings,
      catalog: catalog,
      endpointId: endpointId,
    );
    if (draftRecommendation != null) {
      recommendations.add(draftRecommendation);
    }

    return LocalStackSpeedupGuidance(recommendations: recommendations);
  }

  LocalStackRoleGuidance buildRoleGuidance({
    required AppSettings settings,
    required LocalModelLifecycleCatalog catalog,
    required String endpointId,
    required LocalStackResourceGuidance resourceGuidance,
  }) {
    if (!catalog.supported ||
        !resourceGuidance.hasDetectedMemory ||
        settings.llmProvider != LlmProvider.openAiCompatible) {
      return const LocalStackRoleGuidance.empty();
    }

    final suggestions = <LocalStackRoleModelSuggestion>[];
    for (final target in _roleTargetsForEndpoint(settings, endpointId)) {
      final assigned = resourceGuidance.recommendationFor(target.modelId);
      if (assigned == null) {
        suggestions.add(
          LocalStackRoleModelSuggestion(
            role: target.role,
            status: LocalStackRoleSuggestionStatus.assignedMissing,
            assignedModelId: target.modelId,
            usesMainModel: target.usesMainModel,
          ),
        );
        continue;
      }

      if (_isIdealRoleModel(target.role, assigned)) {
        continue;
      }

      final candidate = _findRoleModelCandidate(
        role: target.role,
        currentModelId: target.modelId,
        resourceGuidance: resourceGuidance,
      );
      suggestions.add(
        LocalStackRoleModelSuggestion(
          role: target.role,
          status: candidate == null
              ? LocalStackRoleSuggestionStatus.noFitCandidate
              : LocalStackRoleSuggestionStatus.suggestSmallerModel,
          assignedModelId: target.modelId,
          usesMainModel: target.usesMainModel,
          suggestedModelId: candidate?.modelId,
        ),
      );
    }

    return LocalStackRoleGuidance(suggestions: suggestions);
  }

  LocalModelResourceRecommendation _recommendModel({
    required LocalManagedModel model,
    required LocalHostResourceProfile hostProfile,
    required int safeBudgetBytes,
    required int closeBudgetBytes,
  }) {
    if (!hostProfile.hasDetectedMemory) {
      return LocalModelResourceRecommendation(
        modelId: model.id,
        fit: LocalModelResourceFit.unknown,
        reason: LocalModelResourceReason.missingHostMemory,
        quantization: LocalModelQuantizationHint.unknown,
        safeBudgetBytes: safeBudgetBytes,
      );
    }

    final source = _modelHintSource(model);
    final parameterBillion = _detectParameterBillion(source);
    final quantization = _detectQuantization(source);
    if (parameterBillion == null ||
        quantization == LocalModelQuantizationHint.unknown) {
      return LocalModelResourceRecommendation(
        modelId: model.id,
        fit: LocalModelResourceFit.unknown,
        reason: LocalModelResourceReason.missingModelHints,
        quantization: quantization,
        safeBudgetBytes: safeBudgetBytes,
        parameterBillion: parameterBillion,
        contextWindowTokens: model.contextWindowTokens,
      );
    }

    final estimatedMemoryBytes = _estimateMemoryBytes(
      parameterBillion: parameterBillion,
      quantization: quantization,
      contextWindowTokens:
          model.contextWindowTokens ?? _defaultContextWindowTokens,
    );
    final fit = estimatedMemoryBytes <= safeBudgetBytes
        ? LocalModelResourceFit.fits
        : estimatedMemoryBytes <= closeBudgetBytes
        ? LocalModelResourceFit.close
        : LocalModelResourceFit.tooLarge;
    final reason = switch (fit) {
      LocalModelResourceFit.fits => LocalModelResourceReason.fitsSafeBudget,
      LocalModelResourceFit.close => LocalModelResourceReason.nearSafeBudget,
      LocalModelResourceFit.tooLarge =>
        LocalModelResourceReason.exceedsSafeBudget,
      LocalModelResourceFit.unknown =>
        LocalModelResourceReason.missingModelHints,
    };

    return LocalModelResourceRecommendation(
      modelId: model.id,
      fit: fit,
      reason: reason,
      quantization: quantization,
      safeBudgetBytes: safeBudgetBytes,
      parameterBillion: parameterBillion,
      contextWindowTokens: model.contextWindowTokens,
      estimatedMemoryBytes: estimatedMemoryBytes,
    );
  }

  String _modelHintSource(LocalManagedModel model) {
    return [
      model.id,
      if (model.path != null) model.path!,
      ...model.metadataHints,
      ...model.commandArguments,
    ].join(' ');
  }

  LocalStackSpeedupRecommendation? _buildDraftModelRecommendation({
    required AppSettings settings,
    required LocalModelLifecycleCatalog catalog,
    required String endpointId,
  }) {
    final targetModelId = _draftTargetModelIdForEndpoint(settings, endpointId);
    if (targetModelId == null || targetModelId.isEmpty) return null;

    final targetModel = _modelById(catalog, targetModelId);
    if (targetModel == null) {
      return LocalStackSpeedupRecommendation(
        kind: LocalStackSpeedupKind.draftModelSpeculation,
        status: LocalStackSpeedupStatus.targetMissing,
        targetModelId: targetModelId,
      );
    }

    if (_hasDraftModelSpeculation(targetModel.commandArguments)) {
      return LocalStackSpeedupRecommendation(
        kind: LocalStackSpeedupKind.draftModelSpeculation,
        status: LocalStackSpeedupStatus.alreadyConfigured,
        targetModelId: targetModelId,
      );
    }

    final draftModel = _findDraftModelCandidate(
      catalog: catalog,
      targetModel: targetModel,
    );
    return LocalStackSpeedupRecommendation(
      kind: LocalStackSpeedupKind.draftModelSpeculation,
      status: draftModel == null
          ? LocalStackSpeedupStatus.needsDraftModel
          : LocalStackSpeedupStatus.recommended,
      targetModelId: targetModelId,
      draftModelId: draftModel?.id,
    );
  }

  String? _draftTargetModelIdForEndpoint(
    AppSettings settings,
    String endpointId,
  ) {
    if (settings.llmProvider != LlmProvider.openAiCompatible) {
      return null;
    }

    final selectedEndpointId = endpointId.trim();
    if (selectedEndpointId.isNotEmpty) {
      return settings.subagentEndpointId.trim() == selectedEndpointId
          ? settings.subagentModel.trim()
          : null;
    }

    final subagentEndpointId = settings.subagentEndpointId.trim();
    if (subagentEndpointId.isEmpty &&
        settings.subagentModel.trim().isNotEmpty) {
      return settings.subagentModel.trim();
    }
    return settings.model.trim();
  }

  LocalManagedModel? _modelById(
    LocalModelLifecycleCatalog catalog,
    String modelId,
  ) {
    for (final model in catalog.models) {
      if (model.id == modelId) return model;
    }
    return null;
  }

  LocalManagedModel? _findDraftModelCandidate({
    required LocalModelLifecycleCatalog catalog,
    required LocalManagedModel targetModel,
  }) {
    final targetSize = _detectParameterBillion(_modelHintSource(targetModel));
    final candidates = <_DraftModelCandidate>[];
    for (final model in catalog.models) {
      if (model.id == targetModel.id) continue;

      final source = _modelHintSource(model);
      final size = _detectParameterBillion(source);
      final draftNamed = source.toLowerCase().contains('draft');
      final smallEnough =
          size != null &&
          (size <= 3 || (targetSize != null && size <= targetSize * 0.4));
      if (!draftNamed && !smallEnough) continue;

      candidates.add(
        _DraftModelCandidate(
          model: model,
          size: size ?? double.maxFinite,
          draftNamed: draftNamed,
        ),
      );
    }

    candidates.sort((left, right) {
      if (left.draftNamed != right.draftNamed) {
        return left.draftNamed ? -1 : 1;
      }
      return left.size.compareTo(right.size);
    });
    return candidates.isEmpty ? null : candidates.first.model;
  }

  List<_RoleModelTarget> _roleTargetsForEndpoint(
    AppSettings settings,
    String endpointId,
  ) {
    final selectedEndpointId = endpointId.trim();
    final mainModelId = settings.model.trim();
    final targets = <_RoleModelTarget>[];

    void addRole({
      required LocalStackRoleKind role,
      required String roleModelId,
      required String roleEndpointId,
    }) {
      final normalizedEndpointId = roleEndpointId.trim();
      final normalizedRoleModelId = roleModelId.trim();
      if (selectedEndpointId.isNotEmpty) {
        if (normalizedEndpointId == selectedEndpointId &&
            normalizedRoleModelId.isNotEmpty) {
          targets.add(
            _RoleModelTarget(
              role: role,
              modelId: normalizedRoleModelId,
              usesMainModel: false,
            ),
          );
        }
        return;
      }

      if (normalizedEndpointId.isNotEmpty) return;
      final modelId = normalizedRoleModelId.isEmpty
          ? mainModelId
          : normalizedRoleModelId;
      if (modelId.isEmpty) return;
      targets.add(
        _RoleModelTarget(
          role: role,
          modelId: modelId,
          usesMainModel: normalizedRoleModelId.isEmpty,
        ),
      );
    }

    addRole(
      role: LocalStackRoleKind.memoryExtraction,
      roleModelId: settings.memoryExtractionModel,
      roleEndpointId: settings.memoryExtractionEndpointId,
    );
    addRole(
      role: LocalStackRoleKind.subagent,
      roleModelId: settings.subagentModel,
      roleEndpointId: settings.subagentEndpointId,
    );
    addRole(
      role: LocalStackRoleKind.goalSuggestion,
      roleModelId: settings.goalSuggestionModel,
      roleEndpointId: settings.goalSuggestionEndpointId,
    );
    addRole(
      role: LocalStackRoleKind.approvalAutoReview,
      roleModelId: settings.approvalAutoReviewModel,
      roleEndpointId: settings.approvalAutoReviewEndpointId,
    );
    return targets;
  }

  bool _isIdealRoleModel(
    LocalStackRoleKind role,
    LocalModelResourceRecommendation recommendation,
  ) {
    final size = recommendation.parameterBillion;
    return recommendation.fit == LocalModelResourceFit.fits &&
        size != null &&
        size <= _idealRoleModelSizeBillion(role) &&
        _isFullRoleModelCandidate(recommendation.modelId);
  }

  LocalModelResourceRecommendation? _findRoleModelCandidate({
    required LocalStackRoleKind role,
    required String currentModelId,
    required LocalStackResourceGuidance resourceGuidance,
  }) {
    final maxSize = _idealRoleModelSizeBillion(role);
    final candidates = resourceGuidance.recommendations.where((recommendation) {
      final size = recommendation.parameterBillion;
      return recommendation.modelId != currentModelId &&
          recommendation.fit == LocalModelResourceFit.fits &&
          size != null &&
          size <= maxSize &&
          _isFullRoleModelCandidate(recommendation.modelId);
    }).toList();

    candidates.sort((left, right) {
      final leftSize = left.parameterBillion ?? double.maxFinite;
      final rightSize = right.parameterBillion ?? double.maxFinite;
      return leftSize.compareTo(rightSize);
    });
    return candidates.isEmpty ? null : candidates.first;
  }

  double _idealRoleModelSizeBillion(LocalStackRoleKind role) {
    return switch (role) {
      LocalStackRoleKind.memoryExtraction => 3,
      LocalStackRoleKind.goalSuggestion => 3,
      LocalStackRoleKind.approvalAutoReview => 3,
      LocalStackRoleKind.subagent => 8,
    };
  }

  bool _isFullRoleModelCandidate(String modelId) {
    final normalized = modelId.toLowerCase();
    return !normalized.contains('embedding') &&
        !normalized.contains('embed') &&
        !normalized.contains('rerank') &&
        !normalized.contains('draft');
  }

  bool _hasNgramSpeculation(LocalModelLifecycleCatalog catalog) {
    return catalog.models.any(
      (model) => _hasOptionValue(
        model.commandArguments,
        option: '--spec-type',
        value: 'ngram-simple',
      ),
    );
  }

  bool _hasDraftModelSpeculation(List<String> arguments) {
    return arguments.any((argument) {
      final normalized = argument.trim().toLowerCase();
      return normalized == '--model-draft' ||
          normalized == '-md' ||
          normalized.startsWith('--model-draft=') ||
          normalized.contains('draft');
    });
  }

  bool _hasOptionValue(
    List<String> arguments, {
    required String option,
    required String value,
  }) {
    final normalizedOption = option.toLowerCase();
    final normalizedValue = value.toLowerCase();
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index].trim().toLowerCase();
      if (argument == normalizedOption &&
          index + 1 < arguments.length &&
          arguments[index + 1].trim().toLowerCase() == normalizedValue) {
        return true;
      }
      if (argument == '$normalizedOption=$normalizedValue' ||
          argument.contains(normalizedValue)) {
        return true;
      }
    }
    return false;
  }

  double? _detectParameterBillion(String source) {
    final match = RegExp(
      r'(^|[^A-Za-z0-9])(\d+(?:\.\d+)?)\s*[bB]([^A-Za-z0-9]|$)',
    ).firstMatch(source);
    if (match == null) return null;
    return double.tryParse(match.group(2)!);
  }

  LocalModelQuantizationHint _detectQuantization(String source) {
    final normalized = source.toUpperCase();
    if (normalized.contains('BF16') ||
        normalized.contains('FP16') ||
        normalized.contains('F16')) {
      return LocalModelQuantizationHint.f16;
    }
    if (normalized.contains('Q8') || normalized.contains('8BIT')) {
      return LocalModelQuantizationHint.q8;
    }
    if (normalized.contains('Q6') || normalized.contains('6BIT')) {
      return LocalModelQuantizationHint.q6;
    }
    if (normalized.contains('Q5') || normalized.contains('5BIT')) {
      return LocalModelQuantizationHint.q5;
    }
    if (normalized.contains('Q4') || normalized.contains('4BIT')) {
      return LocalModelQuantizationHint.q4;
    }
    return LocalModelQuantizationHint.unknown;
  }

  int _estimateMemoryBytes({
    required double parameterBillion,
    required LocalModelQuantizationHint quantization,
    required int contextWindowTokens,
  }) {
    final modelBytes =
        parameterBillion * 1000000000 * _bytesPerParameter(quantization);
    final contextScale = contextWindowTokens / _defaultContextWindowTokens;
    final contextReserveGiB = parameterBillion * 0.08 * contextScale;
    final contextReserveBytes = contextReserveGiB * localHostBytesPerGiB;
    return (modelBytes * _metadataOverheadRatio + contextReserveBytes).ceil();
  }

  double _bytesPerParameter(LocalModelQuantizationHint quantization) {
    return switch (quantization) {
      LocalModelQuantizationHint.q4 => 0.65,
      LocalModelQuantizationHint.q5 => 0.80,
      LocalModelQuantizationHint.q6 => 1.00,
      LocalModelQuantizationHint.q8 => 1.15,
      LocalModelQuantizationHint.f16 => 2.20,
      LocalModelQuantizationHint.unknown => 1.00,
    };
  }
}

class _DraftModelCandidate {
  const _DraftModelCandidate({
    required this.model,
    required this.size,
    required this.draftNamed,
  });

  final LocalManagedModel model;
  final double size;
  final bool draftNamed;
}

class _RoleModelTarget {
  const _RoleModelTarget({
    required this.role,
    required this.modelId,
    required this.usesMainModel,
  });

  final LocalStackRoleKind role;
  final String modelId;
  final bool usesMainModel;
}
