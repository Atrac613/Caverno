import 'package:flutter/material.dart';

import 'computer_use_debug_image_preview.dart';
import 'computer_use_debug_status_primitives.dart';

final class ComputerUseDebugWindowItem {
  const ComputerUseDebugWindowItem({
    required this.id,
    required this.label,
    required this.boundsLabel,
  });

  final int id;
  final String label;
  final String boundsLabel;
}

final class ComputerUseDebugWindowViewModel {
  ComputerUseDebugWindowViewModel({
    required this.isBusy,
    required Iterable<ComputerUseDebugWindowItem> windows,
    required this.selectedWindowId,
    required this.snapshot,
    required this.isPreviewActive,
  }) : windows = List<ComputerUseDebugWindowItem>.unmodifiable(windows);

  final bool isBusy;
  final List<ComputerUseDebugWindowItem> windows;
  final int? selectedWindowId;
  final ComputerUseDebugImageSnapshot? snapshot;
  final bool isPreviewActive;

  bool get canListWindows => !isBusy;
  bool get canFocusSelected => !isBusy && selectedWindowId != null;
  bool get canCaptureSelected => !isBusy && selectedWindowId != null;
  bool get canSelectWindow => !isBusy;

  ComputerUseDebugWindowItem? get selectedWindow {
    final selectedId = selectedWindowId;
    if (selectedId == null) {
      return null;
    }
    for (final window in windows) {
      if (window.id == selectedId) {
        return window;
      }
    }
    return null;
  }
}

class ComputerUseDebugWindowTargetingCard extends StatelessWidget {
  const ComputerUseDebugWindowTargetingCard({
    required this.viewModel,
    required this.onListWindows,
    required this.onFocusSelected,
    required this.onCaptureSelected,
    required this.onSelectedWindowChanged,
    required this.onPointSelected,
    super.key,
  });

  final ComputerUseDebugWindowViewModel viewModel;
  final VoidCallback onListWindows;
  final VoidCallback onFocusSelected;
  final VoidCallback onCaptureSelected;
  final ValueChanged<int?> onSelectedWindowChanged;
  final ValueChanged<ComputerUseDebugImagePoint> onPointSelected;

  @override
  Widget build(BuildContext context) {
    final selectedWindow = viewModel.selectedWindow;
    final snapshot = viewModel.snapshot;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ComputerUseDebugSectionTitle(
              icon: Icons.web_asset_outlined,
              title: 'Window Targeting',
              subtitle:
                  'List visible windows, focus one, and capture a window-relative screenshot.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: viewModel.canListWindows ? onListWindows : null,
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('List Windows'),
                ),
                FilledButton.tonalIcon(
                  onPressed: viewModel.canFocusSelected
                      ? onFocusSelected
                      : null,
                  icon: const Icon(Icons.filter_center_focus_outlined),
                  label: const Text('Focus Selected'),
                ),
                FilledButton.tonalIcon(
                  onPressed: viewModel.canCaptureSelected
                      ? onCaptureSelected
                      : null,
                  icon: const Icon(Icons.crop_free_outlined),
                  label: const Text('Capture Selected'),
                ),
              ],
            ),
            if (viewModel.windows.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(viewModel.selectedWindowId),
                initialValue: viewModel.selectedWindowId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Selected window',
                  border: OutlineInputBorder(),
                ),
                items: viewModel.windows
                    .map(
                      (window) => DropdownMenuItem<int>(
                        value: window.id,
                        child: Text(
                          window.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: viewModel.canSelectWindow
                    ? onSelectedWindowChanged
                    : null,
              ),
            ],
            if (selectedWindow != null) ...[
              const SizedBox(height: 8),
              Text(
                selectedWindow.boundsLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (snapshot != null) ...[
              const SizedBox(height: 12),
              ComputerUseDebugImagePreview(
                key: const ValueKey('computer-use-window-preview'),
                snapshot: snapshot,
                active: viewModel.isPreviewActive,
                tapAreaKey: const ValueKey(
                  'computer-use-window-preview-tap-area',
                ),
                onPointSelected: onPointSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
