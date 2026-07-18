import 'package:flutter/material.dart';

import 'computer_use_debug_status_primitives.dart';

final class ComputerUseDebugOnboardingStep {
  const ComputerUseDebugOnboardingStep({
    required this.label,
    required this.complete,
  });

  final String label;
  final bool complete;
}

final class ComputerUseDebugOnboardingViewModel {
  ComputerUseDebugOnboardingViewModel({
    required Iterable<ComputerUseDebugOnboardingStep> steps,
    required Iterable<String> xpcProductionBlockers,
    required this.xpcProductionNextAction,
  }) : steps = List<ComputerUseDebugOnboardingStep>.unmodifiable(steps),
       xpcProductionBlockers = List<String>.unmodifiable(xpcProductionBlockers);

  final List<ComputerUseDebugOnboardingStep> steps;
  final List<String> xpcProductionBlockers;
  final String xpcProductionNextAction;

  int get completedCount => steps.where((step) => step.complete).length;

  String get subtitle {
    for (final step in steps) {
      if (!step.complete) {
        return 'Next: ${step.label}';
      }
    }
    return 'All onboarding checks are complete.';
  }
}

class ComputerUseDebugOnboardingCard extends StatelessWidget {
  const ComputerUseDebugOnboardingCard({required this.viewModel, super.key});

  final ComputerUseDebugOnboardingViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ComputerUseDebugSectionTitle(
              icon: Icons.fact_check_outlined,
              title: 'Computer Use Onboarding',
              subtitle: viewModel.subtitle,
            ),
            const SizedBox(height: 12),
            ComputerUseDebugOnboardingProgressRow(
              completed: viewModel.completedCount,
              total: viewModel.steps.length,
            ),
            const SizedBox(height: 12),
            for (final step in viewModel.steps)
              ComputerUseDebugOnboardingStepRow(
                label: step.label,
                complete: step.complete,
              ),
            if (viewModel.xpcProductionBlockers.isEmpty) ...[
              const SizedBox(height: 12),
              ComputerUseDebugOnboardingNote(
                icon: Icons.verified_outlined,
                title: 'XPC Production Ready',
                body: viewModel.xpcProductionNextAction,
              ),
            ] else ...[
              const SizedBox(height: 12),
              ComputerUseDebugOnboardingNote(
                icon: Icons.route_outlined,
                title: 'XPC Production Blocker',
                body: viewModel.xpcProductionBlockers.join(', '),
              ),
              const SizedBox(height: 8),
              ComputerUseDebugOnboardingNote(
                icon: Icons.next_plan_outlined,
                title: 'XPC Next Action',
                body: viewModel.xpcProductionNextAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
