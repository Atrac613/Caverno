import 'package:flutter/material.dart';

import 'computer_use_debug_status_primitives.dart';

final class ComputerUseDebugInputViewModel {
  const ComputerUseDebugInputViewModel({
    required this.isBusy,
    required this.isArmed,
    required this.hasCoordinateTarget,
    required this.coordinateTargetLabel,
  });

  final bool isBusy;
  final bool isArmed;
  final bool hasCoordinateTarget;
  final String coordinateTargetLabel;

  bool get canToggleArmed => !isBusy;
  bool get canMovePointer => !isBusy && isArmed && hasCoordinateTarget;
  bool get canClickPoint => !isBusy && isArmed && hasCoordinateTarget;
  bool get canTypeText => !isBusy && isArmed;
}

class ComputerUseDebugInputCard extends StatelessWidget {
  const ComputerUseDebugInputCard({
    required this.viewModel,
    required this.xController,
    required this.yController,
    required this.textController,
    required this.onArmedChanged,
    required this.onMovePointer,
    required this.onClickPoint,
    required this.onTypeText,
    super.key,
  });

  final ComputerUseDebugInputViewModel viewModel;
  final TextEditingController xController;
  final TextEditingController yController;
  final TextEditingController textController;
  final ValueChanged<bool> onArmedChanged;
  final VoidCallback onMovePointer;
  final VoidCallback onClickPoint;
  final VoidCallback onTypeText;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ComputerUseDebugSectionTitle(
              icon: Icons.ads_click_outlined,
              title: 'Input Smoke Checks',
              subtitle:
                  'Run explicit input events against the selected window or display coordinates.',
            ),
            const SizedBox(height: 12),
            ComputerUseDebugArmSwitch(
              title: 'Input Events Armed',
              subtitle:
                  'Required before moving the pointer, clicking, or typing text.',
              value: viewModel.isArmed,
              onChanged: viewModel.canToggleArmed ? onArmedChanged : null,
            ),
            const SizedBox(height: 12),
            ComputerUseDebugCoordinateTargetRow(
              label: viewModel.coordinateTargetLabel,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: xController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'X',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: yController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Y',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Text to type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: viewModel.canMovePointer ? onMovePointer : null,
                  icon: const Icon(Icons.mouse_outlined),
                  label: const Text('Move Pointer'),
                ),
                FilledButton.tonalIcon(
                  onPressed: viewModel.canClickPoint ? onClickPoint : null,
                  icon: const Icon(Icons.touch_app_outlined),
                  label: const Text('Click Point'),
                ),
                FilledButton.tonalIcon(
                  onPressed: viewModel.canTypeText ? onTypeText : null,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('Type Text'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
