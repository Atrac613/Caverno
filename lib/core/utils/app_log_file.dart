import 'dart:io';

import 'package:flutter/foundation.dart';

import '../security/sensitive_data_redactor.dart';
import '../security/sensitive_file_permissions.dart';

/// Debug-build file sink for [appLog], at `~/.caverno/app_logs/<date>.log`.
///
/// Exists because the interesting failures are the ones where the app stops
/// making progress: `debugPrint` output only survives while a `flutter run`
/// terminal is attached, so a stall reproduced outside one leaves no trace and
/// the next session can only guess. Writes are synchronous and unbuffered for
/// that reason — a hung isolate must still have its last lines on disk.
///
/// Never throws: a sink that cannot write disables itself for the process
/// rather than turning logging into a second failure.
class AppLogFile {
  AppLogFile._({Directory? directoryOverride})
    : _directoryOverride = directoryOverride;

  static final AppLogFile instance = AppLogFile._();

  /// A sink bound to [directory] instead of the environment, so tests exercise
  /// the real write/rotate path without touching the developer's home.
  @visibleForTesting
  factory AppLogFile.forDirectory(Directory directory) =>
      AppLogFile._(directoryOverride: directory);

  final Directory? _directoryOverride;

  static const int retainedDays = 7;

  bool _disabled = false;
  File? _file;
  DateTime? _fileDate;

  void write(String message) {
    if (_disabled) return;
    try {
      final redactedMessage = SensitiveDataRedactor.redactText(message);
      final now = DateTime.now();
      final file = _fileFor(now);
      if (file == null) return;
      file.writeAsStringSync(
        '${_timestamp(now)} $redactedMessage\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // A read-only or missing home directory is not worth retrying per line.
      _disabled = true;
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
