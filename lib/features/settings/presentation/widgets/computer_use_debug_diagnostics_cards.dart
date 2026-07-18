import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'computer_use_audit_log_summary.dart';
import 'computer_use_debug_status_primitives.dart';

final class ComputerUseDebugDiagnosticsViewModel {
  ComputerUseDebugDiagnosticsViewModel({
    required this.isBusy,
    required Iterable<Map<String, dynamic>> auditEntries,
    this.lastExportPath,
  }) : auditEntries = List<Map<String, dynamic>>.unmodifiable(
         auditEntries.map((entry) => Map<String, dynamic>.unmodifiable(entry)),
       );

  final bool isBusy;
  final List<Map<String, dynamic>> auditEntries;
  final String? lastExportPath;
}

class ComputerUseDebugDiagnosticsCard extends StatelessWidget {
  const ComputerUseDebugDiagnosticsCard({
    required this.viewModel,
    required this.onRunSmokeSequence,
    required this.onCopyDiagnostics,
    required this.onExportDiagnostics,
    super.key,
  });

  final ComputerUseDebugDiagnosticsViewModel viewModel;
  final VoidCallback onRunSmokeSequence;
  final VoidCallback onCopyDiagnostics;
  final VoidCallback onExportDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ComputerUseDebugSectionTitle(
              icon: Icons.summarize_outlined,
              title: 'Diagnostics',
              subtitle:
                  'Copy or export a redacted smoke-test snapshot for debugging.',
            ),
            const SizedBox(height: 12),
            const ComputerUseDebugOnboardingNote(
              icon: Icons.privacy_tip_outlined,
              title: 'Manual Smoke Boundary',
              body:
                  'Run Smoke Sequence uses the permissions already granted to Caverno Computer Use. TCC grants and desktop actions stay user-operated; input and audio checks run only after explicit arming.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  key: const ValueKey('computer-use-run-smoke-sequence'),
                  icon: Icons.playlist_play_outlined,
                  label: 'Run Smoke Sequence',
                  onPressed: onRunSmokeSequence,
                ),
                _actionButton(
                  key: const ValueKey('computer-use-copy-diagnostics'),
                  icon: Icons.copy_outlined,
                  label: 'Copy Diagnostics',
                  onPressed: onCopyDiagnostics,
                ),
                _actionButton(
                  key: const ValueKey('computer-use-export-diagnostics'),
                  icon: Icons.file_download_outlined,
                  label: 'Export Diagnostics',
                  onPressed: onExportDiagnostics,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ComputerUseAuditLogSummary(
              entries: viewModel.auditEntries,
              maxEntries: 5,
            ),
            if (viewModel.lastExportPath != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Last export: ${viewModel.lastExportPath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonalIcon(
      key: key,
      onPressed: viewModel.isBusy ? null : onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class ComputerUseDebugResultCard extends StatelessWidget {
  const ComputerUseDebugResultCard({
    required this.lastAction,
    required this.lastResult,
    super.key,
  });

  final String lastAction;
  final String lastResult;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.data_object_outlined,
              title: 'Last Native Result',
              subtitle: lastAction,
            ),
            const SizedBox(height: 12),
            SelectableText(
              lastResult,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: kMonoFontFamily),
            ),
          ],
        ),
      ),
    );
  }
}
