import '../../../../core/utils/logger.dart';

/// Serializes composer file prepares so Send can wait for an in-flight drop.
///
/// Chained rather than latest-wins: two prepares would each hold a whole PDF
/// in a parse isolate, and only the newer one's result is ever applied. The
/// chain is error-guarded for the same reason `PythonScriptRuntime._jobQueue`
/// is — a failed prepare left on the tail would make every later [wait]
/// rethrow, which is Send and Interrupt broken until the composer remounts.
class ComposerFilePrepareGate {
  Future<void> _tail = Future<void>.value();
  int _epoch = 0;

  Future<void> wait() => _tail;

  Future<void> enqueue(Future<void> Function(int epoch) work) {
    final epoch = ++_epoch;
    _tail = _tail
        .then((_) => work(epoch))
        .then(
          (_) {},
          onError: (Object error) {
            appDebugPrint('Composer file prepare failed: $error');
          },
        );
    return _tail;
  }

  bool isCurrent(int epoch) => epoch == _epoch;
}
