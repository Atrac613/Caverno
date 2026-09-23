import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import 'composer_control_chip.dart';
import 'composer_menu_rows.dart';
import 'composer_model_catalog.dart';
import 'composer_model_selection.dart';
import 'composer_model_submenu.dart';
import 'message_input_control_labels.dart';

export 'composer_model_selection.dart';

/// Composer chip for model selection, reasoning effort, and template thinking.
/// The chip shows the model and effort; its menu also exposes the independent
/// thinking preference with automatic, enabled, and disabled states.
///
/// Apple Foundation Models pins its own model id, so the model row is then a
/// read-only value.
///
/// The endpoint's model list is fetched when the menu is opened, not while the
/// composer builds: rendering a chat must not cost a `/v1/models` round trip.
class ComposerModelSelector extends ConsumerStatefulWidget {
  const ComposerModelSelector({
    super.key,
    required this.enabled,
    this.compact = false,
    this.selection,
    this.modelLoader,
    this.onSelectionChanged,
  });

  /// False while a reply is running, matching the other composer controls.
  final bool enabled;

  /// Narrow-composer form: a shorter model id and no effort label. The chip
  /// shares a fixed right-hand group with the send controls, so on a phone it
  /// gives up the second value rather than pushing them off screen. The effort
  /// is still one tap away, in the menu.
  final bool compact;

  /// Optional values supplied by a remote composer. When omitted, the local
  /// settings provider remains the source of truth.
  final ComposerModelSelection? selection;

  /// Optional model-list source. Remote Coding uses the desktop endpoint;
  /// ordinary chat uses the local model-list provider.
  final ComposerModelListLoader? modelLoader;

  /// Optional remote update handler. When present, menu changes are sent to
  /// that surface instead of being persisted only in local settings.
  final ComposerModelSelectionChanged? onSelectionChanged;

  @override
  ConsumerState<ComposerModelSelector> createState() =>
      _ComposerModelSelectorState();
}

class _ComposerModelSelectorState extends ConsumerState<ComposerModelSelector> {
  final MenuController _menuController = MenuController();

  /// Model ids from the last load, so the submenu can be rebuilt in place when
  /// the fetch lands while the menu is already open.
  List<String> _models = const <String>[];
  bool _isLoadingModels = false;
  bool _modelsFailed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsNotifierProvider);
    final selection =
        widget.selection ?? ComposerModelSelection.fromSettings(settings);
    final selectedModel = selection.model.trim();
    final modelLabel = selectedModel.isEmpty
        ? 'message.model_unset'.tr()
        : selectedModel;
    final effortLabel = messageInputReasoningEffortLabel(
      selection.reasoningEffort,
    );

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.6,
      child: Tooltip(
        message: 'message.model_effort_tooltip'.tr(
          namedArgs: {'model': modelLabel, 'effort': effortLabel},
        ),
        child: MenuAnchor(
          controller: _menuController,
          onOpen: () => unawaited(_loadModels(settings)),
          menuChildren: [
            ComposerModelSubmenu(
              selectedModel: selectedModel,
              models: _models,
              isLoading: _isLoadingModels,
              loadFailed: _modelsFailed,
              isInert:
                  widget.modelLoader == null &&
                  settings.llmProvider == LlmProvider.appleFoundationModels,
              onSelected: (model) => unawaited(_selectModel(model, settings)),
              onRefresh: () => unawaited(_reloadModels(settings)),
            ),
            ComposerChoiceSubmenu<ReasoningEffortPreference>(
              title: Text('message.reasoning_effort_menu_label'.tr()),
              values: ReasoningEffortPreference.values,
              selected: selection.reasoningEffort,
              labelOf: messageInputReasoningEffortLabel,
              onSelected: (value) =>
                  unawaited(_selectReasoningEffort(value, selection)),
            ),
            ComposerChoiceSubmenu<bool?>(
              title: Text('message.thinking_menu_label'.tr()),
              values: const <bool?>[null, true, false],
              selected: selection.enableThinking,
              labelOf: messageInputEnableThinkingLabel,
              onSelected: (value) =>
                  unawaited(_selectEnableThinking(value, selection)),
            ),
          ],
          builder: (context, controller, _) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.enabled
                ? () =>
                      controller.isOpen ? controller.close() : controller.open()
                : null,
            child: buildComposerControlChip(
              theme: theme,
              icon: Icons.memory_outlined,
              label: modelLabel,
              secondaryLabel: widget.compact ? null : effortLabel,
              key: const ValueKey('composer-model-chip'),
              maxLabelWidth: widget.compact ? 96 : 160,
            ),
          ),
        ),
      ),
    );
  }

  /// Loads the endpoint's model list into [_models]. A failure leaves the menu
  /// open carrying the current model plus the retry entry, so an unreachable
  /// endpoint never turns the picker into a dead control.
  Future<void> _loadModels(AppSettings settings) async {
    if (_isLoadingModels) return;
    if (widget.modelLoader == null &&
        settings.llmProvider == LlmProvider.appleFoundationModels) {
      return;
    }
    setState(() {
      _isLoadingModels = true;
      _modelsFailed = false;
    });
    var models = const <String>[];
    var failed = false;
    try {
      models = widget.modelLoader != null
          ? await widget.modelLoader!()
          : await ComposerModelCatalog.load(ref, settings);
    } on Object catch (error) {
      failed = true;
      appDebugPrint('Composer model list failed to load: $error');
    }
    if (!mounted) return;
    setState(() {
      _models = models;
      _modelsFailed = failed;
      _isLoadingModels = false;
    });
  }

  Future<void> _reloadModels(AppSettings settings) async {
    if (widget.modelLoader == null) {
      ComposerModelCatalog.invalidate(ref, settings);
    }
    await _loadModels(settings);
  }

  Future<void> _selectModel(String model, AppSettings settings) async {
    _menuController.close();
    final selected = model.trim();
    if (selected.isEmpty) return;
    final currentSelection =
        widget.selection ?? ComposerModelSelection.fromSettings(settings);
    if (selected == currentSelection.model.trim()) return;
    if (widget.onSelectionChanged != null) {
      await widget.onSelectionChanged!(
        currentSelection.copyWith(model: selected),
      );
      return;
    }
    await ref.read(settingsNotifierProvider.notifier).updateModel(selected);
    if (!mounted) return;
    // Same follow-up the settings picker runs, so capability-derived behavior
    // (tool support, vision, context window) matches the model now in use. It
    // is a no-op for a model already profiled. A probe failure must not reach
    // the user as an error from the composer: the switch itself succeeded.
    unawaited(
      Future<void>(
        () => ref
            .read(modelCapabilityAutoProbeNotifierProvider.notifier)
            .runForCurrentModel(),
      ).catchError((Object error) {
        appDebugPrint(
          'Model capability probe failed after model switch: $error',
        );
      }),
    );
  }

  Future<void> _selectReasoningEffort(
    ReasoningEffortPreference value,
    ComposerModelSelection currentSelection,
  ) async {
    if (value == currentSelection.reasoningEffort) return;
    if (widget.onSelectionChanged != null) {
      await widget.onSelectionChanged!(
        currentSelection.copyWith(reasoningEffort: value),
      );
      return;
    }
    await ref
        .read(settingsNotifierProvider.notifier)
        .updateReasoningEffort(value);
  }

  Future<void> _selectEnableThinking(
    bool? value,
    ComposerModelSelection currentSelection,
  ) async {
    if (value == currentSelection.enableThinking) return;
    if (widget.onSelectionChanged != null) {
      await widget.onSelectionChanged!(
        value == null
            ? currentSelection.copyWith(clearEnableThinking: true)
            : currentSelection.copyWith(enableThinking: value),
      );
      return;
    }
    await ref
        .read(settingsNotifierProvider.notifier)
        .updateEnableThinking(value);
  }
}
