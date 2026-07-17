import '../../../../core/services/serial_port_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import 'mcp_tool_result_normalizer.dart';
import 'serial_port_tools.dart';

typedef SerialPlatformSupport = bool Function();

/// Exposes serial tools and directly executes every operation except open.
final class BuiltInSerialToolHandler {
  BuiltInSerialToolHandler({
    SerialPortService? serialPortService,
    SerialPlatformSupport? platformSupport,
  }) : _serialPortService = serialPortService,
       _platformSupport = platformSupport ?? _defaultPlatformSupport;

  static const List<String> toolNames = <String>[
    'serial_list_ports',
    'serial_open',
    'serial_read',
    'serial_decode',
    'serial_write',
    'serial_close',
  ];

  static const Set<String> _toolNameSet = <String>{...toolNames};

  final SerialPortService? _serialPortService;
  final SerialPlatformSupport _platformSupport;

  bool get isAvailable => _serialPortService != null;

  bool get canExposeDefinitions => isAvailable && _platformSupport();

  List<Map<String, dynamic>> get definitions => SerialPortTools.allTools;

  bool handles(String name) => _toolNameSet.contains(name);

  Future<McpToolResult> execute({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!handles(name)) {
      return _directDenial(name);
    }
    final serial = _serialPortService;
    if (serial == null) {
      throw StateError('Serial port service is unavailable');
    }

    try {
      switch (name) {
        case 'serial_list_ports':
          return _success(name, serial.listPorts());

        case 'serial_open':
          return _directDenial(name);

        case 'serial_read':
          final port = (arguments['port'] as String?)?.trim() ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'utf8';
          final maxBytes = (arguments['max_bytes'] as num?)?.toInt();
          final clear = (arguments['clear'] as bool?) ?? true;
          final frameDelimiter = arguments['frame_delimiter'] as String?;
          final frameLength = (arguments['frame_length'] as num?)?.toInt();
          final maxFrames = (arguments['max_frames'] as num?)?.toInt() ?? 200;
          final includeStats = (arguments['include_stats'] as bool?) ?? false;
          return _success(
            name,
            serial.read(
              port,
              encoding: encoding,
              maxBytes: maxBytes,
              clear: clear,
              frameDelimiterHex: frameDelimiter,
              frameLength: frameLength,
              maxFrames: maxFrames,
              includeStats: includeStats,
            ),
          );

        case 'serial_decode':
          final dataHex = arguments['data'] as String?;
          final port = (arguments['port'] as String?)?.trim();
          final format = arguments['format'] as String? ?? '';
          final fields = (arguments['fields'] as List?)
              ?.map((entry) => entry.toString())
              .toList();
          final consume = (arguments['consume'] as bool?) ?? false;
          return _success(
            name,
            serial.decode(
              dataHex: dataHex,
              port: port,
              format: format,
              fields: fields,
              consume: consume,
            ),
          );

        case 'serial_write':
          final port = (arguments['port'] as String?)?.trim() ?? '';
          final data = arguments['data'] as String? ?? '';
          final encoding = (arguments['encoding'] as String?) ?? 'utf8';
          return _success(
            name,
            await serial.write(port, data, encoding: encoding),
          );

        case 'serial_close':
          final port = (arguments['port'] as String?)?.trim() ?? '';
          return _success(name, await serial.close(port));
      }
      return _directDenial(name);
    } catch (error) {
      appLog('[McpToolService] Serial tool error ($name): $error');
      return _failure(name, error.toString());
    }
  }

  static bool _defaultPlatformSupport() => SerialPortService.isSupported;

  static McpToolResult _success(String toolName, String result) {
    return McpToolResultNormalizer.success(toolName: toolName, result: result);
  }

  static McpToolResult _directDenial(String toolName) {
    return _failure(
      toolName,
      'Serial tool $toolName must be invoked with user approval and '
      'cannot be executed directly.',
    );
  }

  static McpToolResult _failure(String toolName, String errorMessage) {
    return McpToolResultNormalizer.failure(
      toolName: toolName,
      errorMessage: errorMessage,
    );
  }
}
