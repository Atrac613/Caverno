import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Marks a reply the Anabasis parent wrote.
///
/// A reader needs this because the two kinds of reply mean different things: an
/// orchestrator inspects, verifies and delegates but never edits, so "it
/// changed nothing" is expected of it and would be a failure from an ordinary
/// assistant turn.
///
/// It deliberately mirrors the participant header's shape without being one.
/// ANA0 keeps the parent's authority off surface identity, and rendering the
/// parent as a participant would let a display concern drift into the question
/// of what it is allowed to do.
class AnabasisSpeakerHeader extends StatelessWidget {
  const AnabasisSpeakerHeader({super.key});

  static const _accent = Color(0xFF7D5BA6);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: _accent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'chat.anabasis_speaker'.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Text(
              'chat.anabasis_speaker_role'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(color: _accent),
            ),
          ),
        ),
      ],
    );
  }
}
