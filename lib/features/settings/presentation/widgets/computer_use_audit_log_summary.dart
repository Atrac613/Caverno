import 'package:flutter/material.dart';

class ComputerUseAuditLogSummary extends StatelessWidget {
  const ComputerUseAuditLogSummary({
    super.key,
    required this.entries,
    this.maxEntries = 4,
  });

  final List<Map<String, dynamic>> entries;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries.reversed.take(maxEntries).toList();
    final textTheme = Theme.of(context).textTheme;
    if (visibleEntries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent audit entries', style: textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            'No computer-use audit entries have been recorded yet.',
            style: textTheme.bodySmall,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent audit entries', style: textTheme.labelLarge),
        const SizedBox(height: 6),
        for (final entry in visibleEntries) ...[
          _ComputerUseAuditEntryRow(entry: entry),
          if (!identical(entry, visibleEntries.last)) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _ComputerUseAuditEntryRow extends StatelessWidget {
  const _ComputerUseAuditEntryRow({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status(entry);
    final riskCategory = '${entry['riskCategory'] ?? 'unknown'}';
    final toolName = '${entry['toolName'] ?? 'unknown_tool'}';
    final approvalResult = '${entry['approvalResult'] ?? 'unknown'}';
    final transport = _optionalText(entry['transport']) ?? 'transport unknown';
    final responseCode = _optionalText(entry['responseCode']);
    final fallbackReason = _optionalText(entry['fallbackReason']);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: status.backgroundColor(theme),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: status.borderColor(theme).withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(status.icon, color: status.foregroundColor(theme), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          toolName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timestampLabel(entry['timestamp']),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$approvalResult • $riskCategory',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: status.foregroundColor(theme),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    responseCode == null
                        ? 'Transport: $transport'
                        : 'Transport: $transport • Response: $responseCode',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (fallbackReason != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Fallback: $fallbackReason',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timestampLabel(Object? value) {
    if (value is! String || value.isEmpty) {
      return 'Unknown time';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final local = parsed.toLocal().toIso8601String();
    return local.split('.').first.replaceFirst('T', ' ');
  }

  String? _optionalText(Object? value) {
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  _ComputerUseAuditStatus _status(Map<String, dynamic> entry) {
    final approvalResult = '${entry['approvalResult'] ?? 'unknown'}';
    final success = entry['success'] == true;
    if (approvalResult == 'denied') {
      return _ComputerUseAuditStatus.denied;
    }
    if (!success) {
      return _ComputerUseAuditStatus.failed;
    }
    if (approvalResult == 'approved') {
      return _ComputerUseAuditStatus.approved;
    }
    return _ComputerUseAuditStatus.recorded;
  }
}

enum _ComputerUseAuditStatus { approved, denied, failed, recorded }

extension on _ComputerUseAuditStatus {
  IconData get icon {
    return switch (this) {
      _ComputerUseAuditStatus.approved => Icons.check_circle_outline,
      _ComputerUseAuditStatus.denied => Icons.block_outlined,
      _ComputerUseAuditStatus.failed => Icons.error_outline,
      _ComputerUseAuditStatus.recorded => Icons.history_outlined,
    };
  }

  Color foregroundColor(ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (this) {
      _ComputerUseAuditStatus.approved => scheme.primary,
      _ComputerUseAuditStatus.denied => scheme.error,
      _ComputerUseAuditStatus.failed => scheme.error,
      _ComputerUseAuditStatus.recorded => scheme.secondary,
    };
  }

  Color backgroundColor(ThemeData theme) {
    final scheme = theme.colorScheme;
    return switch (this) {
      _ComputerUseAuditStatus.approved => scheme.primaryContainer,
      _ComputerUseAuditStatus.denied => scheme.errorContainer,
      _ComputerUseAuditStatus.failed => scheme.errorContainer,
      _ComputerUseAuditStatus.recorded => scheme.secondaryContainer,
    };
  }

  Color borderColor(ThemeData theme) {
    return foregroundColor(theme);
  }
}
