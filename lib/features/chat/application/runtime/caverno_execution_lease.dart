import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

enum CavernoExecutionLeaseResourceKind {
  conversation,
  codingWorkspace,
  chatMemory,
}

final class CavernoExecutionLeaseResource {
  CavernoExecutionLeaseResource.chatMemory()
    : this._(
        kind: CavernoExecutionLeaseResourceKind.chatMemory,
        identity: 'global',
        displayTarget: 'chat-memory',
      );

  CavernoExecutionLeaseResource.conversation(String conversationId)
    : this._(
        kind: CavernoExecutionLeaseResourceKind.conversation,
        identity: _requiredIdentity(conversationId, 'conversationId'),
        displayTarget:
            'conversation:${_abbreviate(_requiredIdentity(conversationId, 'conversationId'))}',
      );

  CavernoExecutionLeaseResource.codingWorkspace(String workspacePath)
    : this._codingWorkspace(_normalizeWorkspace(workspacePath));

  CavernoExecutionLeaseResource._codingWorkspace(String normalizedPath)
    : this._(
        kind: CavernoExecutionLeaseResourceKind.codingWorkspace,
        identity: normalizedPath,
        displayTarget: 'workspace:${_workspaceLabel(normalizedPath)}',
      );

  const CavernoExecutionLeaseResource._({
    required this.kind,
    required this.identity,
    required this.displayTarget,
  });

  final CavernoExecutionLeaseResourceKind kind;
  final String identity;
  final String displayTarget;

  String get key => '${kind.name}\n$identity';

  static String _requiredIdentity(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'Must not be empty.');
    }
    return normalized;
  }

  static String _normalizeWorkspace(String value) {
    final required = _requiredIdentity(value, 'workspacePath');
    final absolute = Directory(required).absolute;
    String resolved;
    try {
      resolved = absolute.resolveSymbolicLinksSync();
    } on FileSystemException {
      resolved = absolute.path;
    }
    final normalized = Directory.fromUri(
      Directory(resolved).absolute.uri.normalizePath(),
    ).path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static String _workspaceLabel(String normalizedPath) {
    final segments = Directory(
      normalizedPath,
    ).uri.pathSegments.where((segment) => segment.trim().isNotEmpty);
    final basename = segments.isEmpty ? '' : segments.last.trim();
    return basename.isEmpty ? 'root' : basename;
  }

  static String _abbreviate(String value) {
    const visibleLength = 8;
    return value.length <= visibleLength
        ? value
        : value.substring(0, visibleLength);
  }
}

final class CavernoExecutionLeaseOwner {
  const CavernoExecutionLeaseOwner({
    required this.schemaVersion,
    required this.ownerId,
    required this.processId,
    required this.frontend,
    required this.acquiredAt,
    required this.resourceKind,
    required this.displayTarget,
  });

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final String ownerId;
  final int processId;
  final String frontend;
  final DateTime acquiredAt;
  final CavernoExecutionLeaseResourceKind resourceKind;
  final String displayTarget;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': schemaVersion,
    'ownerId': ownerId,
    'processId': processId,
    'frontend': frontend,
    'acquiredAt': acquiredAt.toUtc().toIso8601String(),
    'resourceKind': resourceKind.name,
    'displayTarget': displayTarget,
  };

  static CavernoExecutionLeaseOwner? tryParse(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final schemaVersion = json['schemaVersion'];
      final ownerId = json['ownerId'];
      final processId = json['processId'];
      final frontend = json['frontend'];
      final acquiredAt = json['acquiredAt'];
      final resourceKind = json['resourceKind'];
      final displayTarget = json['displayTarget'];
      if (schemaVersion is! int ||
          ownerId is! String ||
          processId is! int ||
          frontend is! String ||
          acquiredAt is! String ||
          resourceKind is! String ||
          displayTarget is! String) {
        return null;
      }
      return CavernoExecutionLeaseOwner(
        schemaVersion: schemaVersion,
        ownerId: ownerId,
        processId: processId,
        frontend: frontend,
        acquiredAt: DateTime.parse(acquiredAt).toUtc(),
        resourceKind: CavernoExecutionLeaseResourceKind.values.byName(
          resourceKind,
        ),
        displayTarget: displayTarget,
      );
    } on Object {
      return null;
    }
  }
}

final class CavernoExecutionLeaseConflict implements Exception {
  const CavernoExecutionLeaseConflict({required this.resource, this.owner});

  final CavernoExecutionLeaseResource resource;
  final CavernoExecutionLeaseOwner? owner;

  String get message {
    final knownOwner = owner;
    if (knownOwner == null) {
      return '${resource.displayTarget} is already owned by another Caverno process.';
    }
    return '${resource.displayTarget} is already owned by '
        '${knownOwner.frontend} process ${knownOwner.processId}.';
  }

  @override
  String toString() => 'CavernoExecutionLeaseConflict: $message';
}

final class CavernoExecutionLeaseService {
  CavernoExecutionLeaseService({
    required Directory dataRoot,
    required String frontend,
    String? ownerId,
    int? processId,
    DateTime Function()? now,
  }) : dataRoot = Directory.fromUri(dataRoot.absolute.uri.normalizePath()),
       frontend = _requiredFrontend(frontend),
       ownerId = ownerId ?? const Uuid().v4(),
       processId = processId ?? pid,
       _now = now ?? DateTime.now;

  static final Map<String, CavernoExecutionLeaseOwner> _localOwnersByPath =
      <String, CavernoExecutionLeaseOwner>{};

  final Directory dataRoot;
  final String frontend;
  final String ownerId;
  final int processId;
  final DateTime Function() _now;

  Directory get leaseDirectory =>
      Directory.fromUri(dataRoot.uri.resolve('execution_leases/'));

  CavernoExecutionLeaseHandle acquire(
    Iterable<CavernoExecutionLeaseResource> resources,
  ) {
    final uniqueResources = <String, CavernoExecutionLeaseResource>{
      for (final resource in resources) resource.key: resource,
    };
    if (uniqueResources.isEmpty) {
      throw ArgumentError.value(resources, 'resources', 'Must not be empty.');
    }

    leaseDirectory.createSync(recursive: true);
    final ordered = uniqueResources.values.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final held = <_HeldExecutionLease>[];
    try {
      for (final resource in ordered) {
        held.add(_acquireOne(resource));
      }
      return CavernoExecutionLeaseHandle._(
        resources: List<CavernoExecutionLeaseResource>.unmodifiable(ordered),
        held: held,
      );
    } on Object {
      _releaseAll(held, throwOnFailure: false);
      rethrow;
    }
  }

  _HeldExecutionLease _acquireOne(CavernoExecutionLeaseResource resource) {
    final lockPath = File.fromUri(
      leaseDirectory.uri.resolve(
        '${sha256.convert(utf8.encode(resource.key))}.lease',
      ),
    ).path;
    final localOwner = _localOwnersByPath[lockPath];
    if (localOwner != null) {
      throw CavernoExecutionLeaseConflict(
        resource: resource,
        owner: localOwner,
      );
    }

    final file = File(lockPath);
    final descriptor = file.openSync(mode: FileMode.append);
    try {
      descriptor.lockSync(FileLock.exclusive);
    } on Object catch (error) {
      final owner = error is FileSystemException
          ? _readOwner(descriptor)
          : null;
      descriptor.closeSync();
      if (error is FileSystemException) {
        throw CavernoExecutionLeaseConflict(resource: resource, owner: owner);
      }
      rethrow;
    }

    final owner = CavernoExecutionLeaseOwner(
      schemaVersion: CavernoExecutionLeaseOwner.currentSchemaVersion,
      ownerId: ownerId,
      processId: processId,
      frontend: frontend,
      acquiredAt: _now().toUtc(),
      resourceKind: resource.kind,
      displayTarget: resource.displayTarget,
    );
    _localOwnersByPath[lockPath] = owner;
    try {
      descriptor.truncateSync(0);
      descriptor.setPositionSync(0);
      descriptor.writeStringSync(jsonEncode(owner.toJson()));
      descriptor.flushSync();
      return _HeldExecutionLease(
        lockPath: lockPath,
        descriptor: descriptor,
        ownerId: owner.ownerId,
      );
    } on Object {
      _localOwnersByPath.remove(lockPath);
      _unlockAndClose(descriptor);
      rethrow;
    }
  }

  static CavernoExecutionLeaseOwner? _readOwner(RandomAccessFile descriptor) {
    try {
      descriptor.setPositionSync(0);
      final bytes = descriptor.readSync(descriptor.lengthSync());
      return CavernoExecutionLeaseOwner.tryParse(utf8.decode(bytes));
    } on Object {
      return null;
    }
  }

  static String _requiredFrontend(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'frontend', 'Must not be empty.');
    }
    return normalized;
  }
}

final class CavernoExecutionLeaseHandle {
  CavernoExecutionLeaseHandle._({
    required this.resources,
    required List<_HeldExecutionLease> held,
  }) : _held = held;

  final List<CavernoExecutionLeaseResource> resources;
  final List<_HeldExecutionLease> _held;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _releaseAll(_held, throwOnFailure: true);
  }
}

final class _HeldExecutionLease {
  const _HeldExecutionLease({
    required this.lockPath,
    required this.descriptor,
    required this.ownerId,
  });

  final String lockPath;
  final RandomAccessFile descriptor;
  final String ownerId;
}

void _releaseAll(
  List<_HeldExecutionLease> held, {
  required bool throwOnFailure,
}) {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final lease in held.reversed) {
    final localOwner =
        CavernoExecutionLeaseService._localOwnersByPath[lease.lockPath];
    if (localOwner?.ownerId == lease.ownerId) {
      CavernoExecutionLeaseService._localOwnersByPath.remove(lease.lockPath);
    }
    try {
      _unlockAndClose(lease.descriptor);
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  held.clear();
  if (throwOnFailure && firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

void _unlockAndClose(RandomAccessFile descriptor) {
  Object? unlockError;
  StackTrace? unlockStackTrace;
  try {
    descriptor.unlockSync();
  } on Object catch (error, stackTrace) {
    unlockError = error;
    unlockStackTrace = stackTrace;
  }
  try {
    descriptor.closeSync();
  } on Object catch (error, stackTrace) {
    unlockError ??= error;
    unlockStackTrace ??= stackTrace;
  }
  if (unlockError != null) {
    Error.throwWithStackTrace(unlockError, unlockStackTrace!);
  }
}
