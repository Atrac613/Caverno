import 'dart:async';
import 'dart:io';

import '../../domain/services/dart_project_tooling.dart';

/// Serializes filesystem effects by their resolved target while preserving the
/// caller's original path for user-visible results.
final class FileMutationPathFence {
  final Map<String, Future<void>> _tailsByResolvedPath = {};
  final Set<_FileMutationPathLease> _leases = {};
  final Set<String> _reservedTransactionTokens = {};
  final Map<String, FileMutationPathTransaction> _transactionsByToken = {};
  final Map<String, FileMutationPathGroupTransaction>
  _groupTransactionsByToken = {};
  Completer<void>? _closeCompleter;
  var _closed = false;
  var _generation = 0;

  Future<T> runExclusive<T>(String path, Future<T> Function() operation) async {
    final lease = await _acquire(path);
    try {
      return await operation();
    } finally {
      _release(lease);
    }
  }

  /// Reserves every resolved target before running a multi-path filesystem
  /// effect. Sorted acquisition keeps overlapping multi-path callers deadlock
  /// free, while deduplication makes lexical and symbolic-link aliases share a
  /// single lease.
  Future<T> runExclusiveAll<T>(
    Iterable<String> paths,
    Future<T> Function() operation,
  ) async {
    final leases = await _acquireAll(paths);
    try {
      return await operation();
    } finally {
      _releaseAll(leases);
    }
  }

  /// Reserves every resolved target until an exact multi-path transaction is
  /// either finished or reconciled.
  Future<FileMutationPathGroupTransaction> beginTransactionAll({
    required Iterable<String> paths,
    required String transactionToken,
  }) async {
    final token = _requiredExact(transactionToken, 'transactionToken');
    if (_reservedTransactionTokens.contains(token) ||
        _transactionsByToken.containsKey(token) ||
        _groupTransactionsByToken.containsKey(token)) {
      throw StateError('The filesystem transaction token is already active.');
    }
    _reservedTransactionTokens.add(token);
    try {
      final leases = await _acquireAll(paths);
      final transaction = FileMutationPathGroupTransaction._(
        transactionToken: token,
        leases: leases,
      );
      _groupTransactionsByToken[token] = transaction;
      return transaction;
    } finally {
      _reservedTransactionTokens.remove(token);
      _completeCloseIfDrained();
    }
  }

  void finishTransactionAll(FileMutationPathGroupTransaction transaction) {
    _requireActiveGroup(transaction);
    _groupTransactionsByToken.remove(transaction.transactionToken);
    _releaseAll(transaction._leases);
  }

  /// Releases an exact completed group transaction by token.
  ///
  /// This is reserved for lifecycle retirement after the serialized operation
  /// has settled and no further recovery effect may run.
  bool finishTransactionAllByToken(String transactionToken) {
    final token = _requiredExact(transactionToken, 'transactionToken');
    final transaction = _groupTransactionsByToken.remove(token);
    if (transaction == null) return false;
    _releaseAll(transaction._leases);
    return true;
  }

  /// Runs one serialized recovery attempt while the original group lease stays
  /// held. The lease is released only when [releaseWhen] confirms settlement.
  Future<FileMutationPathTransactionSettlement<T>?> settleTransactionAll<T>({
    required String transactionToken,
    required Future<T> Function() operation,
    required bool Function(T value) releaseWhen,
  }) async {
    final token = _requiredExact(transactionToken, 'transactionToken');
    final transaction = _groupTransactionsByToken[token];
    if (transaction == null) return null;
    return transaction._serialize(() async {
      _requireActiveGroup(transaction);
      final value = await operation();
      if (releaseWhen(value)) {
        _groupTransactionsByToken.remove(token);
        _releaseAll(transaction._leases);
      }
      return FileMutationPathTransactionSettlement(value);
    });
  }

  /// Starts a fence that remains held after raw execution until its exact
  /// rollback record or compensation settles.
  Future<FileMutationPathTransaction> beginTransaction({
    required String path,
    required String transactionToken,
  }) async {
    final token = _requiredExact(transactionToken, 'transactionToken');
    if (_reservedTransactionTokens.contains(token) ||
        _transactionsByToken.containsKey(token) ||
        _groupTransactionsByToken.containsKey(token)) {
      throw StateError('The filesystem transaction token is already active.');
    }
    _reservedTransactionTokens.add(token);
    try {
      final lease = await _acquire(path);
      final transaction = FileMutationPathTransaction._(
        transactionToken: token,
        lexicalPathKey: DartProjectPath.pathKey(path),
        lease: lease,
      );
      _transactionsByToken[token] = transaction;
      return transaction;
    } finally {
      _reservedTransactionTokens.remove(token);
      _completeCloseIfDrained();
    }
  }

  void markHandoffReady(FileMutationPathTransaction transaction) {
    _requireActive(transaction);
    if (!transaction._handoffReady.isCompleted) {
      transaction._handoffReady.complete();
    }
  }

  void finishWithoutEffect(FileMutationPathTransaction transaction) {
    _requireActive(transaction);
    markHandoffReady(transaction);
    _transactionsByToken.remove(transaction.transactionToken);
    _release(transaction._lease);
  }

  /// Continues an exact raw transaction without releasing its path between
  /// callbacks. A null return means no matching transaction is active.
  Future<FileMutationPathTransactionSettlement<T>?> settleTransaction<T>({
    required String path,
    required String transactionToken,
    required Future<T> Function() operation,
    required bool Function(T value) releaseWhen,
  }) async {
    final token = _requiredExact(transactionToken, 'transactionToken');
    final transaction = _transactionsByToken[token];
    if (transaction == null ||
        transaction.lexicalPathKey != DartProjectPath.pathKey(path)) {
      return null;
    }
    await transaction._handoffReady.future;
    _requireActive(transaction);
    final value = await operation();
    if (releaseWhen(value)) {
      _transactionsByToken.remove(token);
      _release(transaction._lease);
    }
    return FileMutationPathTransactionSettlement(value);
  }

  void clearAll() {
    if (_leases.isNotEmpty ||
        _reservedTransactionTokens.isNotEmpty ||
        _transactionsByToken.isNotEmpty ||
        _groupTransactionsByToken.isNotEmpty) {
      throw StateError(
        'The filesystem path fence cannot be cleared while work is active.',
      );
    }
    _generation++;
    _tailsByResolvedPath.clear();
  }

  /// Stops accepting new work and waits for every acquired lease to settle.
  ///
  /// Active operations retain their leases so lifecycle disposal cannot allow a
  /// successor to overlap an effect that has already started.
  Future<void> close() {
    _closed = true;
    _closeCompleter ??= Completer<void>();
    _completeCloseIfDrained();
    return _closeCompleter!.future;
  }

  Future<_FileMutationPathLease> _acquire(String path) async {
    final lexicalPath = _requiredExact(path, 'path');
    final resolvedPathKey = await resolvePathKey(lexicalPath);
    final lease = await _acquireResolvedKey(resolvedPathKey);
    try {
      if (await resolvePathKey(lexicalPath) != resolvedPathKey) {
        throw StateError(
          'The filesystem target changed while its path fence was acquired.',
        );
      }
      return lease;
    } catch (_) {
      _release(lease);
      rethrow;
    }
  }

  Future<List<_FileMutationPathLease>> _acquireAll(
    Iterable<String> paths,
  ) async {
    final lexicalPaths = <String>[];
    final resolvedPathKeys = <String>[];
    for (final path in paths) {
      final lexicalPath = _requiredExact(path, 'path');
      lexicalPaths.add(lexicalPath);
      resolvedPathKeys.add(await resolvePathKey(lexicalPath));
    }
    final orderedPathKeys = resolvedPathKeys.toSet().toList()..sort();
    final leases = <_FileMutationPathLease>[];
    try {
      for (final resolvedPathKey in orderedPathKeys) {
        leases.add(await _acquireResolvedKey(resolvedPathKey));
      }
      for (var index = 0; index < lexicalPaths.length; index++) {
        if (await resolvePathKey(lexicalPaths[index]) !=
            resolvedPathKeys[index]) {
          throw StateError(
            'A filesystem target changed while its path fences were acquired.',
          );
        }
      }
      return leases;
    } catch (_) {
      _releaseAll(leases);
      rethrow;
    }
  }

  Future<_FileMutationPathLease> _acquireResolvedKey(
    String resolvedPathKey,
  ) async {
    if (_closed) {
      throw StateError('The filesystem path fence is closed.');
    }
    final generation = _generation;
    final prior = _tailsByResolvedPath[resolvedPathKey];
    final completion = Completer<void>();
    final lease = _FileMutationPathLease(
      resolvedPathKey: resolvedPathKey,
      completion: completion,
    );
    _leases.add(lease);
    _tailsByResolvedPath[resolvedPathKey] = completion.future;
    if (prior != null) {
      try {
        await prior;
      } catch (_) {
        // A failed predecessor must not strand queued filesystem work.
      }
    }
    if (_closed || generation != _generation || lease._released) {
      _release(lease);
      throw StateError(
        _closed
            ? 'The filesystem path fence is closed.'
            : 'The filesystem path fence was cleared.',
      );
    }
    return lease;
  }

  void _release(_FileMutationPathLease lease) {
    if (lease._released) return;
    lease._released = true;
    _leases.remove(lease);
    if (!lease.completion.isCompleted) {
      lease.completion.complete();
    }
    if (identical(
      _tailsByResolvedPath[lease.resolvedPathKey],
      lease.completion.future,
    )) {
      _tailsByResolvedPath.remove(lease.resolvedPathKey);
    }
    _completeCloseIfDrained();
  }

  void _releaseAll(Iterable<_FileMutationPathLease> leases) {
    for (final lease in leases.toList(growable: false).reversed) {
      _release(lease);
    }
  }

  void _completeCloseIfDrained() {
    final completer = _closeCompleter;
    if (_closed &&
        completer != null &&
        !completer.isCompleted &&
        _leases.isEmpty &&
        _reservedTransactionTokens.isEmpty) {
      completer.complete();
    }
  }

  void _requireActive(FileMutationPathTransaction transaction) {
    if (!identical(
      _transactionsByToken[transaction.transactionToken],
      transaction,
    )) {
      throw StateError('The filesystem transaction is no longer active.');
    }
  }

  void _requireActiveGroup(FileMutationPathGroupTransaction transaction) {
    if (!identical(
      _groupTransactionsByToken[transaction.transactionToken],
      transaction,
    )) {
      throw StateError('The filesystem transaction is no longer active.');
    }
  }

  /// Resolves the stable path identity used for mutation serialization.
  static Future<String> resolvePathKey(String path) async =>
      resolvePathKeySync(path);

  /// Synchronous [resolvePathKey].
  ///
  /// The walk deliberately uses synchronous filesystem calls: snapshot capture
  /// runs on the approval fast path, where a chain of async stat round-trips
  /// delays the pending-approval state past the turn's event cascade.
  static String resolvePathKeySync(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty || normalized != path) {
      throw ArgumentError.value(path, 'path', 'Must be non-empty and trimmed.');
    }
    var candidate = File(path).absolute.path;
    final missingSegments = <String>[];
    while (true) {
      try {
        final type = FileSystemEntity.typeSync(candidate, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          final resolved = switch (type) {
            FileSystemEntityType.directory => Directory(
              candidate,
            ).resolveSymbolicLinksSync(),
            FileSystemEntityType.link => Link(
              candidate,
            ).resolveSymbolicLinksSync(),
            _ => File(candidate).resolveSymbolicLinksSync(),
          };
          final suffix = missingSegments.reversed.join(Platform.pathSeparator);
          final resolvedPath = suffix.isEmpty
              ? resolved
              : '$resolved${Platform.pathSeparator}$suffix';
          return DartProjectPath.pathKey(resolvedPath);
        }
      } on FileSystemException {
        // Fall back to the nearest resolvable parent or the lexical path.
      }
      final parent = Directory(candidate).parent.path;
      if (parent == candidate) {
        return DartProjectPath.pathKey(path);
      }
      final separatorOffset = parent.endsWith(Platform.pathSeparator)
          ? parent.length
          : parent.length + 1;
      if (separatorOffset > candidate.length) {
        return DartProjectPath.pathKey(path);
      }
      missingSegments.add(candidate.substring(separatorOffset));
      candidate = parent;
    }
  }

  static String lexicalPathKey(String path) => DartProjectPath.pathKey(path);

  String _requiredExact(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized != value) {
      throw ArgumentError.value(value, name, 'Must be non-empty and trimmed.');
    }
    return normalized;
  }
}

final class FileMutationPathTransaction {
  FileMutationPathTransaction._({
    required this.transactionToken,
    required this.lexicalPathKey,
    required _FileMutationPathLease lease,
  }) : _lease = lease;

  final String transactionToken;
  final String lexicalPathKey;
  final _FileMutationPathLease _lease;
  final Completer<void> _handoffReady = Completer<void>();
}

final class FileMutationPathTransactionSettlement<T> {
  const FileMutationPathTransactionSettlement(this.value);

  final T value;
}

final class FileMutationPathGroupTransaction {
  FileMutationPathGroupTransaction._({
    required this.transactionToken,
    required List<_FileMutationPathLease> leases,
  }) : _leases = List<_FileMutationPathLease>.unmodifiable(leases);

  final String transactionToken;
  final List<_FileMutationPathLease> _leases;
  Future<void> _settlementTail = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _settlementTail = _settlementTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

final class _FileMutationPathLease {
  _FileMutationPathLease({
    required this.resolvedPathKey,
    required this.completion,
  });

  final String resolvedPathKey;
  final Completer<void> completion;
  var _released = false;
}
