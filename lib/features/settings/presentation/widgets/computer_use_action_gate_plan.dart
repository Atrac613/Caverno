import 'package:flutter/material.dart';

@immutable
class ComputerUseActionGateRow {
  const ComputerUseActionGateRow({
    required this.label,
    required this.status,
    required this.isPositive,
    required this.detail,
  });

  final String label;
  final String status;
  final bool isPositive;
  final String detail;
}

@immutable
class ComputerUseActionGatePlanViewModel {
  ComputerUseActionGatePlanViewModel({
    required Iterable<ComputerUseActionGateRow> rows,
  }) : rows = List.unmodifiable(rows);

  factory ComputerUseActionGatePlanViewModel.fromState({
    required bool helperInstalled,
    required bool helperRunning,
    required bool helperIpcReady,
    required bool accessibilityGranted,
    required bool screenCaptureGranted,
    required Map<String, dynamic>? captureGate,
    required Map<String, dynamic>? inputGate,
    required Map<String, dynamic>? audioGate,
    required Map<String, dynamic>? overlaySmoke,
    required Map<String, dynamic>? unsafeActionGate,
    required bool hasLiveSmokeReport,
  }) {
    final captureStatus = _status(captureGate);
    final inputStatus = _status(inputGate);
    final audioStatus = _status(audioGate);
    final overlayStatus = _status(overlaySmoke);
    final unsafeStatus = _status(unsafeActionGate);
    final helperReady = helperInstalled && helperRunning && helperIpcReady;

    return ComputerUseActionGatePlanViewModel(
      rows: [
        ComputerUseActionGateRow(
          label: 'Helper boundary',
          status: helperReady
              ? 'ready'
              : !helperInstalled || !helperRunning
              ? 'needs launch'
              : 'needs IPC',
          isPositive: helperReady,
          detail:
              'Caverno Computer Use owns Accessibility and Screen & System Audio Recording, and executes approved OS actions.',
        ),
        ComputerUseActionGateRow(
          label: 'Accessibility permission',
          status: accessibilityGranted ? 'granted' : 'blocked',
          isPositive: accessibilityGranted,
          detail: accessibilityGranted
              ? 'Input inspection and UI control can be verified.'
              : 'Grant Accessibility to Caverno Computer Use.',
        ),
        ComputerUseActionGateRow(
          label: 'Screen recording permission',
          status: screenCaptureGranted ? 'granted' : 'blocked',
          isPositive: screenCaptureGranted,
          detail: screenCaptureGranted
              ? 'Display and window capture can be verified.'
              : 'Grant Screen & System Audio Recording to Caverno Computer Use.',
        ),
        ComputerUseActionGateRow(
          label: 'Capture smoke',
          status: captureStatus,
          isPositive: captureStatus == 'ready',
          detail: captureGate != null
              ? _nextAction(captureGate)
              : 'Run live smoke after permissions are granted.',
        ),
        ComputerUseActionGateRow(
          label: 'Input smoke',
          status: inputStatus,
          isPositive: inputStatus == 'ready',
          detail: hasLiveSmokeReport
              ? _nextAction(inputGate)
              : 'Arm non-destructive input smoke only when ready to test.',
        ),
        ComputerUseActionGateRow(
          label: 'System audio smoke',
          status: audioStatus,
          isPositive: audioStatus == 'ready' || audioStatus == 'unsupported',
          detail: hasLiveSmokeReport
              ? _nextAction(audioGate)
              : 'System audio is optional and uses Screen & System Audio Recording.',
        ),
        ComputerUseActionGateRow(
          label: 'Overlay smoke',
          status: overlayStatus,
          isPositive: overlayStatus == 'ready',
          detail: hasLiveSmokeReport
              ? _nextAction(overlaySmoke)
              : 'Run overlay smoke before marking M1 onboarding ready.',
        ),
        ComputerUseActionGateRow(
          label: 'Unsafe arms',
          status: unsafeStatus,
          isPositive: unsafeStatus == 'armed',
          detail: hasLiveSmokeReport
              ? _nextAction(unsafeActionGate)
              : 'Click and text input remain separately armed.',
        ),
      ],
    );
  }

  final List<ComputerUseActionGateRow> rows;

  static String _status(Map<String, dynamic>? gate) {
    final status = gate?['status'];
    return status is String ? status : 'not run';
  }

  static String _nextAction(Map<String, dynamic>? gate) {
    final nextAction = gate?['nextAction'];
    if (nextAction is String && nextAction.isNotEmpty) {
      return nextAction;
    }
    return 'Review the latest live smoke report.';
  }
}

class ComputerUseActionGatePlan extends StatelessWidget {
  const ComputerUseActionGatePlan({super.key, required this.viewModel});

  final ComputerUseActionGatePlanViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Computer Use action plan', style: textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final row in viewModel.rows) _ActionGateRow(row: row),
          ],
        ),
      ),
    );
  }
}

class _ActionGateRow extends StatelessWidget {
  const _ActionGateRow({required this.row});

  final ComputerUseActionGateRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = row.isPositive ? colorScheme.primary : colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            row.isPositive
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.label}: ${row.status}',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(row.detail, style: textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
