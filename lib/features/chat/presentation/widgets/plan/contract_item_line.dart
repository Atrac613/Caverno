import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';

/// One contract bullet, with the mark that says whether the plan is assuming it.
///
/// Extracted from `ContractItemListSection` when the blocking state grew an
/// action: the line is a pure function of an item and its mark and had no
/// reason to be a private class inside the list.
///
/// **The blocking state is the one the user can act on, and until 2026-09-18 it
/// was the one with nothing to act with.** `confirmMaterialAssumption` had a
/// single caller — `MaterialAssumptionConfirmationGate`, which only runs when a
/// mutation is already blocked — so the only way to clear an assumption was the
/// interrupt raised mid-turn, and dismissing that interrupt left no route back.
/// The line now carries the clarification question it was already given and had
/// been discarding, plus the confirmation, so the answer can be given where the
/// claim is read rather than only where it happens to interrupt.
class ContractItemLine extends StatelessWidget {
  const ContractItemLine({
    required this.item,
    required this.mark,
    this.onConfirmAssumption,
    super.key,
  });

  final String item;
  final ConversationContractItemProvenance? mark;

  /// Confirms [mark] on the user's behalf, when this list is showing a live
  /// spec. Null for the draft lists, which have nothing to persist onto.
  final void Function(ConversationContractItemProvenance item)?
  onConfirmAssumption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assumption = mark;
    if (assumption == null) {
      return Text('• $item', style: theme.textTheme.bodyMedium);
    }

    // Blocking is the state worth colouring: it is the only one that stops
    // work, and the user is the only one who can clear it.
    final blocks = assumption.blocksExecution;
    final confirm = onConfirmAssumption;
    final question = assumption.normalizedClarificationQuestion;
    final noteColor = blocks
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;
    final note = assumption.confirmed
        ? 'chat.contract_assumption_confirmed'.tr()
        : blocks
        ? 'chat.contract_assumption_blocking'.tr()
        : 'chat.contract_assumption'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• $item', style: theme.textTheme.bodyMedium),
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 1),
          child: Text(
            note,
            style: theme.textTheme.labelSmall?.copyWith(
              color: noteColor,
              fontWeight: blocks ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (blocks && question != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              question,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (blocks && confirm != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('confirm-assumption-${assumption.itemId}'),
              onPressed: () => confirm(assumption),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text('chat.contract_assumption_confirm_action'.tr()),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
      ],
    );
  }
}
