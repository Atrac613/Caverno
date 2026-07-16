import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/application/runtime/caverno_execution_lease.dart';
import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: caverno_execution_lease_probe.dart '
      '<data-root> <resource-kind> <identity> <metadata-mode>',
    );
    exitCode = 64;
    return;
  }

  final dataRoot = Directory(arguments[0]);
  final kind = CavernoExecutionLeaseResourceKind.values.byName(arguments[1]);
  final identity = arguments[2];
  final metadataMode = arguments[3];
  final resource = switch (kind) {
    CavernoExecutionLeaseResourceKind.chatMemory =>
      CavernoExecutionLeaseResource.chatMemory(),
    CavernoExecutionLeaseResourceKind.conversation =>
      CavernoExecutionLeaseResource.conversation(identity),
    CavernoExecutionLeaseResourceKind.codingWorkspace =>
      CavernoExecutionLeaseResource.codingWorkspace(identity),
  };

  CavernoExecutionLeaseHandle? handle;
  RandomAccessFile? rawDescriptor;
  try {
    if (metadataMode == 'invalid') {
      final leaseDirectory = Directory.fromUri(
        dataRoot.absolute.uri.resolve('execution_leases/'),
      )..createSync(recursive: true);
      final lockFile = File.fromUri(
        leaseDirectory.uri.resolve(
          '${sha256.convert(utf8.encode(resource.key))}.lease',
        ),
      );
      rawDescriptor = lockFile.openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive)
        ..truncateSync(0)
        ..setPositionSync(0)
        ..writeStringSync('invalid owner metadata')
        ..flushSync();
    } else {
      handle = CavernoExecutionLeaseService(
        dataRoot: dataRoot,
        frontend: 'terminal-probe',
        ownerId: 'probe-$pid',
      ).acquire(<CavernoExecutionLeaseResource>[resource]);
    }

    stdout.writeln(
      jsonEncode(<String, Object>{'status': 'acquired', 'pid': pid}),
    );
    await stdout.flush();
    await stdin.first;
  } finally {
    handle?.release();
    if (rawDescriptor != null) {
      rawDescriptor.unlockSync();
      rawDescriptor.closeSync();
    }
  }
}
