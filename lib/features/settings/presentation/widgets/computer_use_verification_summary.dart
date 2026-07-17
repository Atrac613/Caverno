import 'package:flutter/material.dart';

@immutable
class ComputerUseVerificationStatusRow {
  const ComputerUseVerificationStatusRow({
    required this.label,
    required this.isPositive,
    required this.statusText,
  });

  final String label;
  final bool isPositive;
  final String statusText;
}

@immutable
class ComputerUseVerificationSummaryViewModel {
  ComputerUseVerificationSummaryViewModel({
    required this.heading,
    required this.showSteps,
    required Iterable<ComputerUseVerificationStatusRow> statusRows,
  }) : statusRows = List.unmodifiable(statusRows);

  factory ComputerUseVerificationSummaryViewModel.fromVerification(
    Map<String, dynamic> verification,
  ) {
    final generatedAt = verification['generatedAt'];
    final headingValue =
        verification['summary'] ??
        (generatedAt is String ? generatedAt : 'Unknown');
    final steps = verification['steps'];
    final statusRows = <ComputerUseVerificationStatusRow>[];
    if (steps is List) {
      for (final step in steps) {
        if (step is Map) {
          final isPositive = step['ok'] == true;
          statusRows.add(
            ComputerUseVerificationStatusRow(
              label: '${step['label'] ?? step['id'] ?? 'Step'}',
              isPositive: isPositive,
              statusText: isPositive ? 'Done' : '${step['status'] ?? 'Failed'}',
            ),
          );
        }
      }
    }

    return ComputerUseVerificationSummaryViewModel(
      heading: 'Last Verify: $headingValue',
      showSteps: steps is List,
      statusRows: statusRows,
    );
  }

  final String heading;
  final bool showSteps;
  final List<ComputerUseVerificationStatusRow> statusRows;
}

class ComputerUseVerificationSummary extends StatelessWidget {
  const ComputerUseVerificationSummary({super.key, required this.viewModel});

  final ComputerUseVerificationSummaryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(viewModel.heading, style: Theme.of(context).textTheme.bodySmall),
        if (viewModel.showSteps) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final row in viewModel.statusRows)
                _VerificationStatusChip(row: row),
            ],
          ),
        ],
      ],
    );
  }
}

class _VerificationStatusChip extends StatelessWidget {
  const _VerificationStatusChip({required this.row});

  final ComputerUseVerificationStatusRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = row.isPositive ? colorScheme.primary : colorScheme.outline;
    return Chip(
      avatar: Icon(
        row.isPositive
            ? Icons.check_circle_outline
            : Icons.radio_button_unchecked,
        size: 18,
        color: color,
      ),
      label: Text('${row.label}: ${row.statusText}'),
    );
  }
}
