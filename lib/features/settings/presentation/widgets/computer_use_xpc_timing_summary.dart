import 'package:flutter/material.dart';

@immutable
class ComputerUseXpcTimingInfoRow {
  const ComputerUseXpcTimingInfoRow({required this.label, required this.value});

  final String label;
  final String value;
}

@immutable
class ComputerUseXpcTimingSummaryViewModel {
  ComputerUseXpcTimingSummaryViewModel({
    required this.heading,
    required Iterable<ComputerUseXpcTimingInfoRow> rows,
  }) : rows = List.unmodifiable(rows);

  factory ComputerUseXpcTimingSummaryViewModel.fromSummary(
    Map<String, dynamic> summary,
  ) {
    final ready = summary['ready'] == true;
    final classification = _stringValue(summary['classification']) ?? 'unknown';
    final status = _stringValue(summary['status']) ?? 'unknown';
    final nextAction = _stringValue(summary['nextAction']);
    final recommendedActionId = _stringValue(summary['recommendedActionId']);
    final userNextAction = _stringValue(summary['userNextAction']);
    final engineeringNextAction = _stringValue(
      summary['engineeringNextAction'],
    );
    final elapsedMs = summary['elapsedMs'];
    final timeoutMs = summary['timeoutMs'];
    final currentPreferredFallbackTimeoutMs =
        summary['currentPreferredFallbackTimeoutMs'];
    final currentTimeoutHeadroomMs = summary['currentTimeoutHeadroomMs'];
    final lateElapsedMs = summary['lateResponseElapsedMs'];
    final warmupElapsedMs = summary['warmupElapsedMs'];
    final responseBeforeTimeout = summary['responseReceivedBeforeTimeout'];
    final responseAfterTimeout = summary['responseReceivedAfterTimeout'];
    final warmupResponseBeforeTimeout =
        summary['warmupResponseReceivedBeforeTimeout'];
    final fallbackSucceeded = summary['preferredFallbackSucceeded'];
    final warmupStatus = _stringValue(summary['warmupStatus']);

    return ComputerUseXpcTimingSummaryViewModel(
      heading: 'XPC timing: $classification',
      rows: [
        ComputerUseXpcTimingInfoRow(label: 'Timing status', value: status),
        ComputerUseXpcTimingInfoRow(
          label: 'Timing gate',
          value: ready ? 'ready' : 'review',
        ),
        if (elapsedMs is int)
          ComputerUseXpcTimingInfoRow(
            label: 'Elapsed',
            value: '${elapsedMs}ms',
          ),
        if (timeoutMs is int)
          ComputerUseXpcTimingInfoRow(
            label: 'Timeout budget',
            value: '${timeoutMs}ms',
          ),
        if (currentPreferredFallbackTimeoutMs is int)
          ComputerUseXpcTimingInfoRow(
            label: 'Current XPC timeout',
            value: '${currentPreferredFallbackTimeoutMs}ms',
          ),
        if (currentTimeoutHeadroomMs is int)
          ComputerUseXpcTimingInfoRow(
            label: 'Current headroom',
            value: '${currentTimeoutHeadroomMs}ms',
          ),
        if (responseBeforeTimeout is bool)
          ComputerUseXpcTimingInfoRow(
            label: 'Before timeout',
            value: responseBeforeTimeout ? 'yes' : 'no',
          ),
        if (responseAfterTimeout is bool)
          ComputerUseXpcTimingInfoRow(
            label: 'Late response',
            value: responseAfterTimeout ? 'yes' : 'no',
          ),
        if (lateElapsedMs is int)
          ComputerUseXpcTimingInfoRow(
            label: 'Late elapsed',
            value: '${lateElapsedMs}ms',
          ),
        if (warmupStatus != null)
          ComputerUseXpcTimingInfoRow(
            label: 'Warmup status',
            value: warmupStatus,
          ),
        if (warmupElapsedMs is int)
          ComputerUseXpcTimingInfoRow(
            label: 'Warmup elapsed',
            value: '${warmupElapsedMs}ms',
          ),
        if (warmupResponseBeforeTimeout is bool)
          ComputerUseXpcTimingInfoRow(
            label: 'Warmup before timeout',
            value: warmupResponseBeforeTimeout ? 'yes' : 'no',
          ),
        if (fallbackSucceeded is bool)
          ComputerUseXpcTimingInfoRow(
            label: 'Fallback',
            value: fallbackSucceeded ? 'succeeded' : 'not used',
          ),
        if (recommendedActionId != null)
          ComputerUseXpcTimingInfoRow(
            label: 'Timing action',
            value: recommendedActionId,
          ),
        if (userNextAction != null)
          ComputerUseXpcTimingInfoRow(
            label: 'User next action',
            value: userNextAction,
          ),
        if (engineeringNextAction != null)
          ComputerUseXpcTimingInfoRow(
            label: 'Engineering next action',
            value: engineeringNextAction,
          ),
        if (nextAction != null)
          ComputerUseXpcTimingInfoRow(
            label: 'Timing next action',
            value: nextAction,
          ),
      ],
    );
  }

  final String heading;
  final List<ComputerUseXpcTimingInfoRow> rows;

  static String? _stringValue(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }
}

class ComputerUseXpcTimingSummary extends StatelessWidget {
  const ComputerUseXpcTimingSummary({super.key, required this.viewModel});

  final ComputerUseXpcTimingSummaryViewModel viewModel;

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
            for (final row in viewModel.rows) _XpcTimingInfoChip(row: row),
          ],
        ),
      ],
    );
  }
}

class _XpcTimingInfoChip extends StatelessWidget {
  const _XpcTimingInfoChip({required this.row});

  final ComputerUseXpcTimingInfoRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
      label: Text('${row.label}: ${row.value}'),
    );
  }
}
