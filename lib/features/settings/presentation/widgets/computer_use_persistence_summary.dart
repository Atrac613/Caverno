import 'package:flutter/material.dart';

@immutable
class ComputerUsePersistenceStatusRow {
  const ComputerUsePersistenceStatusRow({
    required this.label,
    required this.isPositive,
    required this.positiveText,
    required this.negativeText,
  });

  final String label;
  final bool isPositive;
  final String positiveText;
  final String negativeText;

  String get statusText => isPositive ? positiveText : negativeText;
}

@immutable
class ComputerUsePersistenceSummaryViewModel {
  ComputerUsePersistenceSummaryViewModel({
    required this.heading,
    required Iterable<ComputerUsePersistenceStatusRow> statusRows,
    required this.activeWorkDetail,
  }) : statusRows = List.unmodifiable(statusRows);

  factory ComputerUsePersistenceSummaryViewModel.fromPersistence(
    Map<String, dynamic> persistence,
  ) {
    final updatedAt = persistence['updatedAt'];
    final activeWorkLabels = <String>[];
    final activeWork = persistence['activeWork'];
    if (activeWork is Map) {
      for (final entry in activeWork.entries) {
        if (entry.value == true) {
          activeWorkLabels.add('${entry.key}');
        }
      }
    }

    final verification = persistence['onboardingVerification'];
    final hasVerification = verification is Map;
    final verificationOk = hasVerification && verification['ok'] == true;
    final hasActiveWork = activeWorkLabels.isNotEmpty;

    return ComputerUsePersistenceSummaryViewModel(
      heading:
          'Helper status saved: ${updatedAt is String ? updatedAt : 'Unknown'}',
      statusRows: [
        ComputerUsePersistenceStatusRow(
          label: 'Saved Work',
          isPositive: !hasActiveWork,
          positiveText: 'Idle',
          negativeText: 'Active',
        ),
        ComputerUsePersistenceStatusRow(
          label: 'Saved Verify',
          isPositive: verificationOk,
          positiveText: 'Passed',
          negativeText: hasVerification ? 'Needs attention' : 'Not saved',
        ),
      ],
      activeWorkDetail:
          'Saved active work: ${hasActiveWork ? activeWorkLabels.join(', ') : 'none'}',
    );
  }

  final String heading;
  final List<ComputerUsePersistenceStatusRow> statusRows;
  final String activeWorkDetail;
}

class ComputerUsePersistenceSummary extends StatelessWidget {
  const ComputerUsePersistenceSummary({super.key, required this.viewModel});

  final ComputerUsePersistenceSummaryViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(viewModel.heading, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final row in viewModel.statusRows)
              _PersistenceStatusChip(row: row),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          viewModel.activeWorkDetail,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PersistenceStatusChip extends StatelessWidget {
  const _PersistenceStatusChip({required this.row});

  final ComputerUsePersistenceStatusRow row;

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
