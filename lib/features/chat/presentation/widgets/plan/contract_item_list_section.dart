import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';
import '../../../domain/services/conversation_contract_provenance_service.dart';

/// One labelled list of contract items, with the ones the plan is *assuming*
/// marked as such.
///
/// ANA0's acceptance criterion is that a material assumption "is detected,
/// marked, and never presented as a fact". It was detected and marked in
/// provenance from PR 3b, and the plan document carries the marker as text —
/// but every surface a user actually reads projected the item back out as a
/// plain bullet, identical to a constraint the plan had been told. So the one
/// place the distinction had to survive was the one place it did not.
///
/// This replaces the page's private list builder rather than adding a panel
/// beside it: the track rule is to reuse the representation that already
/// expresses the concept, and "what is this plan assuming?" is answered by the
/// constraint list the user is already looking at.
class ContractItemListSection extends StatelessWidget {
  const ContractItemListSection({
    required this.label,
    required this.items,
    this.spec,
    this.kind,
    super.key,
  });

  final String label;
  final List<String> items;

  /// The spec the items came from, when their marks are worth showing.
  ///
  /// Optional because two callers render a *draft* list that has no provenance
  /// yet; those keep the plain bullets they had.
  final ConversationWorkflowSpec? spec;
  final ConversationContractItemKind? kind;

  static const _provenance = ConversationContractProvenanceService();

  ConversationContractItemProvenance? _markFor(String value) {
    final currentSpec = spec;
    final currentKind = kind;
    if (currentSpec == null || currentKind == null) return null;
    final itemId = _provenance.itemId(kind: currentKind, value: value);
    for (final item in currentSpec.provenance) {
      if (item.itemId == itemId && item.assumption) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedItems = items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalizedItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in normalizedItems)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _ContractItemLine(item: item, mark: _markFor(item)),
            ),
        ],
      ),
    );
  }
}

class _ContractItemLine extends StatelessWidget {
  const _ContractItemLine({required this.item, required this.mark});

  final String item;
  final ConversationContractItemProvenance? mark;

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
      ],
    );
  }
}
