import 'package:flutter/material.dart';

import 'computer_use_debug_image_preview.dart';
import 'computer_use_debug_status_primitives.dart';

final class ComputerUseDebugDisplayScreenshotViewModel {
  const ComputerUseDebugDisplayScreenshotViewModel({
    required this.isBusy,
    required this.snapshot,
    required this.isPreviewActive,
  });

  final bool isBusy;
  final ComputerUseDebugImageSnapshot? snapshot;
  final bool isPreviewActive;

  bool get canCapture => !isBusy;
}

class ComputerUseDebugDisplayScreenshotCard extends StatelessWidget {
  const ComputerUseDebugDisplayScreenshotCard({
    required this.viewModel,
    required this.maxWidthController,
    required this.onCapture,
    required this.onPointSelected,
    super.key,
  });

  final ComputerUseDebugDisplayScreenshotViewModel viewModel;
  final TextEditingController maxWidthController;
  final VoidCallback onCapture;
  final ValueChanged<ComputerUseDebugImagePoint> onPointSelected;

  @override
  Widget build(BuildContext context) {
    final snapshot = viewModel.snapshot;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ComputerUseDebugSectionTitle(
              icon: Icons.desktop_mac_outlined,
              title: 'Display Screenshot',
              subtitle: 'Capture the main display and preview the PNG payload.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: maxWidthController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max image width',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: viewModel.canCapture ? onCapture : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Capture Display'),
            ),
            if (snapshot != null) ...[
              const SizedBox(height: 12),
              ComputerUseDebugImagePreview(
                key: const ValueKey('computer-use-display-preview'),
                snapshot: snapshot,
                active: viewModel.isPreviewActive,
                tapAreaKey: const ValueKey(
                  'computer-use-display-preview-tap-area',
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
