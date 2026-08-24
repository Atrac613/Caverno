import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/app_settings.dart';
import 'settings_file_service.dart';

final settingsQrServiceProvider = Provider<SettingsQrService>((ref) {
  return SettingsQrService();
});

class SettingsQrLimitException implements Exception {
  const SettingsQrLimitException(this.message);

  final String message;

  @override
  String toString() => 'SettingsQrLimitException: $message';
}

class SettingsQrService {
  SettingsQrService({
    this.maxCompressedBytes = defaultMaxCompressedBytes,
    this.maxDecompressedBytes = defaultMaxDecompressedBytes,
  }) {
    if (maxCompressedBytes <= 0 || maxDecompressedBytes <= 0) {
      throw ArgumentError('Settings QR byte limits must be positive.');
    }
  }

  static const int defaultMaxCompressedBytes = 256 * 1024;
  static const int defaultMaxDecompressedBytes = 1024 * 1024;

  final int maxCompressedBytes;
  final int maxDecompressedBytes;

  int get maxBase64Characters => ((maxCompressedBytes + 2) ~/ 3) * 4;

  /// Generates a QR-compatible string from [AppSettings].
  /// Uses minified JSON -> GZip -> Base64 for compact representation.
  String generateQrString(AppSettings settings) {
    final jsonString = SettingsFileService.encodeSettings(settings);
    final bytes = utf8.encode(jsonString);
    _checkDecompressedLength(bytes.length);
    // Note: GZipCodec is available in dart:io (Mobile/Desktop)
    final compressed = GZipCodec().encode(bytes);
    _checkCompressedLength(compressed.length);
    return base64Encode(compressed);
  }

  /// Parses [AppSettings] from a QR data string.
  AppSettings parseQrString(String qrString) {
    try {
      if (qrString.length > maxBase64Characters) {
        throw SettingsQrLimitException(
          'Settings QR Base64 text exceeded $maxBase64Characters characters.',
        );
      }
      final compressed = base64Decode(qrString.trim());
      _checkCompressedLength(compressed.length);
      final bytes = _decompressBounded(compressed);
      final jsonString = utf8.decode(bytes);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final settings = AppSettings.fromJson(json);
      SettingsFileService.validateSettings(settings);
      return settings;
    } on SettingsQrLimitException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid or corrupt QR data: $e');
    }
  }

  List<int> _decompressBounded(List<int> compressed) {
    final output = _BoundedSettingsQrByteSink(maxDecompressedBytes);
    final decoder = GZipCodec().decoder.startChunkedConversion(output);
    try {
      decoder.add(compressed);
      decoder.close();
    } catch (_) {
      try {
        decoder.close();
      } catch (_) {}
      rethrow;
    }
    return output.takeBytes();
  }

  void _checkCompressedLength(int length) {
    if (length > maxCompressedBytes) {
      throw SettingsQrLimitException(
        'Settings QR compressed payload exceeded $maxCompressedBytes bytes.',
      );
    }
  }

  void _checkDecompressedLength(int length) {
    if (length > maxDecompressedBytes) {
      throw SettingsQrLimitException(
        'Settings QR decompressed payload exceeded '
        '$maxDecompressedBytes bytes.',
      );
    }
  }
}

class _BoundedSettingsQrByteSink extends ByteConversionSink {
  _BoundedSettingsQrByteSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder _bytes = BytesBuilder();
  var _length = 0;
  var _closed = false;

  @override
  void add(List<int> chunk) {
    addSlice(chunk, 0, chunk.length, false);
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    if (_closed) throw StateError('Settings QR byte sink is closed.');
    final chunkLength = end - start;
    if (chunkLength > maxBytes - _length) {
      throw SettingsQrLimitException(
        'Settings QR decompressed payload exceeded $maxBytes bytes.',
      );
    }
    if (chunkLength > 0) {
      _bytes.add(
        start == 0 && end == chunk.length ? chunk : chunk.sublist(start, end),
      );
      _length += chunkLength;
    }
    if (isLast) close();
  }

  @override
  void close() {
    _closed = true;
  }

  Uint8List takeBytes() {
    if (!_closed) {
      throw StateError('Settings QR byte sink is not closed.');
    }
    return _bytes.takeBytes();
  }
}
