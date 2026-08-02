import 'dart:io';

import '../../domain/services/chat_tool_catalogue_snapshot.dart';

/// Persists a catalogue snapshot without exposing partially written JSON.
final class ChatToolCatalogueSnapshotStore {
  const ChatToolCatalogueSnapshotStore({
    this.snapshotService = const ChatToolCatalogueSnapshotService(),
  });

  final ChatToolCatalogueSnapshotService snapshotService;

  Future<void> writeNew(File output, Map<String, Object?> snapshot) async {
    if (await output.exists()) {
      throw FileSystemException(
        'Refusing to overwrite an existing catalogue snapshot',
        output.path,
      );
    }
    await output.parent.create(recursive: true);
    final temporary = File(
      '${output.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(
        snapshotService.encode(snapshot),
        flush: true,
      );
      await temporary.rename(output.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }
}
