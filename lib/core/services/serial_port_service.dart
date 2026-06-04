import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';

/// A serial port that has been opened and is actively buffering incoming data.
class _OpenPort {
  _OpenPort({
    required this.port,
    required this.reader,
    required this.config,
  });

  final SerialPort port;
  final SerialPortReader reader;
  final SerialPortConfig config;

  /// Set immediately after construction (the subscription needs `this`).
  late final StreamSubscription<Uint8List> subscription;

  /// Ring buffer of bytes received since the last drain.
  final List<int> buffer = <int>[];

  /// Bytes dropped from the front of [buffer] due to the cap, reported once.
  int droppedBytes = 0;

  /// Last error emitted by the read stream (e.g. device unplugged).
  String? lastError;
}

/// Manages serial port discovery and buffered read/write sessions.
///
/// Desktop only (macOS / Windows / Linux) via `flutter_libserialport`.
/// Every method returns a JSON-encoded string so results can be handed
/// straight back to the LLM, mirroring [WifiService].
///
/// For binary analysis the reader supports a `hexdump` encoding, optional
/// framing (split on a delimiter or fixed length), a lightweight content hint
/// (text/binary heuristic) and detailed byte statistics. [decode] performs
/// deterministic, Python-`struct`-style unpacking so numeric fields are parsed
/// in code rather than by the LLM.
class SerialPortService {
  /// Maximum bytes retained per open port before the oldest are dropped.
  static const int _bufferCapBytes = 256 * 1024;

  /// Read-stream poll timeout (ms); bounds how long the reader isolate blocks.
  static const int _readerTimeoutMs = 500;

  final Map<String, _OpenPort> _openPorts = {};

  /// Serial ports are only available on desktop platforms.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Enumerate available serial ports with metadata (read-only).
  String listPorts() {
    if (!isSupported) return _notSupportedJson();
    try {
      final ports = <Map<String, dynamic>>[];
      for (final name in SerialPort.availablePorts) {
        final port = SerialPort(name);
        try {
          ports.add({
            'name': name,
            'description': port.description,
            'manufacturer': port.manufacturer,
            'product_name': port.productName,
            'serial_number': port.serialNumber,
            'vendor_id': port.vendorId,
            'product_id': port.productId,
            'transport': _transportName(port.transport),
            'is_open': _openPorts.containsKey(name),
          });
        } catch (e) {
          ports.add({'name': name, 'error': e.toString()});
        } finally {
          port.dispose();
        }
      }
      return jsonEncode({'count': ports.length, 'ports': ports});
    } catch (e) {
      appLog('[SerialPortService] listPorts error: $e');
      return jsonEncode({
        'error': true,
        'message': 'Failed to list serial ports: $e',
      });
    }
  }

  /// Open [portName] and start buffering incoming data.
  Future<String> open(
    String portName, {
    int baudRate = 9600,
    int dataBits = 8,
    String parity = 'none',
    int stopBits = 1,
    String flowControl = 'none',
  }) async {
    if (!isSupported) return _notSupportedJson();
    if (portName.isEmpty) {
      return jsonEncode({'error': true, 'message': 'port is required'});
    }
    if (_openPorts.containsKey(portName)) {
      return jsonEncode({
        'error': true,
        'message': 'Port $portName is already open. Call serial_close first.',
      });
    }
    if (!const [5, 6, 7, 8].contains(dataBits)) {
      return jsonEncode({
        'error': true,
        'message': 'data_bits must be one of 5, 6, 7, 8 (got $dataBits).',
      });
    }
    if (!const [1, 2].contains(stopBits)) {
      return jsonEncode({
        'error': true,
        'message': 'stop_bits must be 1 or 2 (got $stopBits).',
      });
    }
    if (!SerialPort.availablePorts.contains(portName)) {
      return jsonEncode({
        'error': true,
        'message': 'Port $portName not found. Available ports: '
            '${SerialPort.availablePorts.join(', ')}',
      });
    }

    final port = SerialPort(portName);
    SerialPortConfig? config;
    try {
      if (!port.openReadWrite()) {
        final err = SerialPort.lastError;
        port.dispose();
        return jsonEncode({
          'error': true,
          'message': 'Failed to open $portName: ${err ?? 'unknown error'}. '
              'It may be in use by another program, or on Linux your user may '
              'need to be in the "dialout" group.',
        });
      }

      config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = dataBits
        ..parity = _parityFromString(parity)
        ..stopBits = stopBits
        ..setFlowControl(_flowControlFromString(flowControl));
      port.config = config;

      final reader = SerialPortReader(port, timeout: _readerTimeoutMs);
      final open = _OpenPort(port: port, reader: reader, config: config);
      open.subscription = reader.stream.listen(
        (data) => _appendToBuffer(open, data),
        onError: (Object e) {
          open.lastError = e.toString();
          appLog('[SerialPortService] read stream error on $portName: $e');
        },
        cancelOnError: false,
      );
      _openPorts[portName] = open;

      appLog('[SerialPortService] opened $portName @ $baudRate baud');
      return jsonEncode({
        'success': true,
        'port': portName,
        'baud_rate': baudRate,
        'data_bits': dataBits,
        'parity': parity,
        'stop_bits': stopBits,
        'flow_control': flowControl,
        'message': 'Port opened. Incoming data is now buffered; '
            'call serial_read to retrieve it.',
      });
    } catch (e) {
      appLog('[SerialPortService] open error on $portName: $e');
      config?.dispose();
      try {
        if (port.isOpen) port.close();
      } catch (_) {}
      port.dispose();
      return jsonEncode({
        'error': true,
        'message': 'Failed to open $portName: $e',
      });
    }
  }

  /// Drain buffered incoming data from an open port.
  ///
  /// Supports `utf8` / `hex` / `hexdump` / `base64` encodings, an optional
  /// content hint, detailed statistics, and framing: when [frameDelimiterHex]
  /// or [frameLength] is given the buffer is split into complete frames and any
  /// trailing partial frame is retained for the next read.
  String read(
    String portName, {
    String encoding = 'utf8',
    int? maxBytes,
    bool clear = true,
    String? frameDelimiterHex,
    int? frameLength,
    int maxFrames = 200,
    bool includeStats = false,
  }) {
    if (!isSupported) return _notSupportedJson();
    final open = _openPorts[portName];
    if (open == null) {
      return jsonEncode({
        'error': true,
        'message': 'Port $portName is not open. Call serial_open first.',
      });
    }

    final hasDelimiter =
        frameDelimiterHex != null && frameDelimiterHex.trim().isNotEmpty;
    final hasFixed = frameLength != null && frameLength > 0;
    if (hasDelimiter || hasFixed) {
      return _readFramed(
        open,
        portName,
        encoding,
        frameDelimiterHex: hasDelimiter ? frameDelimiterHex : null,
        frameLength: hasFixed ? frameLength : null,
        maxFrames: maxFrames,
        includeStats: includeStats,
      );
    }

    final total = open.buffer.length;
    final take = (maxBytes != null && maxBytes >= 0 && maxBytes < total)
        ? maxBytes
        : total;
    final slice = open.buffer.sublist(0, take);
    if (clear) open.buffer.removeRange(0, take);

    final result = <String, dynamic>{
      'port': portName,
      'bytes_read': slice.length,
      'bytes_remaining': open.buffer.length,
      'encoding': encoding,
      'data': _decode(slice, encoding),
      'content_hint': _contentHint(slice),
    };
    if (includeStats) result['stats'] = _stats(slice);
    _attachBufferNotes(result, open);
    return jsonEncode(result);
  }

  /// Deterministically unpack bytes with a Python-`struct`-style [format].
  ///
  /// Input bytes come from [dataHex] (preferred) or, if [port] is given, from
  /// that open port's buffer (set [consume] to drain the parsed bytes).
  String decode({
    String? dataHex,
    String? port,
    required String format,
    List<String>? fields,
    bool consume = false,
  }) {
    List<int> bytes;
    _OpenPort? open;
    if (dataHex != null && dataHex.trim().isNotEmpty) {
      bytes = _parseHexString(dataHex);
    } else if (port != null && port.trim().isNotEmpty) {
      open = _openPorts[port];
      if (open == null) {
        return jsonEncode({
          'error': true,
          'message': 'Port $port is not open. Call serial_open first, or pass '
              'bytes via "data".',
        });
      }
      bytes = List<int>.from(open.buffer);
    } else {
      return jsonEncode({
        'error': true,
        'message': 'Provide either "data" (hex) or an open "port".',
      });
    }

    final decoded = _structDecode(bytes, format, fields);
    if (decoded['error'] == true) return jsonEncode(decoded);

    if (consume && open != null) {
      final consumed = (decoded['bytes_consumed'] as int?) ?? 0;
      final n = consumed <= open.buffer.length ? consumed : open.buffer.length;
      if (n > 0) open.buffer.removeRange(0, n);
      decoded['bytes_remaining'] = open.buffer.length;
    }
    return jsonEncode(decoded);
  }

  /// Write [data] to an open port.
  Future<String> write(
    String portName,
    String data, {
    String encoding = 'utf8',
  }) async {
    if (!isSupported) return _notSupportedJson();
    final open = _openPorts[portName];
    if (open == null) {
      return jsonEncode({
        'error': true,
        'message': 'Port $portName is not open. Call serial_open first.',
      });
    }
    try {
      final bytes = _encode(data, encoding);
      final written = open.port.write(
        Uint8List.fromList(bytes),
        timeout: 1000,
      );
      open.port.drain();
      return jsonEncode({
        'success': true,
        'port': portName,
        'bytes_written': written,
      });
    } catch (e) {
      appLog('[SerialPortService] write error on $portName: $e');
      return jsonEncode({
        'error': true,
        'message': 'Write failed on $portName: $e',
      });
    }
  }

  /// Close an open port and release its buffer.
  Future<String> close(String portName) async {
    if (!isSupported) return _notSupportedJson();
    final open = _openPorts.remove(portName);
    if (open == null) {
      return jsonEncode({
        'error': true,
        'message': 'Port $portName is not open.',
      });
    }
    await _disposeOpenPort(open);
    appLog('[SerialPortService] closed $portName');
    return jsonEncode({
      'success': true,
      'port': portName,
      'message': 'Closed $portName',
    });
  }

  /// Release every open port. Call on provider disposal.
  Future<void> dispose() async {
    final ports = _openPorts.values.toList();
    _openPorts.clear();
    for (final open in ports) {
      await _disposeOpenPort(open);
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _appendToBuffer(_OpenPort open, Uint8List data) {
    open.buffer.addAll(data);
    final overflow = open.buffer.length - _bufferCapBytes;
    if (overflow > 0) {
      open.buffer.removeRange(0, overflow);
      open.droppedBytes += overflow;
    }
  }

  String _readFramed(
    _OpenPort open,
    String portName,
    String encoding, {
    String? frameDelimiterHex,
    int? frameLength,
    required int maxFrames,
    required bool includeStats,
  }) {
    final buf = open.buffer;
    final frames = <List<int>>[];
    var consumedUpTo = 0;

    if (frameDelimiterHex != null) {
      final delim = _parseHexString(frameDelimiterHex);
      if (delim.isEmpty) {
        return jsonEncode({
          'error': true,
          'message': 'frame_delimiter must be valid hex (e.g. "0a" or "0d0a").',
        });
      }
      var idx = _indexOfSub(buf, delim, consumedUpTo);
      while (frames.length < maxFrames && idx != -1) {
        frames.add(buf.sublist(consumedUpTo, idx));
        consumedUpTo = idx + delim.length;
        idx = _indexOfSub(buf, delim, consumedUpTo);
      }
    } else {
      final len = frameLength!;
      while (frames.length < maxFrames && buf.length - consumedUpTo >= len) {
        frames.add(buf.sublist(consumedUpTo, consumedUpTo + len));
        consumedUpTo += len;
      }
    }

    if (consumedUpTo > 0) buf.removeRange(0, consumedUpTo);

    final allBytes = <int>[for (final f in frames) ...f];
    final result = <String, dynamic>{
      'port': portName,
      'encoding': encoding,
      'frame_count': frames.length,
      'frames': [for (final f in frames) _decode(f, encoding)],
      'partial_bytes_remaining': buf.length,
      'content_hint': _contentHint(allBytes),
    };
    if (includeStats) result['stats'] = _stats(allBytes);
    _attachBufferNotes(result, open);
    return jsonEncode(result);
  }

  void _attachBufferNotes(Map<String, dynamic> result, _OpenPort open) {
    if (open.droppedBytes > 0) {
      result['dropped_bytes'] = open.droppedBytes;
      result['note'] = 'Buffer cap reached; oldest bytes were dropped.';
      open.droppedBytes = 0;
    }
    if (open.lastError != null) {
      result['stream_error'] = open.lastError;
    }
  }

  Future<void> _disposeOpenPort(_OpenPort open) async {
    try {
      await open.subscription.cancel();
    } catch (_) {}
    try {
      open.reader.close();
    } catch (_) {}
    try {
      if (open.port.isOpen) open.port.close();
    } catch (_) {}
    try {
      open.config.dispose();
    } catch (_) {}
    try {
      open.port.dispose();
    } catch (_) {}
  }

  String _decode(List<int> bytes, String encoding) {
    switch (encoding.toLowerCase()) {
      case 'hex':
        return bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
      case 'hexdump':
        return _hexdump(bytes);
      case 'base64':
        return base64Encode(bytes);
      case 'utf8':
      default:
        // Tolerate partial/garbled frames rather than throwing.
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  List<int> _encode(String data, String encoding) {
    switch (encoding.toLowerCase()) {
      case 'hex':
        return _parseHexString(data);
      case 'base64':
        return base64Decode(data);
      case 'utf8':
      default:
        return utf8.encode(data);
    }
  }

  /// Canonical `hexdump -C` style: offset, two 8-byte hex groups, ASCII gutter.
  String _hexdump(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i += 16) {
      final end = math.min(i + 16, bytes.length);
      final chunk = bytes.sublist(i, end);
      final offset = i.toRadixString(16).padLeft(8, '0');

      final left = <String>[];
      final right = <String>[];
      for (var j = 0; j < 16; j++) {
        final cell = j < chunk.length
            ? chunk[j].toRadixString(16).padLeft(2, '0')
            : '  ';
        (j < 8 ? left : right).add(cell);
      }
      final hex = '${left.join(' ')}  ${right.join(' ')}';

      final ascii = chunk
          .map((b) => (b >= 0x20 && b <= 0x7e) ? String.fromCharCode(b) : '.')
          .join();

      sb.writeln('$offset  $hex  |$ascii|');
    }
    return sb.toString().trimRight();
  }

  /// Cheap text/binary heuristic to help the model pick an encoding.
  Map<String, dynamic> _contentHint(List<int> bytes) {
    if (bytes.isEmpty) {
      return {'likely_type': 'empty', 'printable_ratio': 0};
    }
    var printable = 0;
    var nulls = 0;
    for (final b in bytes) {
      if (b == 0) nulls++;
      if ((b >= 0x20 && b <= 0x7e) || b == 0x09 || b == 0x0a || b == 0x0d) {
        printable++;
      }
    }
    final ratio = printable / bytes.length;
    final String type;
    if (ratio > 0.95 && nulls == 0) {
      type = 'text';
    } else if (ratio < 0.30 || nulls > bytes.length * 0.1) {
      type = 'binary';
    } else {
      type = 'mixed';
    }
    return {
      'likely_type': type,
      'printable_ratio': double.parse(ratio.toStringAsFixed(2)),
    };
  }

  /// Byte distribution statistics (opt-in; helps spot framing/structure).
  Map<String, dynamic> _stats(List<int> bytes) {
    final counts = List<int>.filled(256, 0);
    for (final b in bytes) {
      counts[b]++;
    }
    var distinct = 0;
    for (final c in counts) {
      if (c > 0) distinct++;
    }

    final order = List<int>.generate(256, (i) => i)
      ..sort((a, b) => counts[b] - counts[a]);
    final topBytes = <Map<String, dynamic>>[];
    for (var i = 0; i < 5 && i < order.length; i++) {
      if (counts[order[i]] == 0) break;
      topBytes.add({
        'byte': '0x${order[i].toRadixString(16).padLeft(2, '0')}',
        'count': counts[order[i]],
      });
    }

    var entropy = 0.0;
    final n = bytes.length;
    if (n > 0) {
      for (final c in counts) {
        if (c > 0) {
          final p = c / n;
          entropy -= p * (math.log(p) / math.ln2);
        }
      }
    }

    return {
      'byte_count': n,
      'distinct_bytes': distinct,
      'null_bytes': counts[0],
      'entropy_bits_per_byte': double.parse(entropy.toStringAsFixed(2)),
      'top_bytes': topBytes,
    };
  }

  List<int> _parseHexString(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\s:,\-]'), '');
    final bytes = <int>[];
    for (var i = 0; i + 1 < cleaned.length; i += 2) {
      final parsed = int.tryParse(cleaned.substring(i, i + 2), radix: 16);
      if (parsed != null) bytes.add(parsed);
    }
    return bytes;
  }

  int _indexOfSub(List<int> haystack, List<int> needle, int from) {
    if (needle.isEmpty) return -1;
    for (var i = from; i + needle.length <= haystack.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  /// Python-`struct`-style decoder. Byte order: `<` little (default), `>`/`!`
  /// big. Types: x b B h H i I l L q Q f d, and `Ns` for an N-byte string.
  Map<String, dynamic> _structDecode(
    List<int> bytes,
    String format,
    List<String>? fields,
  ) {
    var fmt = format.trim();
    if (fmt.isEmpty) {
      return {'error': true, 'message': 'format is required'};
    }

    var endian = Endian.little;
    switch (fmt[0]) {
      case '<':
        endian = Endian.little;
        fmt = fmt.substring(1);
        break;
      case '>':
      case '!':
        endian = Endian.big;
        fmt = fmt.substring(1);
        break;
      case '=':
      case '@':
        fmt = fmt.substring(1);
        break;
    }

    final data = Uint8List.fromList(bytes);
    final bd = ByteData.sublistView(data);
    final values = <dynamic>[];
    final tokenRe = RegExp(r'(\d*)([xcbBhHiIlLqQfds])');
    var off = 0;
    var pos = 0;

    while (pos < fmt.length) {
      if (fmt[pos] == ' ') {
        pos++;
        continue;
      }
      final m = tokenRe.matchAsPrefix(fmt, pos);
      if (m == null) {
        return {
          'error': true,
          'message': 'Invalid format near "${fmt.substring(pos)}". '
              'Use chars: x b B h H i I l L q Q f d s.',
        };
      }
      pos = m.end;
      final countStr = m.group(1)!;
      final type = m.group(2)!;
      final count = countStr.isEmpty ? 1 : int.parse(countStr);

      if (type == 's') {
        final len = countStr.isEmpty ? 1 : count;
        if (off + len > data.length) {
          return _structShort(off + len, data.length);
        }
        values.add(
          utf8.decode(data.sublist(off, off + len), allowMalformed: true),
        );
        off += len;
        continue;
      }
      if (type == 'x') {
        off += count;
        continue;
      }

      final size = _structSize(type);
      for (var k = 0; k < count; k++) {
        if (off + size > data.length) {
          return _structShort(off + size, data.length);
        }
        final raw = _readStructValue(bd, off, type, endian);
        // jsonEncode rejects NaN/Infinity — stringify non-finite doubles.
        values.add(raw is double && !raw.isFinite ? raw.toString() : raw);
        off += size;
      }
    }

    final result = <String, dynamic>{
      'values': values,
      'bytes_consumed': off,
      'byte_order': endian == Endian.little ? 'little' : 'big',
    };
    if (fields != null && fields.isNotEmpty) {
      final named = <String, dynamic>{};
      for (var i = 0; i < values.length; i++) {
        named[i < fields.length ? fields[i] : 'field_$i'] = values[i];
      }
      result['fields'] = named;
    }
    return result;
  }

  Map<String, dynamic> _structShort(int needed, int have) => {
        'error': true,
        'message': 'Not enough bytes: need $needed, have $have.',
      };

  int _structSize(String type) {
    switch (type) {
      case 'b':
      case 'B':
      case 'c':
        return 1;
      case 'h':
      case 'H':
        return 2;
      case 'i':
      case 'I':
      case 'l':
      case 'L':
      case 'f':
        return 4;
      case 'q':
      case 'Q':
      case 'd':
        return 8;
      default:
        return 1;
    }
  }

  dynamic _readStructValue(ByteData bd, int off, String type, Endian endian) {
    switch (type) {
      case 'b':
        return bd.getInt8(off);
      case 'B':
      case 'c':
        return bd.getUint8(off);
      case 'h':
        return bd.getInt16(off, endian);
      case 'H':
        return bd.getUint16(off, endian);
      case 'i':
      case 'l':
        return bd.getInt32(off, endian);
      case 'I':
      case 'L':
        return bd.getUint32(off, endian);
      case 'q':
        return bd.getInt64(off, endian);
      case 'Q':
        return bd.getUint64(off, endian);
      case 'f':
        return bd.getFloat32(off, endian);
      case 'd':
        return bd.getFloat64(off, endian);
      default:
        return bd.getUint8(off);
    }
  }

  int _parityFromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'odd':
        return SerialPortParity.odd;
      case 'even':
        return SerialPortParity.even;
      case 'mark':
        return SerialPortParity.mark;
      case 'space':
        return SerialPortParity.space;
      case 'none':
      default:
        return SerialPortParity.none;
    }
  }

  int _flowControlFromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'xonxoff':
      case 'xon_xoff':
      case 'software':
        return SerialPortFlowControl.xonXoff;
      case 'rtscts':
      case 'rts_cts':
      case 'hardware':
        return SerialPortFlowControl.rtsCts;
      case 'dtrdsr':
      case 'dtr_dsr':
        return SerialPortFlowControl.dtrDsr;
      case 'none':
      default:
        return SerialPortFlowControl.none;
    }
  }

  String _transportName(int transport) {
    switch (transport) {
      case SerialPortTransport.usb:
        return 'usb';
      case SerialPortTransport.bluetooth:
        return 'bluetooth';
      case SerialPortTransport.native:
        return 'native';
      default:
        return 'unknown';
    }
  }

  String _notSupportedJson() => jsonEncode({
        'error': true,
        'message': 'Serial port access is only supported on desktop '
            '(macOS, Windows, Linux). Current platform: '
            '${Platform.operatingSystem}.',
      });
}

final serialPortServiceProvider = Provider<SerialPortService>((ref) {
  final service = SerialPortService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
