import 'dart:async';

import 'package:caverno/features/chat/presentation/widgets/composer_file_prepare_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failed prepare does not poison later waits', () async {
    final gate = ComposerFilePrepareGate();

    await gate.enqueue((_) async => throw StateError('prepare blew up'));

    // Send calls wait() before every message; one bad attachment must not
    // leave it throwing forever.
    await expectLater(gate.wait(), completes);
    var ran = false;
    await gate.enqueue((_) async => ran = true);
    expect(ran, isTrue);
    await expectLater(gate.wait(), completes);
  });

  test('prepares run one at a time', () async {
    final gate = ComposerFilePrepareGate();
    final first = Completer<void>();
    final running = <String>[];

    final firstDone = gate.enqueue((_) async {
      running.add('first-start');
      await first.future;
      running.add('first-end');
    });
    final secondDone = gate.enqueue((_) async => running.add('second-start'));

    await pumpEventQueue();
    expect(running, ['first-start']);

    first.complete();
    await Future.wait([firstDone, secondDone]);
    expect(running, ['first-start', 'first-end', 'second-start']);
  });

  test('only the newest epoch is current', () async {
    final gate = ComposerFilePrepareGate();
    final epochs = <int>[];

    final first = gate.enqueue((epoch) async => epochs.add(epoch));
    final second = gate.enqueue((epoch) async => epochs.add(epoch));
    await Future.wait([first, second]);

    expect(gate.isCurrent(epochs.last), isTrue);
    expect(gate.isCurrent(epochs.first), isFalse);
  });

  test('wait completes immediately when nothing is in flight', () async {
    await expectLater(ComposerFilePrepareGate().wait(), completes);
  });
}
