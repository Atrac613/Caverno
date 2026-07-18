import 'package:flutter/material.dart';

import 'computer_use_debug_status_primitives.dart';

final class ComputerUseDebugAudioViewModel {
  const ComputerUseDebugAudioViewModel({
    required this.isBusy,
    required this.isRecording,
    required this.isArmed,
  });

  final bool isBusy;
  final bool isRecording;
  final bool isArmed;

  bool get canToggleArmed => !isBusy && !isRecording;
  bool get canStartRecording => !isBusy && !isRecording && isArmed;
  bool get canStopRecording => !isBusy && isRecording;
}

class ComputerUseDebugAudioCard extends StatelessWidget {
  const ComputerUseDebugAudioCard({
    required this.viewModel,
    required this.onArmedChanged,
    required this.onStartRecording,
    required this.onStopRecording,
    super.key,
  });

  final ComputerUseDebugAudioViewModel viewModel;
  final ValueChanged<bool> onArmedChanged;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ComputerUseDebugSectionTitle(
              icon: Icons.graphic_eq_outlined,
              title: 'System Audio',
              subtitle:
                  'Start and stop a ScreenCaptureKit system audio recording.',
            ),
            const SizedBox(height: 12),
            ComputerUseDebugArmSwitch(
              title: 'System Audio Armed',
              subtitle: 'Required before starting a system audio recording.',
              value: viewModel.isArmed,
              onChanged: viewModel.canToggleArmed ? onArmedChanged : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  viewModel.isRecording
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: viewModel.isRecording
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).disabledColor,
                ),
                const SizedBox(width: 8),
                Text(
                  viewModel.isRecording ? 'Recording active' : 'Not recording',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: viewModel.canStartRecording
                      ? onStartRecording
                      : null,
                  icon: const Icon(Icons.fiber_manual_record_outlined),
                  label: const Text('Start Recording'),
                ),
                FilledButton.tonalIcon(
                  onPressed: viewModel.canStopRecording
                      ? onStopRecording
                      : null,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop Recording'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
