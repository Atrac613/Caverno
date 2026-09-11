import 'dart:async';
import 'dart:ui' show AppExitResponse;

import '../utils/logger.dart';

/// Closes GUI persistence before the Flutter engine tears down the Dart VM.
///
/// Sparkle and `window_manager.destroy()` both quit via `NSApp.terminate`,
/// which reaches `WidgetsBindingObserver.didRequestAppExit` while isolates are
/// still alive. Drift opens SQLite on a background isolate; if that isolate is
/// killed without `AppDatabase.close`, `sqlite3_finalize` can SIGSEGV on a
/// destroyed mutex. Closing here is the cancelable-exit hook that Sparkle
/// actually waits on.
///
/// The handler waits until close finishes. A close failure returns
/// [AppExitResponse.cancel] so the running app is not left with a closed
/// database. Concurrent callers share one in-flight close.
///
/// The wait is bounded by [closeTimeout]. Drift's background-isolate close
/// sends a `terminateAll` request and awaits the isolate's answer, so a
/// statement blocked on a busy SQLite lock (a second Caverno process, a stale
/// WAL lock) never answers and the close never completes. An unbounded wait
/// there turns every exit path into a silent hang: the engine is still waiting
/// on `System.requestAppExit`, so `NSApp.terminate` is dropped and the user
/// sees a quit that does nothing. A timeout is therefore treated as "exit
/// anyway" rather than as a failure — the data SQLite already committed is
/// durable, and a crash during teardown is strictly better than an app that
/// cannot be quit.
final class CavernoAppExitHandler {
  CavernoAppExitHandler({
    Future<void> Function()? closePersistence,
    this.closeTimeout = const Duration(seconds: 5),
  }) : _closePersistence = closePersistence;

  final Future<void> Function()? _closePersistence;

  /// How long to wait for persistence to close before exiting regardless.
  final Duration closeTimeout;

  Future<AppExitResponse>? _inFlight;
  bool _closedSuccessfully = false;
  bool _exitApproved = false;

  bool get isClosed => _closedSuccessfully;

  /// Whether the handler has already decided the app may exit, either because
  /// persistence closed or because closing it timed out.
  bool get hasApprovedExit => _exitApproved;

  Future<AppExitResponse> handleExitRequest() {
    if (_exitApproved) {
      return Future<AppExitResponse>.value(AppExitResponse.exit);
    }
    return _inFlight ??= _runClose();
  }

  Future<AppExitResponse> _runClose() async {
    try {
      final closer = _closePersistence;
      if (closer != null) {
        await closer().timeout(closeTimeout);
      }
      _closedSuccessfully = true;
      _exitApproved = true;
      return AppExitResponse.exit;
    } on TimeoutException {
      appLog(
        '[Exit] persistence close did not finish within '
        '${closeTimeout.inMilliseconds} ms; exiting without it',
      );
      _exitApproved = true;
      return AppExitResponse.exit;
    } catch (error, stackTrace) {
      appLog('[Exit] persistence close failed: $error');
      appLog('[Exit] $stackTrace');
      _inFlight = null;
      return AppExitResponse.cancel;
    }
  }
}

/// Stops background maintenance while persistence closes, then restarts it if
/// the app is going to keep running.
Future<AppExitResponse> withMaintenancePausedForExit({
  required void Function() stopMaintenance,
  required void Function() startMaintenance,
  required Future<AppExitResponse> Function() requestExit,
}) async {
  stopMaintenance();
  final response = await requestExit();
  if (response == AppExitResponse.cancel) {
    startMaintenance();
  }
  return response;
}
