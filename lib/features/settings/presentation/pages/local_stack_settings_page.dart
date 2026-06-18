import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/local_host_resources.dart';
import '../../domain/entities/local_model_lifecycle.dart';
import '../../domain/services/local_model_preparation_service.dart';
import '../../domain/services/local_stack_recommendation_service.dart';
import '../providers/local_model_lifecycle_provider.dart';
import '../providers/settings_notifier.dart';

class LocalStackSettingsPage extends ConsumerStatefulWidget {
  const LocalStackSettingsPage({super.key});

  @override
  ConsumerState<LocalStackSettingsPage> createState() =>
      _LocalStackSettingsPageState();
}

class _LocalStackSettingsPageState
    extends ConsumerState<LocalStackSettingsPage> {
  final Set<String> _pendingModelIds = <String>{};
  String _selectedEndpointId = '';
  bool _preparingRoleModels = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final endpoints = ref.watch(localModelLifecycleEndpointOptionsProvider);
    final selectedEndpoint = _selectedEndpoint(endpoints);
    final catalog = ref.watch(
      localModelLifecycleCatalogForEndpointProvider(selectedEndpoint),
    );
    final hostResources = ref.watch(localHostResourceProfileProvider);
    final recommendationService = ref.watch(
      localStackRecommendationServiceProvider,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('settings.local_stack_title'.tr()),
        actions: [
          IconButton(
            key: const ValueKey('local-stack-refresh'),
            tooltip: 'settings.local_stack_refresh'.tr(),
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(selectedEndpoint),
          ),
        ],
      ),
      body: catalog.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LocalStackMessage(
          icon: Icons.error_outline,
          message: 'settings.local_stack_load_error'.tr(args: ['$error']),
        ),
        data: (catalog) => _LocalStackBody(
          settings: settings,
          endpoints: endpoints,
          selectedEndpoint: selectedEndpoint,
          onEndpointChanged: _selectEndpoint,
          catalog: catalog,
          hostResources: hostResources,
          recommendationService: recommendationService,
          speedupGuidance: recommendationService.buildSpeedupGuidance(
            settings: settings,
            catalog: catalog,
            endpointId: selectedEndpoint.id,
          ),
          rolePlan: ref
              .watch(localModelPreparationServiceProvider)
              .buildRoleModelPlanForEndpoint(
                settings: settings,
                catalog: catalog,
                endpointId: selectedEndpoint.id,
              ),
          pendingModelIds: _pendingModelIds,
          preparingRoleModels: _preparingRoleModels,
          onPrepareRoleModels: () => _runPrepareRoleModels(selectedEndpoint),
          onLoad: (modelId) => _runModelAction(
            endpoint: selectedEndpoint,
            modelId: modelId,
            action: _LocalStackModelAction.load,
          ),
          onUnload: (modelId) => _runModelAction(
            endpoint: selectedEndpoint,
            modelId: modelId,
            action: _LocalStackModelAction.unload,
          ),
        ),
      ),
    );
  }

  LocalModelLifecycleEndpointConfig _selectedEndpoint(
    List<LocalModelLifecycleEndpointConfig> endpoints,
  ) {
    for (final endpoint in endpoints) {
      if (endpoint.id == _selectedEndpointId) {
        return endpoint;
      }
    }
    return endpoints.first;
  }

  void _selectEndpoint(String endpointId) {
    setState(() {
      _selectedEndpointId = endpointId;
      _pendingModelIds.clear();
    });
  }

  void _refresh(LocalModelLifecycleEndpointConfig endpoint) {
    ref.invalidate(localModelLifecycleCatalogForEndpointProvider(endpoint));
    if (endpoint.isPrimary) {
      ref.invalidate(localModelLifecycleCatalogProvider);
    }
  }

  Future<void> _runModelAction({
    required LocalModelLifecycleEndpointConfig endpoint,
    required String modelId,
    required _LocalStackModelAction action,
  }) async {
    if (_pendingModelIds.contains(modelId)) return;
    setState(() => _pendingModelIds.add(modelId));
    try {
      final dataSource = ref.read(localModelLifecycleDataSourceFactoryProvider)(
        endpoint,
      );
      final result = switch (action) {
        _LocalStackModelAction.load => await dataSource.loadManagedModel(
          modelId,
        ),
        _LocalStackModelAction.unload => await dataSource.unloadManagedModel(
          modelId,
        ),
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.message)));
      _refresh(endpoint);
    } finally {
      if (mounted) {
        setState(() => _pendingModelIds.remove(modelId));
      }
    }
  }

  Future<void> _runPrepareRoleModels(
    LocalModelLifecycleEndpointConfig endpoint,
  ) async {
    if (_preparingRoleModels) return;
    setState(() => _preparingRoleModels = true);
    try {
      final settings = ref.read(settingsNotifierProvider);
      final catalog = await ref.read(
        localModelLifecycleCatalogForEndpointProvider(endpoint).future,
      );
      final plan = ref
          .read(localModelPreparationServiceProvider)
          .buildRoleModelPlanForEndpoint(
            settings: settings,
            catalog: catalog,
            endpointId: endpoint.id,
          );

      if (!mounted) return;
      if (!plan.hasTargets) {
        _showSnackBar('settings.local_stack_prepare_no_endpoint_roles'.tr());
        return;
      }
      if (!plan.hasLoadableModels) {
        _showSnackBar(
          'settings.local_stack_prepare_no_work'.tr(
            args: ['${plan.readyModelIds.length}'],
          ),
        );
        return;
      }

      final dataSource = ref.read(localModelLifecycleDataSourceFactoryProvider)(
        endpoint,
      );
      var loadedCount = 0;
      var failedCount = 0;
      for (final modelId in plan.loadableModelIds) {
        final result = await dataSource.loadManagedModel(modelId);
        if (result.supported && result.succeeded) {
          loadedCount++;
        } else {
          failedCount++;
        }
      }

      if (!mounted) return;
      final skippedCount =
          plan.readyModelIds.length +
          plan.inProgressModelIds.length +
          plan.missingModelIds.length;
      _showSnackBar(
        failedCount == 0
            ? 'settings.local_stack_prepare_done'.tr(
                args: ['$loadedCount', '$skippedCount'],
              )
            : 'settings.local_stack_prepare_partial'.tr(
                args: ['$loadedCount', '$failedCount', '$skippedCount'],
              ),
      );
      _refresh(endpoint);
    } finally {
      if (mounted) {
        setState(() => _preparingRoleModels = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _LocalStackModelAction { load, unload }

class _LocalStackBody extends StatelessWidget {
  const _LocalStackBody({
    required this.settings,
    required this.endpoints,
    required this.selectedEndpoint,
    required this.onEndpointChanged,
    required this.catalog,
    required this.hostResources,
    required this.recommendationService,
    required this.speedupGuidance,
    required this.rolePlan,
    required this.pendingModelIds,
    required this.preparingRoleModels,
    required this.onPrepareRoleModels,
    required this.onLoad,
    required this.onUnload,
  });

  final AppSettings settings;
  final List<LocalModelLifecycleEndpointConfig> endpoints;
  final LocalModelLifecycleEndpointConfig selectedEndpoint;
  final ValueChanged<String> onEndpointChanged;
  final LocalModelLifecycleCatalog catalog;
  final AsyncValue<LocalHostResourceProfile> hostResources;
  final LocalStackRecommendationService recommendationService;
  final LocalStackSpeedupGuidance speedupGuidance;
  final LocalModelPreparationPlan rolePlan;
  final Set<String> pendingModelIds;
  final bool preparingRoleModels;
  final VoidCallback onPrepareRoleModels;
  final ValueChanged<String> onLoad;
  final ValueChanged<String> onUnload;

  @override
  Widget build(BuildContext context) {
    final resourceGuidance = hostResources.whenData(
      (profile) => recommendationService.buildGuidance(
        hostProfile: profile,
        catalog: catalog,
      ),
    );
    final guidance = resourceGuidance.when(
      data: (value) => value,
      loading: () => null,
      error: (_, _) => null,
    );
    final roleGuidance = guidance == null
        ? const LocalStackRoleGuidance.empty()
        : recommendationService.buildRoleGuidance(
            settings: settings,
            catalog: catalog,
            endpointId: selectedEndpoint.id,
            resourceGuidance: guidance,
          );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'settings.local_stack_intro'.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _LocalStackEndpointDropdown(
          endpoints: endpoints,
          selectedEndpoint: selectedEndpoint,
          onChanged: onEndpointChanged,
        ),
        const SizedBox(height: 16),
        if (!catalog.supported) ...[
          _LocalStackInlineMessage(
            icon: Icons.info_outline,
            message:
                catalog.message ??
                'settings.local_stack_unsupported_default'.tr(),
          ),
        ] else if (catalog.models.isEmpty) ...[
          _LocalStackInlineMessage(
            icon: Icons.storage_outlined,
            message: 'settings.local_stack_empty'.tr(),
          ),
        ] else ...[
          _LocalStackResourceGuidancePanel(guidance: resourceGuidance),
          const SizedBox(height: 16),
          if (roleGuidance.hasSuggestions) ...[
            _LocalStackRoleGuidancePanel(guidance: roleGuidance),
            const SizedBox(height: 16),
          ],
          _LocalStackSpeedupGuidancePanel(guidance: speedupGuidance),
          const SizedBox(height: 16),
          _PrepareRoleModelsButton(
            plan: rolePlan,
            preparing: preparingRoleModels,
            onPressed: onPrepareRoleModels,
          ),
          const SizedBox(height: 24),
          Text(
            'settings.local_stack_models_section'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final model in catalog.models)
            _ManagedModelTile(
              model: model,
              recommendation: guidance?.hasDetectedMemory == true
                  ? guidance?.recommendationFor(model.id)
                  : null,
              pending: pendingModelIds.contains(model.id),
              onLoad: () => onLoad(model.id),
              onUnload: () => onUnload(model.id),
            ),
        ],
      ],
    );
  }
}

class _LocalStackRoleGuidancePanel extends StatelessWidget {
  const _LocalStackRoleGuidancePanel({required this.guidance});

  final LocalStackRoleGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.assignment_ind_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'settings.local_stack_roles_section'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final suggestion in guidance.suggestions) ...[
                Text(
                  _roleSuggestionText(suggestion),
                  style: theme.textTheme.bodySmall,
                ),
                if (suggestion != guidance.suggestions.last)
                  const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _roleSuggestionText(LocalStackRoleModelSuggestion suggestion) {
    final roleLabel = _roleLabel(suggestion.role);
    return switch (suggestion.status) {
      LocalStackRoleSuggestionStatus.suggestSmallerModel =>
        suggestion.usesMainModel
            ? 'settings.local_stack_role_suggest_main'.tr(
                args: [
                  roleLabel,
                  suggestion.assignedModelId,
                  suggestion.suggestedModelId ?? '',
                ],
              )
            : 'settings.local_stack_role_suggest_assigned'.tr(
                args: [
                  roleLabel,
                  suggestion.assignedModelId,
                  suggestion.suggestedModelId ?? '',
                ],
              ),
      LocalStackRoleSuggestionStatus.assignedMissing =>
        'settings.local_stack_role_missing'.tr(
          args: [roleLabel, suggestion.assignedModelId],
        ),
      LocalStackRoleSuggestionStatus.noFitCandidate =>
        suggestion.usesMainModel
            ? 'settings.local_stack_role_no_candidate_main'.tr(
                args: [roleLabel, suggestion.assignedModelId],
              )
            : 'settings.local_stack_role_no_candidate_assigned'.tr(
                args: [roleLabel, suggestion.assignedModelId],
              ),
    };
  }

  String _roleLabel(LocalStackRoleKind role) {
    return switch (role) {
      LocalStackRoleKind.memoryExtraction =>
        'settings.model_routing_memory_extraction'.tr(),
      LocalStackRoleKind.subagent => 'settings.model_routing_subagent'.tr(),
      LocalStackRoleKind.goalSuggestion =>
        'settings.model_routing_goal_suggestion'.tr(),
      LocalStackRoleKind.approvalAutoReview =>
        'settings.model_routing_approval_auto_review'.tr(),
    };
  }
}

class _LocalStackResourceGuidancePanel extends StatelessWidget {
  const _LocalStackResourceGuidancePanel({required this.guidance});

  final AsyncValue<LocalStackResourceGuidance> guidance;

  @override
  Widget build(BuildContext context) {
    return guidance.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('settings.local_stack_resource_detecting'.tr())),
        ],
      ),
      error: (error, _) => _LocalStackGuidanceContent(
        icon: Icons.memory_outlined,
        title: 'settings.local_stack_resource_section'.tr(),
        body: 'settings.local_stack_resource_detection_error'.tr(
          args: ['$error'],
        ),
      ),
      data: (guidance) {
        if (!guidance.hasDetectedMemory) {
          return _LocalStackGuidanceContent(
            icon: Icons.memory_outlined,
            title: 'settings.local_stack_resource_section'.tr(),
            body: 'settings.local_stack_resource_unavailable'.tr(),
          );
        }

        final hostGiB = _formatGiB(guidance.hostProfile.totalMemoryBytes!);
        final safeBudgetGiB = _formatGiB(guidance.safeBudgetBytes);
        final unifiedSuffix = guidance.hostProfile.appleSiliconUnifiedMemory
            ? 'settings.local_stack_resource_unified_suffix'.tr()
            : '';
        return _LocalStackGuidanceContent(
          icon: Icons.memory_outlined,
          title: 'settings.local_stack_resource_section'.tr(),
          body: [
            'settings.local_stack_resource_summary'.tr(
              args: [
                hostGiB,
                unifiedSuffix,
                guidance.hostProfile.detectionMethod,
              ],
            ),
            'settings.local_stack_resource_counts'.tr(
              args: [
                '${guidance.fitCount}',
                '${guidance.closeCount}',
                '${guidance.tooLargeCount}',
                '${guidance.unknownCount}',
              ],
            ),
            'settings.local_stack_resource_assumption'.tr(
              args: [safeBudgetGiB],
            ),
          ].join(' '),
        );
      },
    );
  }
}

class _LocalStackGuidanceContent extends StatelessWidget {
  const _LocalStackGuidanceContent({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(body, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocalStackSpeedupGuidancePanel extends StatelessWidget {
  const _LocalStackSpeedupGuidancePanel({required this.guidance});

  final LocalStackSpeedupGuidance guidance;

  @override
  Widget build(BuildContext context) {
    if (!guidance.hasRecommendations) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.bolt_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'settings.local_stack_speedups_section'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final recommendation in guidance.recommendations) ...[
                Text(
                  _speedupText(recommendation),
                  style: theme.textTheme.bodySmall,
                ),
                if (recommendation != guidance.recommendations.last)
                  const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _speedupText(LocalStackSpeedupRecommendation recommendation) {
    return switch (recommendation.kind) {
      LocalStackSpeedupKind.ngramSpeculation => _ngramText(recommendation),
      LocalStackSpeedupKind.draftModelSpeculation => _draftText(recommendation),
    };
  }

  String _ngramText(LocalStackSpeedupRecommendation recommendation) {
    return recommendation.status == LocalStackSpeedupStatus.alreadyConfigured
        ? 'settings.local_stack_speedup_ngram_configured'.tr()
        : 'settings.local_stack_speedup_ngram_recommended'.tr();
  }

  String _draftText(LocalStackSpeedupRecommendation recommendation) {
    final targetModelId = recommendation.targetModelId ?? '';
    return switch (recommendation.status) {
      LocalStackSpeedupStatus.alreadyConfigured =>
        'settings.local_stack_speedup_draft_configured'.tr(
          args: [targetModelId],
        ),
      LocalStackSpeedupStatus.recommended =>
        'settings.local_stack_speedup_draft_recommended'.tr(
          args: [targetModelId, recommendation.draftModelId ?? ''],
        ),
      LocalStackSpeedupStatus.needsDraftModel =>
        'settings.local_stack_speedup_draft_needs_model'.tr(
          args: [targetModelId],
        ),
      LocalStackSpeedupStatus.targetMissing =>
        'settings.local_stack_speedup_draft_target_missing'.tr(
          args: [targetModelId],
        ),
    };
  }
}

class _LocalStackEndpointDropdown extends StatelessWidget {
  const _LocalStackEndpointDropdown({
    required this.endpoints,
    required this.selectedEndpoint,
    required this.onChanged,
  });

  final List<LocalModelLifecycleEndpointConfig> endpoints;
  final LocalModelLifecycleEndpointConfig selectedEndpoint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const ValueKey('local-stack-endpoint-selector'),
      initialValue: selectedEndpoint.id,
      decoration: InputDecoration(
        labelText: 'settings.local_stack_endpoint_label'.tr(),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final endpoint in endpoints)
          DropdownMenuItem<String>(
            value: endpoint.id,
            child: Text(
              endpoint.isPrimary
                  ? 'settings.model_routing_endpoint_primary'.tr()
                  : endpoint.label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) => onChanged(value ?? ''),
    );
  }
}

class _PrepareRoleModelsButton extends StatelessWidget {
  const _PrepareRoleModelsButton({
    required this.plan,
    required this.preparing,
    required this.onPressed,
  });

  final LocalModelPreparationPlan plan;
  final bool preparing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final targetCount = plan.targetModelIds.length;
    final loadableCount = plan.loadableModelIds.length;
    final label = preparing
        ? 'settings.local_stack_preparing_roles'.tr()
        : 'settings.local_stack_prepare_roles'.tr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          key: const ValueKey('local-stack-prepare-role-models'),
          onPressed: preparing || !plan.hasTargets ? null : onPressed,
          icon: preparing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add_check_outlined),
          label: Text(label),
        ),
        const SizedBox(height: 8),
        Text(
          targetCount == 0
              ? 'settings.local_stack_prepare_roles_empty'.tr()
              : 'settings.local_stack_prepare_roles_summary'.tr(
                  args: ['$loadableCount', '$targetCount'],
                ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ManagedModelTile extends StatelessWidget {
  const _ManagedModelTile({
    required this.model,
    required this.recommendation,
    required this.pending,
    required this.onLoad,
    required this.onUnload,
  });

  final LocalManagedModel model;
  final LocalModelResourceRecommendation? recommendation;
  final bool pending;
  final VoidCallback onLoad;
  final VoidCallback onUnload;

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel(model.state);
    final details = <String>[
      statusLabel,
      if (model.contextWindowTokens != null)
        'settings.local_stack_context_tokens'.tr(
          args: ['${model.contextWindowTokens}'],
        ),
      if (recommendation != null) _resourceFitLabel(recommendation!),
      if (model.failed) 'settings.local_stack_failed'.tr(),
      if (model.path != null) model.path!,
    ];

    return ListTile(
      key: ValueKey('local-stack-model-${model.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(_statusIcon(model.state)),
      title: Text(model.id, overflow: TextOverflow.ellipsis),
      subtitle: Text(details.join(' · '), overflow: TextOverflow.ellipsis),
      trailing: _ModelActionButton(
        model: model,
        pending: pending,
        onLoad: onLoad,
        onUnload: onUnload,
      ),
    );
  }

  String _statusLabel(LocalModelLifecycleState state) {
    return 'settings.local_stack_status_${state.name}'.tr();
  }

  String _resourceFitLabel(LocalModelResourceRecommendation recommendation) {
    final estimatedMemoryBytes = recommendation.estimatedMemoryBytes;
    if (estimatedMemoryBytes == null) {
      return 'settings.local_stack_resource_fit_unknown'.tr();
    }
    return 'settings.local_stack_resource_fit_${recommendation.fit.name}'.tr(
      args: [_formatGiB(estimatedMemoryBytes)],
    );
  }

  IconData _statusIcon(LocalModelLifecycleState state) {
    return switch (state) {
      LocalModelLifecycleState.loaded => Icons.check_circle_outline,
      LocalModelLifecycleState.loading => Icons.pending_outlined,
      LocalModelLifecycleState.unloaded => Icons.radio_button_unchecked,
      LocalModelLifecycleState.sleeping => Icons.bedtime_outlined,
      LocalModelLifecycleState.downloading => Icons.downloading_outlined,
      LocalModelLifecycleState.unknown => Icons.help_outline,
    };
  }
}

String _formatGiB(int bytes) {
  final value = bytes / localHostBytesPerGiB;
  if (value >= 10 || value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class _ModelActionButton extends StatelessWidget {
  const _ModelActionButton({
    required this.model,
    required this.pending,
    required this.onLoad,
    required this.onUnload,
  });

  final LocalManagedModel model;
  final bool pending;
  final VoidCallback onLoad;
  final VoidCallback onUnload;

  @override
  Widget build(BuildContext context) {
    if (pending) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (model.isInProgress) {
      return Text(
        'settings.local_stack_action_pending'.tr(),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final canUnload =
        model.state == LocalModelLifecycleState.loaded ||
        model.state == LocalModelLifecycleState.sleeping;
    if (canUnload) {
      return TextButton.icon(
        key: ValueKey('local-stack-unload-${model.id}'),
        onPressed: onUnload,
        icon: const Icon(Icons.stop_circle_outlined),
        label: Text('settings.local_stack_unload'.tr()),
      );
    }

    return TextButton.icon(
      key: ValueKey('local-stack-load-${model.id}'),
      onPressed: onLoad,
      icon: const Icon(Icons.play_arrow_outlined),
      label: Text('settings.local_stack_load'.tr()),
    );
  }
}

class _LocalStackMessage extends StatelessWidget {
  const _LocalStackMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalStackInlineMessage extends StatelessWidget {
  const _LocalStackInlineMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
