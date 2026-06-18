import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_settings.dart';
import '../providers/model_list_provider.dart';
import '../providers/settings_notifier.dart';

/// Per-role model routing (LL1, docs/local_llm_agent_roadmap.md).
///
/// Secondary LLM calls (memory extraction, subagents, goal suggestions, tool
/// approval auto-review) can run on a smaller, faster model than the main
/// conversation. An empty assignment falls back to the main model.
class ModelRoutingSettingsPage extends ConsumerWidget {
  const ModelRoutingSettingsPage({super.key});

  /// Resolve the model-list config for a role: the assigned mesh endpoint's
  /// base URL + key, or the primary endpoint when unassigned or not found.
  /// Roles on the same endpoint share one fetch (a configured model not in the
  /// catalog stays selectable via [_RoleModelDropdown]).
  ModelListConfig _endpointConfig(AppSettings settings, String endpointId) {
    if (endpointId.isNotEmpty) {
      for (final endpoint in settings.namedEndpoints) {
        if (endpoint.id == endpointId) {
          return ModelListConfig(
            baseUrl: endpoint.normalizedBaseUrl,
            apiKey: endpoint.apiKey,
          );
        }
      }
    }
    return ModelListConfig(baseUrl: settings.baseUrl, apiKey: settings.apiKey);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final notifier = ref.read(settingsNotifierProvider.notifier);
    final isAppleProvider =
        settings.llmProvider == LlmProvider.appleFoundationModels;

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

    return Scaffold(
      appBar: AppBar(title: Text('settings.model_routing_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 24),
          _RoleModelDropdown(
            fieldKey: const ValueKey('model-routing-memory-extraction'),
            label: 'settings.model_routing_memory_extraction'.tr(),
            helper: 'settings.model_routing_memory_extraction_desc'.tr(),
            value: settings.memoryExtractionModel,
            asyncModels: modelsFor(settings.memoryExtractionEndpointId),
            enabled: !isAppleProvider,
            onChanged: notifier.updateMemoryExtractionModel,
          ),
          _RoleEndpointDropdown(
            fieldKey: const ValueKey('endpoint-routing-memory-extraction'),
            value: settings.memoryExtractionEndpointId,
            endpoints: settings.namedEndpoints,
            enabled: !isAppleProvider,
            onChanged: notifier.updateMemoryExtractionEndpointId,
          ),
          const SizedBox(height: 16),
          _RoleModelDropdown(
            fieldKey: const ValueKey('model-routing-subagent'),
            label: 'settings.model_routing_subagent'.tr(),
            helper: 'settings.model_routing_subagent_desc'.tr(),
            value: settings.subagentModel,
            asyncModels: modelsFor(settings.subagentEndpointId),
            enabled: !isAppleProvider,
            onChanged: notifier.updateSubagentModel,
          ),
          _RoleEndpointDropdown(
            fieldKey: const ValueKey('endpoint-routing-subagent'),
            value: settings.subagentEndpointId,
            endpoints: settings.namedEndpoints,
            enabled: !isAppleProvider,
            onChanged: notifier.updateSubagentEndpointId,
          ),
          const SizedBox(height: 16),
          _RoleModelDropdown(
            fieldKey: const ValueKey('model-routing-goal-suggestion'),
            label: 'settings.model_routing_goal_suggestion'.tr(),
            helper: 'settings.model_routing_goal_suggestion_desc'.tr(),
            value: settings.goalSuggestionModel,
            asyncModels: modelsFor(settings.goalSuggestionEndpointId),
            enabled: !isAppleProvider,
            onChanged: notifier.updateGoalSuggestionModel,
          ),
          _RoleEndpointDropdown(
            fieldKey: const ValueKey('endpoint-routing-goal-suggestion'),
            value: settings.goalSuggestionEndpointId,
            endpoints: settings.namedEndpoints,
            enabled: !isAppleProvider,
            onChanged: notifier.updateGoalSuggestionEndpointId,
          ),
          const SizedBox(height: 16),
          _RoleModelDropdown(
            fieldKey: const ValueKey('model-routing-approval-auto-review'),
            label: 'settings.model_routing_approval_auto_review'.tr(),
            helper: 'settings.model_routing_approval_auto_review_desc'.tr(),
            value: settings.approvalAutoReviewModel,
            asyncModels: modelsFor(settings.approvalAutoReviewEndpointId),
            enabled: !isAppleProvider,
            onChanged: notifier.updateApprovalAutoReviewModel,
          ),
          _RoleEndpointDropdown(
            fieldKey: const ValueKey('endpoint-routing-approval-auto-review'),
            value: settings.approvalAutoReviewEndpointId,
            endpoints: settings.namedEndpoints,
            enabled: !isAppleProvider,
            onChanged: notifier.updateApprovalAutoReviewEndpointId,
          ),
        ],
      ),
    );
  }
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
  final List<NamedEndpoint> endpoints;
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
    required this.label,
    required this.helper,
    required this.value,
    required this.asyncModels,
    required this.enabled,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String helper;
  final String value;
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
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: helper,
        helperMaxLines: 3,
      ),
      items: options
          .map(
            (model) => DropdownMenuItem<String>(
              value: model,
              child: Text(
                model.isEmpty
                    ? 'settings.model_routing_default_option'.tr()
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
