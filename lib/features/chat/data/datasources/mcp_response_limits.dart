import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class McpResponseLimitException implements Exception {
  const McpResponseLimitException(this.message);

  final String message;

  @override
  String toString() => 'McpResponseLimitException: $message';
}

/// Decodes newline-delimited UTF-8 without buffering an unbounded line.
class McpBoundedLineDecoder extends StreamTransformerBase<List<int>, String> {
  McpBoundedLineDecoder({
    required this.maxLineBytes,
    this.streamName = 'MCP stdio',
  }) {
    if (maxLineBytes <= 0) {
      throw ArgumentError.value(
        maxLineBytes,
        'maxLineBytes',
        'The MCP stdio line limit must be positive.',
      );
    }
  }

  final int maxLineBytes;
  final String streamName;

  @override
  Stream<String> bind(Stream<List<int>> stream) async* {
    final buffer = Uint8List(maxLineBytes);
    var length = 0;

    String decodeLine() {
      var decodedLength = length;
      if (decodedLength > 0 && buffer[decodedLength - 1] == 0x0D) {
        decodedLength -= 1;
      }
      return utf8.decode(
        Uint8List.sublistView(buffer, 0, decodedLength),
        allowMalformed: false,
      );
    }

    await for (final chunk in stream) {
      for (final byte in chunk) {
        if (byte == 0x0A) {
          yield decodeLine();
          length = 0;
          continue;
        }
        if (length >= maxLineBytes) {
          throw McpResponseLimitException(
            '$streamName line exceeded $maxLineBytes bytes.',
          );
        }
        buffer[length] = byte;
        length += 1;
      }
    }

    if (length > 0) {
      yield decodeLine();
    }
  }
}

String extractBoundedMcpTextContent(
  Object? rawContent, {
  required int maxCharacters,
}) {
  if (rawContent is! List) return '';

  final textParts = <String>[];
  var outputCharacters = 0;
  for (final entry in rawContent) {
    if (entry is! Map || entry['type'] != 'text') continue;
    final text = entry['text'];
    if (text is! String) continue;
    final separatorCharacters = textParts.isEmpty ? 0 : 1;
    if (text.length > maxCharacters - outputCharacters - separatorCharacters) {
      throw McpResponseLimitException(
        'MCP tool text exceeded $maxCharacters characters.',
      );
    }
    outputCharacters += separatorCharacters + text.length;
    textParts.add(text);
  }
  return textParts.join('\n');
}
