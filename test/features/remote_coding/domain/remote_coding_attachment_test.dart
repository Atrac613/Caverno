import 'dart:typed_data';

import 'package:caverno/features/remote_coding/domain/remote_coding_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a 32 MiB attachment boundary', () {
    expect(RemoteCodingAttachmentPolicy.maxBytes, 32 * 1024 * 1024);
    expect(RemoteCodingAttachmentPolicy.maxSizeLabel, '32 MiB');
    expect(
      RemoteCodingAttachmentPolicy.validate(
        name: 'exact.bin',
        mimeType: 'application/octet-stream',
        byteLength: RemoteCodingAttachmentPolicy.maxBytes,
      ),
      isNull,
    );
  });

  test('chunks empty and exact-boundary payloads deterministically', () {
    expect(RemoteCodingAttachmentPolicy.chunkCount(0), 1);
    expect(
      RemoteCodingAttachmentPolicy.chunkCount(
        RemoteCodingAttachmentPolicy.chunkBytes,
      ),
      1,
    );
    expect(
      RemoteCodingAttachmentPolicy.chunkCount(
        RemoteCodingAttachmentPolicy.chunkBytes + 1,
      ),
      2,
    );
  });

  test('normalizes an untrusted display name and MIME type', () {
    expect(
      RemoteCodingAttachmentPolicy.normalizedName('../notes final.txt'),
      'notes_final.txt',
    );
    expect(
      RemoteCodingAttachmentPolicy.normalizedMimeType(
        'TEXT/PLAIN; charset=utf-8',
      ),
      'text/plain',
    );
    expect(
      RemoteCodingAttachmentPolicy.normalizedMimeType(''),
      'application/octet-stream',
    );
  });

  test('rejects attachments above the bounded transfer size', () {
    expect(
      RemoteCodingAttachmentPolicy.validate(
        name: 'large.bin',
        mimeType: 'application/octet-stream',
        byteLength: RemoteCodingAttachmentPolicy.maxBytes + 1,
      ),
      isNotNull,
    );
    expect(
      RemoteCodingAttachmentDraft(
        name: 'screen.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      ).isImage,
      isTrue,
    );
  });
}
