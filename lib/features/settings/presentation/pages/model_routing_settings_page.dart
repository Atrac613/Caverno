import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../domain/entities/app_settings.dart';
import '../providers/model_capability_auto_probe_notifier.dart';
import '../providers/model_list_provider.dart';
import '../providers/settings_notifier.dart';

/// Base model (LL24 primary turn), per-mode primary, and per-role (LL1)
/// model routing — the single place every model choice is made.
///
/// The base model is the fallback for everything below it; the per-mode and
/// per-role assignments override it for their own calls. Secondary LLM calls
/// (memory extraction, subagents, goal suggestions, tool approval auto-review)
/// can run on a smaller, faster model than the main conversation. An empty
/// assignment falls back to the base model.
class ModelRoutingSettingsPage extends ConsumerWidget {
  const ModelRoutingSettingsPage({super.key});

  /// Resolve the model-list config for a role: the assigned mesh endpoint's
  /// base URL + key, or the primary endpoint when unassigned or not found.
  /// Roles on the same endpoint share one fetch (a configured model not in the
  /// catalog stays selectable via [_RoleModelDropdown]).
  ModelListConfig _endpointConfig(AppSettings settings, String endpointId) {
    if (endpointId.isNotEmpty) {
      for (final endpoint in settings.enabledLlmEndpoints) {
        if (endpoint.id == endpointId) {
          return ModelListConfig(
            baseUrl: endpoint.normalizedBaseUrl,
            apiKey: endpoint.apiKey,
          );
        }
      }
    }
    return _primaryConfig(settings);
  }

  ModelListConfig _primaryConfig(AppSettings settings) {
    final baseUrl = settings.baseUrl.trim().isEmpty
        ? ApiConstants.defaultBaseUrl
        : settings.baseUrl.trim();
    final apiKey = settings.apiKey.trim().isEmpty
        ? ApiConstants.defaultApiKey
        : settings.apiKey.trim();
    return ModelListConfig(baseUrl: baseUrl, apiKey: apiKey);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final isAppleProvider =
        settings.llmProvider == LlmProvider.appleFoundationModels;
    final primaryConfig = _primaryConfig(settings);

    // LL8: each role lists models from its assigned endpoint (primary when
    // unassigned), so picking a mesh endpoint surfaces that host's models.
    AsyncValue<List<String>> modelsFor(String endpointId) {
      if (isAppleProvider) {
        return const AsyncValue<List<String>>.data(<String>[]);
      }
      return ref.watch(
        modelListProvider(_endpointConfig(settings, endpointId)),
      );
    }

    final baseModel = settings.effectiveModel;
    final baseModels = isAppleProvider
        ? AsyncValue<List<String>>.data([baseModel])
        : ref.watch(modelListProvider(primaryConfig));

    return Scaffold(
      appBar: AppBar(title: Text('settings.model_routing_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'settings.model_routing_intro'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (isAppleProvider) ...[
            const SizedBox(height: 12),
            Text(
              'settings.model_routing_apple_unsupported'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _RoutingSection(
            icon: Icons.hub_outlined,
            title: 'settings.model_routing_section_base'.tr(),
            description: 'settings.model_routing_section_base_desc'.tr(),
            trailing: IconButton(
              key: const ValueKey('model-routing-refresh'),
              onPressed: isAppleProvider
                  ? null
                  : () => ref.invalidate(modelListProvider(primaryConfig)),
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'settings.model_refresh'.tr(),
              visualDensity: VisualDensity.compact,
            ),
            children: [
              _BaseModelDropdown(
                asyncModels: baseModels,
                llmProvider: settings.llmProvider,
                selectedModel: baseModel,
                onChanged: (model) async {
                  await notifier.updateModel(model);
                  unawaited(
                    ref
                        .read(modelCapabilityAutoProbeNotifierProvider.notifier)
                        .runForCurrentModel(),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _RoutingSection(
            icon: Icons.forum_outlined,
            title: 'settings.model_routing_section_modes'.tr(),
            description: 'settings.model_routing_section_modes_desc'.tr(),
            children: [
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-primary-general'),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-primary-general',
                ),
                title: 'settings.model_routing_primary_general'.tr(),
                description: 'settings.model_routing_primary_general_desc'.tr(),
                model: settings.generalPrimaryModel,
                effectiveDefaultModel: settings.effectivePrimaryModelFor(
                  AssistantMode.general,
                ),
                asyncModels: modelsFor(settings.generalPrimaryEndpointId),
                endpointId: settings.generalPrimaryEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateGeneralPrimaryModel,
                onEndpointChanged: notifier.updateGeneralPrimaryEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-primary-coding'),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-primary-coding',
                ),
                title: 'settings.model_routing_primary_coding'.tr(),
                description: 'settings.model_routing_primary_coding_desc'.tr(),
                model: settings.codingPrimaryModel,
                effectiveDefaultModel: settings.effectivePrimaryModelFor(
                  AssistantMode.coding,
                ),
                asyncModels: modelsFor(settings.codingPrimaryEndpointId),
                endpointId: settings.codingPrimaryEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateCodingPrimaryModel,
                onEndpointChanged: notifier.updateCodingPrimaryEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-primary-plan'),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-primary-plan',
                ),
                title: 'settings.model_routing_primary_plan'.tr(),
                description: 'settings.model_routing_primary_plan_desc'.tr(),
                model: settings.planPrimaryModel,
                effectiveDefaultModel: settings.effectivePrimaryModelFor(
                  AssistantMode.plan,
                ),
                asyncModels: modelsFor(settings.planPrimaryEndpointId),
                endpointId: settings.planPrimaryEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updatePlanPrimaryModel,
                onEndpointChanged: notifier.updatePlanPrimaryEndpointId,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _RoutingSection(
            icon: Icons.auto_awesome_outlined,
            title: 'settings.model_routing_section_pro'.tr(),
            description: 'settings.model_routing_section_pro_desc'.tr(),
            children: [
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-pro-reasoning'),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-pro-reasoning',
                ),
                title: 'settings.model_routing_pro_reasoning'.tr(),
                description: 'settings.model_routing_pro_reasoning_desc'.tr(),
                model: settings.proReasoningModel,
                effectiveDefaultModel: settings.effectiveProReasoningModel,
                asyncModels: modelsFor(settings.proReasoningEndpointId),
                endpointId: settings.proReasoningEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateProReasoningModel,
                onEndpointChanged: notifier.updateProReasoningEndpointId,
                extra: _ProReasoningCandidateRoutingDropdown(
                  value: settings.proReasoningCandidateRouting,
                  enabled: !isAppleProvider,
                  onChanged: notifier.updateProReasoningCandidateRouting,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _RoutingSection(
            icon: Icons.settings_suggest_outlined,
            title: 'settings.model_routing_section_background'.tr(),
            description: 'settings.model_routing_section_background_desc'.tr(),
            children: [
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-planning'),
                endpointFieldKey: const ValueKey('endpoint-routing-planning'),
                title: 'settings.model_routing_planning'.tr(),
                description: 'settings.model_routing_planning_desc'.tr(),
                model: settings.planningModel,
                effectiveDefaultModel: settings.effectivePlanningModel,
                asyncModels: modelsFor(settings.planningEndpointId),
                endpointId: settings.planningEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updatePlanningModel,
                onEndpointChanged: notifier.updatePlanningEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey(
                  'model-routing-memory-extraction',
                ),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-memory-extraction',
                ),
                title: 'settings.model_routing_memory_extraction'.tr(),
                description: 'settings.model_routing_memory_extraction_desc'
                    .tr(),
                model: settings.memoryExtractionModel,
                effectiveDefaultModel: settings.effectiveMemoryExtractionModel,
                asyncModels: modelsFor(settings.memoryExtractionEndpointId),
                endpointId: settings.memoryExtractionEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateMemoryExtractionModel,
                onEndpointChanged: notifier.updateMemoryExtractionEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-subagent'),
                endpointFieldKey: const ValueKey('endpoint-routing-subagent'),
                title: 'settings.model_routing_subagent'.tr(),
                description: 'settings.model_routing_subagent_desc'.tr(),
                model: settings.subagentModel,
                effectiveDefaultModel: settings.effectiveSubagentModel,
                asyncModels: modelsFor(settings.subagentEndpointId),
                endpointId: settings.subagentEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateSubagentModel,
                onEndpointChanged: notifier.updateSubagentEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-goal-suggestion'),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-goal-suggestion',
                ),
                title: 'settings.model_routing_goal_suggestion'.tr(),
                description: 'settings.model_routing_goal_suggestion_desc'.tr(),
                model: settings.goalSuggestionModel,
                effectiveDefaultModel: settings.effectiveGoalSuggestionModel,
                asyncModels: modelsFor(settings.goalSuggestionEndpointId),
                endpointId: settings.goalSuggestionEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateGoalSuggestionModel,
                onEndpointChanged: notifier.updateGoalSuggestionEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey('model-routing-log-analysis'),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-log-analysis',
                ),
                title: 'settings.model_routing_log_analysis'.tr(),
                description: 'settings.model_routing_log_analysis_desc'.tr(),
                model: settings.logAnalysisModel,
                effectiveDefaultModel: settings.effectiveLogAnalysisModel,
                asyncModels: modelsFor(settings.logAnalysisEndpointId),
                endpointId: settings.logAnalysisEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateLogAnalysisModel,
                onEndpointChanged: notifier.updateLogAnalysisEndpointId,
              ),
              _RoleRoute(
                modelFieldKey: const ValueKey(
                  'model-routing-approval-auto-review',
                ),
                endpointFieldKey: const ValueKey(
                  'endpoint-routing-approval-auto-review',
                ),
                title: 'settings.model_routing_approval_auto_review'.tr(),
                description: 'settings.model_routing_approval_auto_review_desc'
                    .tr(),
                model: settings.approvalAutoReviewModel,
                effectiveDefaultModel:
                    settings.effectiveApprovalAutoReviewModel,
                asyncModels: modelsFor(settings.approvalAutoReviewEndpointId),
                endpointId: settings.approvalAutoReviewEndpointId,
                endpoints: settings.enabledLlmEndpoints,
                enabled: !isAppleProvider,
                onModelChanged: notifier.updateApprovalAutoReviewModel,
                onEndpointChanged: notifier.updateApprovalAutoReviewEndpointId,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A titled group of routes. The card boundary is what separates one group of
/// roles from the next: the flat list this replaced ran every dropdown
/// together, so which endpoint belonged to which role was a guess.
class _RoutingSection extends StatelessWidget {
  const _RoutingSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            children[index],
          ],
        ],
      ),
    );
  }
}

/// One role: its name and purpose above the model/endpoint pair that serves it.
/// Grouping the two dropdowns under a single heading is what makes the pairing
/// readable — as separate flat fields they only carried generic labels.
class _RoleRoute extends StatelessWidget {
  const _RoleRoute({
    required this.modelFieldKey,
    required this.endpointFieldKey,
    required this.title,
    required this.description,
    required this.model,
    required this.effectiveDefaultModel,
    required this.asyncModels,
    required this.endpointId,
    required this.endpoints,
    required this.enabled,
    required this.onModelChanged,
    required this.onEndpointChanged,
    this.extra,
  });

  final Key modelFieldKey;
  final Key endpointFieldKey;
  final String title;
  final String description;
  final String model;
  final String effectiveDefaultModel;
  final AsyncValue<List<String>> asyncModels;
  final String endpointId;
  final List<LlmEndpoint> endpoints;
  final bool enabled;
  final ValueChanged<String> onModelChanged;
  final ValueChanged<String> onEndpointChanged;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _RoleModelDropdown(
            fieldKey: modelFieldKey,
            value: model,
            effectiveDefaultModel: effectiveDefaultModel,
            asyncModels: asyncModels,
            enabled: enabled,
            onChanged: onModelChanged,
          ),
          _RoleEndpointDropdown(
            fieldKey: endpointFieldKey,
            value: endpointId,
            endpoints: endpoints,
            enabled: enabled,
            onChanged: onEndpointChanged,
          ),
          if (extra != null) ...[const SizedBox(height: 10), extra!],
        ],
      ),
    );
  }
}

/// The model every unassigned role falls back to. Lives here rather than in
/// General settings so the app has exactly one model picker.
class _BaseModelDropdown extends StatelessWidget {
  const _BaseModelDropdown({
    required this.asyncModels,
    required this.llmProvider,
    required this.selectedModel,
    required this.onChanged,
  });

  final AsyncValue<List<String>> asyncModels;
  final LlmProvider llmProvider;
  final String selectedModel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (llmProvider == LlmProvider.appleFoundationModels) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'settings.model_name'.tr(),
          border: const OutlineInputBorder(),
          helperText: 'settings.apple_model_helper'.tr(),
        ),
        child: Text(selectedModel, overflow: TextOverflow.ellipsis),
      );
    }

    return asyncModels.when(
      data: (models) {
        final options = [...models];
        if (!options.contains(selectedModel)) {
          options.insert(0, selectedModel);
        }
        return DropdownButtonFormField<String>(
          key: const ValueKey('model-routing-base-model'),
          initialValue: selectedModel,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'settings.model_name'.tr(),
            border: const OutlineInputBorder(),
            helperText: 'settings.model_list_helper'.tr(),
          ),
          items: options
              .map(
                (model) => DropdownMenuItem<String>(
                  value: model,
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            onChanged(value.trim());
          },
        );
      },
      loading: () => InputDecorator(
        decoration: InputDecoration(
          labelText: 'settings.model_name'.tr(),
          border: const OutlineInputBorder(),
          helperText: 'settings.model_loading'.tr(),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('settings.model_loading_message'.tr())),
          ],
        ),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('model-routing-base-model'),
            initialValue: selectedModel,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'settings.model_name'.tr(),
              border: const OutlineInputBorder(),
              helperText: 'settings.model_error_helper'.tr(),
            ),
            items: [
              DropdownMenuItem<String>(
                value: selectedModel,
                child: Text(selectedModel, overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              onChanged(value.trim());
            },
          ),
          const SizedBox(height: 8),
          Text(
            'settings.model_error_message'.tr(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProReasoningCandidateRoutingDropdown extends StatelessWidget {
  const _ProReasoningCandidateRoutingDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ProReasoningCandidateRouting value;
  final bool enabled;
  final ValueChanged<ProReasoningCandidateRouting> onChanged;

  @override
  Widget build(
    BuildContext context,
  ) => DropdownButtonFormField<ProReasoningCandidateRouting>(
    key: const ValueKey('routing-pro-reasoning-candidates'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: 'settings.model_routing_pro_reasoning_candidates'.tr(),
      helperText: 'settings.model_routing_pro_reasoning_candidates_desc'.tr(),
      helperMaxLines: 3,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    items: ProReasoningCandidateRouting.values
        .map(
          (routing) => DropdownMenuItem(
            value: routing,
            child: Text(switch (routing) {
              ProReasoningCandidateRouting.mesh =>
                'settings.model_routing_pro_reasoning_candidates_mesh'.tr(),
              ProReasoningCandidateRouting.localOnly =>
                'settings.model_routing_pro_reasoning_candidates_local'.tr(),
              ProReasoningCandidateRouting.selectedOnly =>
                'settings.model_routing_pro_reasoning_candidates_selected'.tr(),
            }),
          ),
        )
        .toList(growable: false),
    onChanged: enabled
        ? (selected) {
            if (selected != null) onChanged(selected);
          }
        : null,
  );
}

/// LL8: assigns a role's secondary calls to a registered mesh endpoint. Hidden
/// when no endpoints are registered so the page is unchanged without a mesh.
class _RoleEndpointDropdown extends StatelessWidget {
  const _RoleEndpointDropdown({
    required this.fieldKey,
    required this.value,
    required this.endpoints,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String value;
  final List<LlmEndpoint> endpoints;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (endpoints.isEmpty) return const SizedBox.shrink();

    final ids = endpoints.map((endpoint) => endpoint.id).toList();
    final options = <String>[
      '',
      ...ids,
      // Keep a stale assignment selectable so it is not silently dropped.
      if (value.isNotEmpty && !ids.contains(value)) value,
    ];

    String labelFor(String id) {
      if (id.isEmpty) return 'settings.model_routing_endpoint_primary'.tr();
      for (final endpoint in endpoints) {
        if (endpoint.id == id) return endpoint.displayLabel;
      }
      return id;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String>(
        key: fieldKey,
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'settings.model_routing_endpoint_label'.tr(),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: options
            .map(
              (id) => DropdownMenuItem<String>(
                value: id,
                child: Text(labelFor(id), overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: enabled ? (selected) => onChanged(selected ?? '') : null,
      ),
    );
  }
}

class _RoleModelDropdown extends StatelessWidget {
  const _RoleModelDropdown({
    required this.fieldKey,
    required this.value,
    required this.effectiveDefaultModel,
    required this.asyncModels,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String value;
  final String effectiveDefaultModel;
  final AsyncValue<List<String>> asyncModels;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final models = asyncModels.value ?? const <String>[];
    final options = <String>[
      '',
      ...models,
      // Keep a manually configured model selectable even when the endpoint
      // does not currently list it.
      if (value.isNotEmpty && !models.contains(value)) value,
    ];

    return DropdownButtonFormField<String>(
      key: fieldKey,
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'settings.model_routing_model_label'.tr(),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: options
          .map(
            (model) => DropdownMenuItem<String>(
              value: model,
              child: Text(
                model.isEmpty
                    ? 'settings.model_routing_default_option_with_model'.tr(
                        namedArgs: {'model': effectiveDefaultModel},
                      )
                    : model,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: enabled ? (selected) => onChanged(selected ?? '') : null,
    );
  }
}
