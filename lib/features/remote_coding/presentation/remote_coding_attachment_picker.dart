import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../domain/remote_coding_attachment.dart';

/// Picks or reads one attachment for the Remote Coding mobile composer.
class RemoteCodingAttachmentPicker {
  const RemoteCodingAttachmentPicker();

  Future<RemoteCodingAttachmentDraft?> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;
    return RemoteCodingAttachmentDraft(
      name: picked.name.isEmpty ? 'image.jpg' : picked.name,
      mimeType:
          picked.mimeType ??
          _mimeTypeForName(picked.name, fallback: 'image/jpeg'),
      bytes: bytes,
    );
  }

  Future<RemoteCodingAttachmentDraft?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    final pickedPath = picked.path;
    final bytes =
        picked.bytes ??
        (pickedPath == null ? null : await File(pickedPath).readAsBytes());
    if (bytes == null || (bytes.isEmpty && picked.size != 0)) return null;
    return RemoteCodingAttachmentDraft(
      name: picked.name,
      mimeType: _mimeTypeForName(picked.name),
      bytes: bytes,
    );
  }

  /// Reads the highest-priority supported binary format from the clipboard.
  /// Returns null when the clipboard contains text only, so the caller can
  /// preserve normal text paste behavior.
  Future<RemoteCodingAttachmentDraft?> readClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;
    final reader = await clipboard.read();
    const formats = <(FileFormat, String, String)>[
      (Formats.png, 'image/png', 'clipboard.png'),
      (Formats.jpeg, 'image/jpeg', 'clipboard.jpg'),
      (Formats.gif, 'image/gif', 'clipboard.gif'),
      (Formats.webp, 'image/webp', 'clipboard.webp'),
      (Formats.heic, 'image/heic', 'clipboard.heic'),
      (Formats.heif, 'image/heif', 'clipboard.heif'),
      (Formats.tiff, 'image/tiff', 'clipboard.tiff'),
      (Formats.bmp, 'image/bmp', 'clipboard.bmp'),
      (Formats.pdf, 'application/pdf', 'clipboard.pdf'),
      (Formats.plainTextFile, 'text/plain', 'clipboard.txt'),
      (Formats.htmlFile, 'text/html', 'clipboard.html'),
      (Formats.csv, 'text/csv', 'clipboard.csv'),
      (Formats.json, 'application/json', 'clipboard.json'),
      (Formats.doc, 'application/msword', 'clipboard.doc'),
      (
        Formats.docx,
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'clipboard.docx',
      ),
      (Formats.zip, 'application/zip', 'clipboard.zip'),
    ];
    for (final (format, mimeType, fallbackName) in formats) {
      if (!reader.canProvide(format)) continue;
      final attachment = await _readFile(
        reader: reader,
        format: format,
        mimeType: mimeType,
        fallbackName: fallbackName,
      );
      if (attachment != null) {
        return attachment;
      }
    }
    final suggestedName = await reader.getSuggestedName();
    if (suggestedName == null && !reader.canProvide(Formats.fileUri)) {
      return null;
    }
    final attachment = await _readFile(
      reader: reader,
      format: null,
      mimeType: _mimeTypeForName(suggestedName ?? ''),
      fallbackName: suggestedName ?? 'clipboard.bin',
    );
    if (attachment == null) return null;
    return attachment;
  }

  Future<RemoteCodingAttachmentDraft?> fromInsertedContent(
    KeyboardInsertedContent content,
  ) async {
    final bytes = content.data;
    final mimeType = content.mimeType.trim().toLowerCase();
    if (bytes == null || bytes.isEmpty || !mimeType.startsWith('image/')) {
      return null;
    }
    final extension = mimeType.split('/').last;
    return RemoteCodingAttachmentDraft(
      name: 'inserted.$extension',
      mimeType: mimeType,
      bytes: bytes,
    );
  }

  Future<RemoteCodingAttachmentDraft?> _readFile({
    required DataReader reader,
    required FileFormat? format,
    required String mimeType,
    required String fallbackName,
  }) async {
    final completer = Completer<RemoteCodingAttachmentDraft?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          if (file.fileSize != null &&
              file.fileSize! > RemoteCodingAttachmentPolicy.maxBytes) {
            completer.complete(null);
            return;
          }
          final bytes = await file.readAll();
          completer.complete(
            RemoteCodingAttachmentDraft(
              name: file.fileName ?? fallbackName,
              mimeType: mimeType,
              bytes: bytes,
            ),
          );
        } catch (_) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    if (progress == null) return null;
    return completer.future;
  }

  static String _mimeTypeForName(
    String name, {
    String fallback = 'application/octet-stream',
  }) {
    final lower = name.toLowerCase();
    const types = <String, String>{
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.heic': 'image/heic',
      '.heif': 'image/heif',
      '.tif': 'image/tiff',
      '.tiff': 'image/tiff',
      '.bmp': 'image/bmp',
      '.pdf': 'application/pdf',
      '.json': 'application/json',
      '.csv': 'text/csv',
      '.txt': 'text/plain',
      '.md': 'text/markdown',
      '.xml': 'application/xml',
      '.yaml': 'application/yaml',
      '.yml': 'application/yaml',
      '.zip': 'application/zip',
    };
    for (final entry in types.entries) {
      if (lower.endsWith(entry.key)) return entry.value;
    }
    return fallback;
  }
}
