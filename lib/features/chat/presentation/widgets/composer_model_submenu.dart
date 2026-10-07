import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'composer_menu_rows.dart';

/// The composer menu's model row: the endpoint's models, the load state, and a
/// refresh entry.
class ComposerModelSubmenu extends StatelessWidget {
  const ComposerModelSubmenu({
    super.key,
    required this.selectedModel,
    required this.models,
    required this.isLoading,
    required this.loadFailed,
    required this.isInert,
    required this.onSelected,
    required this.onRefresh,
  });

  final String selectedModel;
  final List<String> models;
  final bool isLoading;
  final bool loadFailed;

  /// Apple's provider has exactly one model; leave the row inert rather than
  /// opening a submenu whose only entry is the current value.
  final bool isInert;
  final ValueChanged<String> onSelected;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [...models];
    if (selectedModel.isNotEmpty && !options.contains(selectedModel)) {
      options.insert(0, selectedModel);
    }
    return SubmenuButton(
      trailingIcon: buildComposerSubmenuValue(
        theme,
        selectedModel.isEmpty ? 'message.model_unset'.tr() : selectedModel,
      ),
      menuChildren: isInert
          ? const <Widget>[]
          : [
              if (isLoading)
                MenuItemButton(
                  onPressed: null,
                  child: Text('message.model_loading'.tr()),
                )
              else if (loadFailed)
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
                  onPressed: () => onSelected(model),
                  child: Text(model, overflow: TextOverflow.ellipsis),
                ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.refresh, size: 18),
                onPressed: onRefresh,
                child: Text('message.model_refresh'.tr()),
              ),
            ],
      child: Text('message.model_menu_label'.tr()),
    );
  }
}
