import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/duration_format.dart';

/// Anything older than this is a stale or synthetic timestamp rather than a
/// live turn, so the row drops the number instead of printing nonsense.
const Duration _implausibleTurn = Duration(hours: 24);

/// `14m 8s · Running tools…` — the in-bubble replacement for the streaming
/// spinner.
///
/// Pure props. The start time is the assistant message's own timestamp, so the
/// row is correct again after the ListView destroys and rebuilds it on scroll;
/// nothing may be captured in [State.initState].
class AssistantTurnStatusRow extends StatefulWidget {
  const AssistantTurnStatusRow({
    super.key,
    required this.startedAt,
    required this.label,
    this.now = DateTime.now,
  });

  final DateTime startedAt;

  /// Already-resolved status text, e.g. `Running read_file…`.
  final String label;

  /// Wall clock, injectable for tests. `testWidgets` fakes timers but not
  /// `DateTime.now()`, so a test that pumps forward would otherwise never see
  /// the elapsed value move.
  final DateTime Function() now;

  @override
  State<AssistantTurnStatusRow> createState() => _AssistantTurnStatusRowState();
}

class _AssistantTurnStatusRowState extends State<AssistantTurnStatusRow> {
  Timer? _tick;
  late int _shownSeconds;

  @override
  void initState() {
    super.initState();
    _shownSeconds = _elapsed().inSeconds;
    // One rebuild per second, rather than the repeating AnimationController the
    // old spinner ran, which forced a frame every vsync for the whole turn.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void didUpdateWidget(covariant AssistantTurnStatusRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _shownSeconds = _elapsed().inSeconds;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration _elapsed() => widget.now().difference(widget.startedAt);

  void _onTick() {
    final seconds = _elapsed().inSeconds;
    if (!mounted || seconds == _shownSeconds) return;
    setState(() => _shownSeconds = seconds);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = _elapsed();
    final showElapsed =
        !elapsed.isNegative &&
        elapsed.inSeconds >= 1 &&
        elapsed < _implausibleTurn;

    return Text(
      showElapsed
          ? '${formatCompactDuration(elapsed)} · ${widget.label}'
          : widget.label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: context.appColors.textMuted,
      ),
    );
  }
}
