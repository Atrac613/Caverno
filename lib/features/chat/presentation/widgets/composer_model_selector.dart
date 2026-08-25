import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/utils/logger.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/model_capability_auto_probe_notifier.dart';
import '../../../settings/presentation/providers/model_list_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import 'composer_control_chip.dart';
import 'composer_menu_rows.dart';
import 'message_input_control_labels.dart';

/// Composer chip that carries the two settings describing *how* the next turn
/// is answered: which model runs it, and how much reasoning effort it is asked
/// for. They travel together because they are read together — "which model, at
/// what effort" is one decision — so the chip shows both and one menu edits
/// both, instead of a model chip next to an unlabelled brain icon.
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
  });

  /// False while a reply is running, matching the other composer controls.
  final bool enabled;

  /// Narrow-composer form: a shorter model id and no effort label. The chip
  /// shares a fixed right-hand group with the send controls, so on a phone it
  /// gives up the second value rather than pushing them off screen. The effort
  /// is still one tap away, in the menu.
  final bool compact;

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
    final selectedModel = settings.effectiveModel.trim();
    final modelLabel = selectedModel.isEmpty
        ? 'message.model_unset'.tr()
        : selectedModel;
    final effortLabel = messageInputReasoningEffortLabel(
      settings.reasoningEffort,
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
            _buildModelSubmenu(theme, settings, selectedModel),
            _buildEffortSubmenu(theme, settings, effortLabel),
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

  Widget _buildModelSubmenu(
    ThemeData theme,
    AppSettings settings,
    String selectedModel,
  ) {
    final isApple = settings.llmProvider == LlmProvider.appleFoundationModels;
    final options = [..._models];
    if (selectedModel.isNotEmpty && !options.contains(selectedModel)) {
      options.insert(0, selectedModel);
    }
    return SubmenuButton(
      trailingIcon: buildComposerSubmenuValue(
        theme,
        selectedModel.isEmpty ? 'message.model_unset'.tr() : selectedModel,
      ),
      // Apple's provider has exactly one model; leave the row inert rather than
      // opening a submenu whose only entry is the current value.
      menuChildren: isApple
          ? const <Widget>[]
          : [
              if (_isLoadingModels)
                MenuItemButton(
                  onPressed: null,
                  child: Text('message.model_loading'.tr()),
                )
              else if (_modelsFailed)
                MenuItemButton(
                  onPressed: null,
                  child: Text(
                    'message.model_load_failed'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              for (final model in options)
                MenuItemButton(
                  leadingIcon: buildComposerMenuCheckIcon(
                    theme,
                    model == selectedModel,
                  ),
                  onPressed: () => unawaited(_selectModel(model, settings)),
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.refresh, size: 18),
                onPressed: () => unawaited(_reloadModels(settings)),
                child: Text('message.model_refresh'.tr()),
              ),
            ],
      child: Text('message.model_menu_label'.tr()),
    );
  }

  Widget _buildEffortSubmenu(
    ThemeData theme,
    AppSettings settings,
    String effortLabel,
  ) {
    return SubmenuButton(
      trailingIcon: buildComposerSubmenuValue(theme, effortLabel),
      menuChildren: [
        for (final value in ReasoningEffortPreference.values)
          MenuItemButton(
            leadingIcon: buildComposerMenuCheckIcon(
              theme,
              settings.reasoningEffort == value,
            ),
            onPressed: () => unawaited(
              ref
                  .read(settingsNotifierProvider.notifier)
                  .updateReasoningEffort(value),
            ),
            child: Text(messageInputReasoningEffortLabel(value)),
          ),
      ],
      child: Text('message.reasoning_effort_menu_label'.tr()),
    );
  }

  /// Model list config for the picker.
  ///
  /// Keyed identically to the one the chat header uses for the token-usage
  /// indicator, so the two share a cached `/v1/models` fetch rather than
  /// issuing separate ones.
  ModelListConfig _modelListConfig(AppSettings settings) {
    return ModelListConfig(
      baseUrl: settings.baseUrl.trim().isEmpty
          ? ApiConstants.defaultBaseUrl
          : settings.baseUrl.trim(),
      apiKey: settings.apiKey.trim().isEmpty
          ? ApiConstants.defaultApiKey
          : settings.apiKey.trim(),
      selectedModelId: settings.model.trim(),
    );
  }

  /// Loads the endpoint's model list into [_models]. A failure leaves the menu
  /// open carrying the current model plus the retry entry, so an unreachable
  /// endpoint never turns the picker into a dead control.
  Future<void> _loadModels(AppSettings settings) async {
    if (_isLoadingModels) return;
    if (settings.llmProvider == LlmProvider.appleFoundationModels) return;
    setState(() {
      _isLoadingModels = true;
      _modelsFailed = false;
    });
    final config = _modelListConfig(settings);
    var models = const <String>[];
    var failed = false;
    // Hold a listener while the request is in flight: the catalog provider is
    // autoDispose, and a bare read would let it drop mid-fetch.
    final subscription = ref.listenManual(modelListProvider(config), (_, _) {});
    try {
      models = await ref.read(modelListProvider(config).future);
    } on Object catch (error) {
      failed = true;
      appDebugPrint('Composer model list failed to load: $error');
    } finally {
      subscription.close();
    }
    if (!mounted) return;
    setState(() {
      _models = models;
      _modelsFailed = failed;
      _isLoadingModels = false;
    });
  }

  Future<void> _reloadModels(AppSettings settings) async {
    ref.invalidate(modelCatalogProvider(_modelListConfig(settings)));
    await _loadModels(settings);
  }

  Future<void> _selectModel(String model, AppSettings settings) async {
    _menuController.close();
    final selected = model.trim();
    if (selected.isEmpty) return;
    if (selected == settings.effectiveModel.trim()) return;
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
}
