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
final class CavernoAppExitHandler {
  CavernoAppExitHandler({Future<void> Function()? closePersistence})
    : _closePersistence = closePersistence;

  final Future<void> Function()? _closePersistence;
  Future<AppExitResponse>? _inFlight;
  bool _closedSuccessfully = false;

  bool get isClosed => _closedSuccessfully;

  Future<AppExitResponse> handleExitRequest() {
    if (_closedSuccessfully) {
      return Future<AppExitResponse>.value(AppExitResponse.exit);
    }
    return _inFlight ??= _runClose();
  }

  Future<AppExitResponse> _runClose() async {
    try {
      final closer = _closePersistence;
      if (closer != null) {
        await closer();
      }
      _closedSuccessfully = true;
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
