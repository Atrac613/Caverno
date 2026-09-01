import 'package:caverno/features/chat/presentation/widgets/composer_dropped_attachment_intake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the composer/page pair: the page holds a pending drop, the child
/// claims it from `didUpdateWidget`, and the "handled" callback clears state on
/// the page. Calling that callback synchronously marks an ancestor dirty while
/// it is building, which is a framework assertion on every drop.
class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int? pending;
  int cleared = 0;

  void drop(int id) => setState(() => pending = id);

  @override
  Widget build(BuildContext context) => _Composer(
    pending: pending,
    onHandled: () {
      if (!mounted) return;
      setState(() {
        pending = null;
        cleared += 1;
      });
    },
  );
}

class _Composer extends StatefulWidget {
  const _Composer({this.pending, this.onHandled});

  final int? pending;
  final VoidCallback? onHandled;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final intake = DroppedAttachmentIntake();
  final taken = <int>[];

  void _handle() {
    final pending = widget.pending;
    if (pending == null || !intake.take(pending, widget.onHandled)) return;
    taken.add(pending);
  }

  @override
  void initState() {
    super.initState();
    _handle();
  }

  @override
  void didUpdateWidget(_Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handle();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  testWidgets('claiming a drop does not rebuild the page during its build', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _Page()));

    tester.state<_PageState>(find.byType(_Page)).drop(1);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.state<_PageState>(find.byType(_Page)).cleared, 1);
    expect(tester.state<_ComposerState>(find.byType(_Composer)).taken, [1]);
  });

  testWidgets('a second drop of a new id is claimed again', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Page()));
    final page = tester.state<_PageState>(find.byType(_Page));

    page.drop(1);
    await tester.pump();
    await tester.pump();
    page.drop(2);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.state<_ComposerState>(find.byType(_Composer)).taken, [1, 2]);
  });

  test('the same id is claimed only once', () {
    final intake = DroppedAttachmentIntake();
    var handled = 0;

    expect(intake.take(7, () => handled++), isTrue);
    expect(intake.take(7, () => handled++), isFalse);
    expect(intake.isCurrent(7), isTrue);
    expect(intake.isCurrent(8), isFalse);
  });
}
