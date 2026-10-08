import 'dart:io';

import 'package:flutter/foundation.dart';

import '../security/sensitive_data_redactor.dart';
import '../security/sensitive_file_permissions.dart';

/// File sink for [appLog], at `~/.caverno/app_logs/<date>.log`.
///
/// Exists because the interesting failures are the ones where the app stops
/// making progress: `debugPrint` output only survives while a `flutter run`
/// terminal is attached, so a stall reproduced outside one leaves no trace and
/// the next session can only guess. Writes are synchronous and unbuffered for
/// that reason — a hung isolate must still have its last lines on disk.
///
/// Available in release builds behind the Logging settings toggle, which
/// defaults off: a fresh install writes nothing until the user opts in.
/// In-memory default follows the build mode so release never writes before
/// settings load.
///
/// Never throws: a sink that cannot write disables itself for the process
/// rather than turning logging into a second failure.
class AppLogFile {
  AppLogFile._({Directory? directoryOverride, DateTime Function()? clock})
    : _directoryOverride = directoryOverride,
      _clock = clock ?? DateTime.now;

  static final AppLogFile instance = AppLogFile._();

  /// A sink bound to [directory] instead of the environment, so tests exercise
  /// the real write/rotate path without touching the developer's home.
  @visibleForTesting
  factory AppLogFile.forDirectory(
    Directory directory, {
    DateTime Function()? clock,
  }) => AppLogFile._(directoryOverride: directory, clock: clock);

  final Directory? _directoryOverride;
  final DateTime Function() _clock;

  /// How long a failed write pauses the sink before it tries again.
  static const Duration writeFailurePause = Duration(seconds: 30);

  /// Where the sink writes on a platform whose `HOME` is not a writable
  /// developer home. Set once at startup by [bindDirectory].
  Directory? _boundDirectory;

  static const int retainedDays = 7;

  bool _disabled = false;
  bool _fileLoggingEnabled = kDebugMode;
  DateTime? _pausedUntil;
  int _droppedLines = 0;
  String? _lastWriteError;
  File? _file;
  DateTime? _fileDate;

  /// User-controlled kill switch for the file sink, fed from settings.
  ///
  /// The in-memory default is [kDebugMode], so a release build writes nothing
  /// until settings load and opt in. Disabling also stops [_pruneExpired],
  /// which only runs on the write path — retention is deliberately not a
  /// background job, so stale files are removed by [deleteAll] instead.
  void setFileLoggingEnabled(bool enabled) {
    _fileLoggingEnabled = enabled;
  }

  /// Binds the sink to a directory resolved from the platform at startup.
  ///
  /// The `$HOME/.caverno/app_logs` fallback below is a desktop path. On iOS and
  /// Android `HOME` is the sandbox root, and a write outside Documents or
  /// Library fails — so `_disabled` latched on the first line and **every**
  /// mobile log was dropped, silently. That is precisely where the sink is
  /// needed: a device has no attached `flutter run`, and a profile build does
  /// not print at all, so a notification that appears to do nothing leaves no
  /// evidence anywhere. Desktop keeps its existing path so the tooling that
  /// reads it is untouched.
  ///
  /// Resets the cached file so a rebind takes effect on the next line.
  void bindDirectory(Directory directory) {
    _boundDirectory = directory;
    _file = null;
    _fileDate = null;
    _disabled = false;
  }

  /// The directory the sink is writing to, or null when it has none.
  ///
  /// Exposed so a settings surface can offer the files for export: a log the
  /// person cannot get off the device is only marginally better than none.
  Directory? get currentDirectory => _directory();

  /// A failed write pauses the sink for [writeFailurePause] rather than
  /// ending it. Session 7171235a lost every line after 10:54:09: one write
  /// failed at the same moment a SQLite save could not open its journal, the
  /// sink latched off for the rest of the run, and the evidence that would
  /// have named the cause was never written. On resuming, the sink records how
  /// many lines it dropped and the OS error that stopped it.
  void write(String message) {
    if (_disabled || !_fileLoggingEnabled) return;
    final now = _clock();
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && now.isBefore(pausedUntil)) {
      _droppedLines++;
      return;
    }
    try {
      final redactedMessage = SensitiveDataRedactor.redactText(message);
      final file = _fileFor(now);
      if (file == null) return;
      final resumed = _pausedUntil == null
          ? ''
          : '${_timestamp(now)} [AppLog] resumed after dropping '
                '$_droppedLines line(s); write failed with: $_lastWriteError\n';
      file.writeAsStringSync(
        '$resumed${_timestamp(now)} $redactedMessage\n',
        mode: FileMode.append,
        flush: true,
      );
      _pausedUntil = null;
      _droppedLines = 0;
      _lastWriteError = null;
    } on Object catch (error) {
      _droppedLines++;
      _lastWriteError ??= error.toString();
      _pausedUntil = now.add(writeFailurePause);
    }
  }

  File? _fileFor(DateTime now) {
    final date = DateTime(now.year, now.month, now.day);
    final cached = _file;
    if (cached != null && _fileDate == date) return cached;

    final directory = _directory();
    if (directory == null) {
      _disabled = true;
      return null;
    }
    directory.createSync(recursive: true);
    _preparePermissions(directory);
    _pruneExpired(directory, date);
    final file = File('${directory.path}/${_dateStamp(date)}.log');
    if (!file.existsSync()) {
      file.createSync();
    }
    SensitiveFilePermissions.ownerOnlyFileSync(file);
    _file = file;
    _fileDate = date;
    return file;
  }

  Directory? _directory() {
    final injected = _directoryOverride;
    if (injected != null) return injected;
    final override = Platform.environment['CAVERNO_APP_LOG_DIR']?.trim();
    if (override != null && override.isNotEmpty) return Directory(override);
    final bound = _boundDirectory;
    if (bound != null) return bound;
    final home = Platform.environment['HOME']?.trim();
    if (home == null || home.isEmpty) return null;
    return Directory('$home/.caverno/app_logs');
  }

  void _preparePermissions(Directory directory) {
    final environmentOverride = Platform.environment['CAVERNO_APP_LOG_DIR']
        ?.trim();
    final usesDefaultDirectory =
        _directoryOverride == null &&
        (environmentOverride == null || environmentOverride.isEmpty);
    if (usesDefaultDirectory &&
        directory.parent.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .lastOrNull ==
            '.caverno') {
      SensitiveFilePermissions.ownerOnlyDirectorySync(directory.parent);
    }
    SensitiveFilePermissions.ownerOnlyDirectorySync(directory);
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.log')) {
        SensitiveFilePermissions.ownerOnlyFileSync(entity);
      }
    }
  }

  /// Where this sink writes, or null when no home directory is resolvable.
  /// Exposed so the Logging settings page can report and clear the same files
  /// [write] produces, rather than re-deriving the path.
  Directory? get logDirectory => _directory();

  /// Removes every `.log` file this sink has produced and returns how many
  /// were deleted. The day-file cache is dropped so the next [write] goes back
  /// through [_fileFor] — otherwise it would append to a deleted path and
  /// recreate the file without owner-only permissions.
  int deleteAll() {
    final directory = _directory();
    if (directory == null || !directory.existsSync()) return 0;
    var deleted = 0;
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.log')) continue;
      try {
        entity.deleteSync();
        deleted++;
      } on Object {
        // Another process may hold it; report only what actually went away.
      }
    }
    _file = null;
    _fileDate = null;
    return deleted;
  }

  void _pruneExpired(Directory directory, DateTime today) {
    final cutoff = today.subtract(const Duration(days: retainedDays));
    for (final entity in directory.listSync()) {
      if (entity is! File || !entity.path.endsWith('.log')) continue;
      final stamp = entity.uri.pathSegments.last.replaceAll('.log', '');
      final date = DateTime.tryParse(stamp);
      if (date == null || !date.isBefore(cutoff)) continue;
      try {
        entity.deleteSync();
      } on Object {
        // Another process may hold it; the next prune will retry.
      }
    }
  }

  static String _dateStamp(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _timestamp(DateTime now) =>
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
}
